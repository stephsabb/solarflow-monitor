import Foundation

protocol SolarFlowService: Sendable {
    func fetchSnapshot() async throws -> SolarFlowSnapshot
}

enum SolarFlowServiceError: LocalizedError {
    case invalidConfiguration(String)
    case unexpectedResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .unexpectedResponse: "Réponse cloud illisible."
        case .httpError(let status): "Le cloud a répondu avec le statut HTTP \(status)."
        }
    }
}
