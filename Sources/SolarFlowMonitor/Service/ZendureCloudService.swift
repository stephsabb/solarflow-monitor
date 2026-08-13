import CryptoKit
import Foundation
import Network

struct CloudConfiguration: Equatable, Sendable {
    var cloudKey = ""
    var zendureEmail = ""
    var zendurePassword = ""
    var shellyServer = ""
    var shellyDeviceID = ""
    var shellyAuthKey = ""
    var panelPowerWp = 0.0
    var batteryCapacityKWh = 0.0
    var minimumSOCPercent = 10
    var weatherLocation = ""
    var appearanceMode = "automatic"
    var updateFeedURL = "https://stephsabb.github.io/solarflow-monitor/appcast.xml"
    var automaticallyChecksForUpdates = true
}

actor ZendureCloudService: SolarFlowService {
    private struct Device: Decodable, Sendable {
        let deviceKey: String
        let productKey: String
        let productModel: String
    }

    private struct MQTTSettings: Decodable, Sendable {
        let url: String
        let clientId: String
        let username: String
        let password: String
    }

    private struct APIEnvelope: Decodable, Sendable {
        struct Payload: Decodable, Sendable {
            let deviceList: [Device]
            let mqtt: MQTTSettings
        }
        let code: Int
        let success: Bool
        let data: Payload?
        let msg: String?
    }

    private let cloudKey: String
    private var client: MQTTClient?
    private var devices: [Device] = []
    private var valuesByDevice: [String: [String: Int]] = [:]
    private var lastMessageByDevice: [String: Date] = [:]

    init(cloudKey: String) { self.cloudKey = cloudKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    func fetchSnapshot() async throws -> SolarFlowSnapshot {
        if let latest = lastMessageByDevice.values.max(), Date().timeIntervalSince(latest) > 90 {
            // Zendure may close an MQTT session without a visible HTTP error.
            // Never keep presenting a dead session indefinitely.
            client?.disconnect()
            client = nil
            try await connect()
        } else if client == nil {
            try await connect()
        }
        guard let client, !devices.isEmpty else {
            throw SolarFlowServiceError.unexpectedResponse
        }

        for device in devices {
            let request: [String: Any] = [
                "deviceId": device.deviceKey,
                "messageId": Int.random(in: 1...999_999),
                "timestamp": Int(Date().timeIntervalSince1970),
                "properties": ["getAll"]
            ]
            let payload = try JSONSerialization.data(withJSONObject: request)
            client.publish(topic: "iot/\(device.productKey)/\(device.deviceKey)/properties/read", payload: payload)
        }
        try await Task.sleep(for: .milliseconds(valuesByDevice.count < devices.count ? 1_200 : 350))

        let available = devices.compactMap { device -> [String: Int]? in
            guard let updated = lastMessageByDevice[device.deviceKey],
                  Date().timeIntervalSince(updated) < 300 else { return nil }
            return valuesByDevice[device.deviceKey]
        }
        guard !available.isEmpty, let updated = lastMessageByDevice.values.max() else {
            throw SolarFlowServiceError.invalidConfiguration("Connexion établie, mais aucune mesure reçue. Vérifiez que l’appareil est en ligne.")
        }
        let aggregate = ZendureSolarFlow.aggregate(available, updatedAt: updated)
        return SolarFlowSnapshot(
            solarPowerWatts: aggregate.solarPowerWatts,
            homePowerWatts: aggregate.homePowerWatts,
            batteryLevelPercent: aggregate.batteryLevelPercent,
            batteryPowerWatts: aggregate.batteryPowerWatts,
            connectionState: available.count == devices.count ? .connected : .disconnected,
            updatedAt: aggregate.updatedAt
        )
    }

    private func connect() async throws {
        guard let decoded = Data(base64Encoded: cloudKey),
              let content = String(data: decoded, encoding: .utf8),
              let split = content.lastIndex(of: ".") else {
            throw SolarFlowServiceError.invalidConfiguration("La clé Cloud Zendure n’est pas valide.")
        }
        let apiURL = String(content[..<split])
        let appKey = String(content[content.index(after: split)...])
        guard let url = URL(string: apiURL + "/api/ha/deviceList") else {
            throw SolarFlowServiceError.invalidConfiguration("La clé contient une adresse cloud invalide.")
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let nonce = String(Int.random(in: 10_000...99_999))
        let secret = "C*dafwArEOXK"
        let bodyString = "appKey\(appKey)nonce\(nonce)timestamp\(timestamp)"
        let digest = Insecure.SHA1.hash(data: Data("\(secret)\(bodyString)\(secret)".utf8))
        let signature = digest.map { String(format: "%02X", $0) }.joined()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: ["appKey": appKey])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(timestamp), forHTTPHeaderField: "timestamp")
        request.setValue(nonce, forHTTPHeaderField: "nonce")
        request.setValue("zenHa", forHTTPHeaderField: "clientid")
        request.setValue(signature, forHTTPHeaderField: "sign")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SolarFlowServiceError.unexpectedResponse
        }
        let envelope = try JSONDecoder().decode(APIEnvelope.self, from: data)
        guard envelope.code == 200, envelope.success, let payload = envelope.data else {
            throw SolarFlowServiceError.invalidConfiguration(envelope.msg ?? "Clé refusée par Zendure.")
        }
        let supported = payload.deviceList.filter { ZendureSolarFlow.matches($0.productModel) }
        guard !supported.isEmpty else {
            throw SolarFlowServiceError.invalidConfiguration("Aucun contrôleur SolarFlow compatible trouvé sur ce compte.")
        }
        devices = supported

        let mqtt = try MQTTEndpoint(payload.mqtt.url)
        let newClient = MQTTClient(
            host: mqtt.host,
            port: mqtt.port,
            useTLS: mqtt.useTLS,
            clientID: payload.mqtt.clientId,
            username: payload.mqtt.username,
            password: payload.mqtt.password
        )
        newClient.onPayload = { [weak self] topic, data in
            Task { await self?.consume(topic: topic, data: data) }
        }
        client = newClient
        try await newClient.connect()
        for device in devices {
            newClient.subscribe(topic: "/\(device.productKey)/\(device.deviceKey)/#")
            newClient.subscribe(topic: "iot/\(device.productKey)/\(device.deviceKey)/#")
        }
    }

    private func consume(topic: String, data: Data) {
        let topicParts = topic.split(separator: "/")
        guard topicParts.count >= 3 else { return }
        let deviceIndex = topic.hasPrefix("/") ? 1 : 2
        guard topicParts.indices.contains(deviceIndex) else { return }
        let deviceID = String(topicParts[deviceIndex])
        guard devices.contains(where: { $0.deviceKey == deviceID }) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["isHA"] == nil else { return }
        var deviceValues = valuesByDevice[deviceID, default: [:]]
        let dataObject = (object["data"] as? [String: Any]) ?? object
        let properties = (dataObject["properties"] as? [String: Any]) ?? dataObject
        deviceValues.merge(ZendureSolarFlow.canonicalValues(properties: properties, data: dataObject)) { _, new in new }
        if !deviceValues.isEmpty {
            valuesByDevice[deviceID] = deviceValues
            lastMessageByDevice[deviceID] = .now
        }
    }

}

private struct MQTTEndpoint {
    let host: String
    let port: UInt16
    let useTLS: Bool

    init(_ raw: String) throws {
        var value = raw
        let tls = value.hasPrefix("mqtts://")
        value = value.replacingOccurrences(of: "mqtts://", with: "").replacingOccurrences(of: "mqtt://", with: "")
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard let host = parts.first, !host.isEmpty else { throw SolarFlowServiceError.unexpectedResponse }
        self.host = host
        self.port = UInt16(parts.count > 1 ? parts[1] : "1883") ?? 1883
        self.useTLS = tls || port == 8883
    }
}

private final class MQTTClient: @unchecked Sendable {
    private let connection: NWConnection
    private let clientID: String
    private let username: String
    private let password: String
    private let queue = DispatchQueue(label: "SolarFlowMonitor.MQTT")
    private var buffer = Data()
    private var packetID: UInt16 = 1
    private var keepAliveTimer: DispatchSourceTimer?
    var onPayload: (@Sendable (String, Data) -> Void)?

    init(host: String, port: UInt16, useTLS: Bool, clientID: String, username: String, password: String) {
        let parameters = useTLS ? NWParameters.tls : NWParameters.tcp
        self.connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        self.clientID = clientID
        self.username = username
        self.password = password
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let resumed = ResumeGate()
            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(self.connectPacket())
                    self.startKeepAlive()
                    resumed.once {
                        continuation.resume()
                    }
                case .failed(let error):
                    resumed.once {
                        continuation.resume(throwing: error)
                    }
                default: break
                }
            }
            connection.start(queue: queue)
            receive()
        }
    }

    func subscribe(topic: String) {
        packetID &+= 1
        var body = Data([UInt8(packetID >> 8), UInt8(packetID & 0xff)])
        body.append(mqttString(topic)); body.append(0)
        send(packet(type: 0x82, body: body))
    }

    func publish(topic: String, payload: Data) {
        var body = mqttString(topic); body.append(payload)
        send(packet(type: 0x30, body: body))
    }

    func disconnect() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        send(Data([0xE0, 0x00]))
        connection.cancel()
    }

    private func connectPacket() -> Data {
        var body = mqttString("MQIsdp")
        body.append(3); body.append(0xC2); body.append(contentsOf: [0, 30])
        body.append(mqttString(clientID)); body.append(mqttString(username)); body.append(mqttString(password))
        return packet(type: 0x10, body: body)
    }

    private func packet(type: UInt8, body: Data) -> Data {
        var result = Data([type]); var length = body.count
        repeat { var byte = UInt8(length % 128); length /= 128; if length > 0 { byte |= 128 }; result.append(byte) } while length > 0
        result.append(body); return result
    }

    private func mqttString(_ value: String) -> Data {
        let data = Data(value.utf8)
        return Data([UInt8(data.count >> 8), UInt8(data.count & 0xff)]) + data
    }

    private func send(_ data: Data) { connection.send(content: data, completion: .contentProcessed { _ in }) }

    private func startKeepAlive() {
        guard keepAliveTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
        timer.resume()
        keepAliveTimer = timer
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data { self.buffer.append(data); self.parsePackets() }
            if error == nil { self.receive() }
        }
    }

    private func parsePackets() {
        while buffer.count > 2 {
            let bytes = [UInt8](buffer); var multiplier = 1; var length = 0; var index = 1
            repeat { guard index < bytes.count else { return }; let byte = bytes[index]; length += Int(byte & 127) * multiplier; multiplier *= 128; index += 1; if byte & 128 == 0 { break } } while multiplier <= 2_097_152
            guard bytes.count >= index + length else { return }
            let type = bytes[0] >> 4
            let body = Data(bytes[index..<(index + length)])
            buffer.removeFirst(index + length)
            if type == 3, body.count >= 2 {
                let topicLength = Int(body[0]) << 8 | Int(body[1])
                guard body.count >= 2 + topicLength else { continue }
                let qos = (bytes[0] >> 1) & 0x03
                let payloadStart = 2 + topicLength + (qos > 0 ? 2 : 0)
                if payloadStart <= body.count,
                   let topic = String(data: body.dropFirst(2).prefix(topicLength), encoding: .utf8) {
                    onPayload?(topic, body.dropFirst(payloadStart))
                }
            }
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func once(_ action: () -> Void) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        action()
    }
}
