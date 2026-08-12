# SolarFlow Monitor pour macOS

Petite application macOS native en SwiftUI pour afficher à distance l’état et l’historique de Zendure SolarFlow 800 Pro / 800 Plus. Le projet utilise Swift 6, une architecture simple Model / ViewModel / Service et se rafraîchit toutes les minutes lorsque le Mac est actif.

## Lancer immédiatement

1. Ouvrez `Package.swift` avec Xcode 16 ou plus récent.
2. Choisissez le schéma **SolarFlowMonitor** et la destination **My Mac**.
3. Cliquez sur Run (⌘R).

L’application apparaît dans la barre des menus. En ligne de commande, `swift run SolarFlowMonitor` fonctionne également.

L’écran principal affiche également quatre courbes compactes et lissées sur les dernières 24 heures : production solaire, consommation totale de la maison, niveau des batteries et importation réseau. Les graphiques partent de zéro ; l’injection négative n’est donc pas représentée sur la carte réseau. Les cartes utilisent les relevés locaux effectués chaque minute et se remplissent progressivement lorsque l’application fonctionne.

Une carte **Météo locale** occupe toute la largeur sous les graphiques. Renseignez une ville ou un code postal dans **Configuration → Météo locale**. L’application utilise le géocodage et les prévisions Open‑Meteo pour afficher l’état du ciel, la température, la couverture nuageuse et la durée d’ensoleillement prévue. Les données sont actualisées toutes les 30 minutes.

## Brancher l’accès Zendure Cloud

La fenêtre de configuration est organisée en trois onglets : **Équipement solaire**, **Énergie** et **Météo**. Chaque onglet regroupe uniquement les paramètres associés et tient dans la fenêtre sans défilement.

1. Dans l’application mobile Zendure, ouvrez **Profil → Clé d’autorisation Cloud**.
2. Copiez la clé affichée.
3. Dans SolarFlow Monitor, ouvrez **Configuration**, choisissez **Zendure Cloud**, collez la clé puis enregistrez.

Aucune URL ni aucun numéro de série n’est nécessaire : la clé contient la région cloud, et l’application détecte automatiquement le premier SolarFlow 800 Pro / Plus du compte. Elle s’authentifie auprès du service Home Assistant Zendure, récupère les paramètres de connexion MQTT puis reçoit les mesures en temps réel.

La clé n’est jamais envoyée ailleurs que vers l’adresse Zendure qu’elle contient. Ne la communiquez pas à un tiers.

## Activer l’historique

1. Cliquez sur l’engrenage dans la fenêtre de l’application.
2. Renseignez l’e-mail et le mot de passe utilisés pour vous connecter à l’application Zendure.
3. Enregistrez, puis cliquez sur l’icône en forme de graphique.

L’application récupère l’historique de chacun des SolarFlow 800 Pro / Plus détectés, puis additionne les deux équipements par période. Elle convertit les totaux reçus en Wh vers les kWh affichés et présente la production solaire, l’énergie fournie à la maison, l’énergie envoyée aux batteries et l’énergie restituée par les batteries. « Vers la maison » désigne uniquement la contribution des SolarFlow et non la consommation totale du logement couverte également par le réseau.

Le sélecteur placé sous le titre permet d’afficher les sept derniers jours, le mois en cours ou l’année en cours. La vue annuelle regroupe les valeurs par mois.

Le tableau affiche la date, la consommation totale de la maison, l’énergie fournie à la maison par les SolarFlow et la production solaire. Le chevron de chaque ligne révèle l’importation, l’injection, la charge et la décharge des batteries. Le graphique superpose la production solaire et l’énergie fournie par les SolarFlow, avec la consommation totale en courbe.

## Analyser le dimensionnement

Le bouton **Analyse** de la fenêtre d’historique ouvre un bilan des 30 derniers jours. Les totaux Zendure et Shelly permettent d’afficher immédiatement la production solaire, la consommation totale, la charge des batteries, l’import réseau, l’injection et le taux d’autoconsommation.

Les réglages proposent également la puissance totale des panneaux en Wc, la capacité totale des batteries en kWh et la capacité minimale restante configurée. Ces valeurs préparent les diagnostics de capacité et les futures simulations.

Les API d’énergie utilisées ici ne fournissent pas l’heure à laquelle la batterie a atteint 100 % ou son SOC minimal. SolarFlow Monitor enregistre donc, à partir de cette version, un échantillon local à chaque actualisation d’une minute : production, consommation, SOC et puissance réseau. La vue indique toujours le nombre de jours et d’heures réellement couverts. Elle ne conclut sur les événements horaires qu’après une couverture suffisante, idéalement 20 à 30 jours. Le Mac peut rester verrouillé, mais l’application doit être lancée ; aucune mesure artificielle n’est ajoutée pendant la veille ou lorsque l’application est fermée.

Dans le tableau, **Vers batteries** est l’énergie totale entrée dans les batteries pendant la période (charge), tandis que **Depuis batteries** est l’énergie totale restituée par les batteries (décharge). Ces valeurs sont des flux cumulés en kWh, pas le niveau de charge en pourcentage.

L’historique utilise les points d’accès privés employés par l’application mobile Zendure (`/auth/app/token`, `/productModule/device/queryDeviceListByConsumerId` et `/tdengine/device/solarFlow/energy`). Cette API n’est pas documentée officiellement par Zendure et peut changer sans préavis. La connexion par mot de passe doit être disponible sur le compte ; un compte créé uniquement avec Apple ou Google peut nécessiter la définition préalable d’un mot de passe Zendure.

## Ajouter le Shelly 3EM / Pro 3EM

Dans **Configuration → Shelly Cloud**, renseignez :

1. le serveur Shelly Cloud associé au compteur (par exemple `shelly-123-eu.shelly.cloud`) ;
2. le **Device Id** hexadécimal à 12 caractères du compteur (par exemple `c8c9a370537a`) ;
3. la clé d’authentification du compte Shelly.

Ces informations sont accessibles dans Shelly Smart Control, dans les informations de l’appareil et les paramètres d’autorisation du compte. Le **Decimal Id** et l’adresse IP ne doivent pas être utilisés dans le champ Device Id. L’application accepte le Shelly 3EM Gen1 (`SHEM-3`) et le Pro 3EM Gen2. Une fois la connexion validée, la puissance affichée pour la maison devient la consommation totale calculée ainsi : **sortie des SolarFlow + puissance nette mesurée au réseau**. L’historique ajoute l’importation et l’injection réseau puis applique la même formule aux énergies.

SolarFlow Monitor utilise également l’endpoint de statistiques employé par Shelly Smart Control (`/v2/statistics/power-consumption/em-3p`) pour récupérer à distance les consommations et injections historiques déjà conservées par Shelly Cloud. Cet endpoint n’est pas inclus dans la documentation publique stable et peut évoluer. Les compteurs locaux enregistrés à chaque actualisation restent utilisés comme solution de repli.

## Sécurité

La clé Cloud Zendure, le mot de passe Zendure et la clé Shelly sont regroupés dans une seule entrée du Trousseau macOS. Les réglages sont modifiés dans une copie temporaire et enregistrés en une seule fois. La clé Shelly est transmise uniquement au serveur Shelly configuré. L’e-mail, les adresses de serveurs et les identifiants d’appareils sont sauvegardés dans les préférences de l’application. L’application ne journalise pas les identifiants.

## Structure

```text
Sources/SolarFlowMonitor/
├── Model/SolarFlowSnapshot.swift
├── Model/EnergyHistoryDay.swift
├── Model/ShellyMeterSnapshot.swift
├── Service/SolarFlowService.swift
├── Service/ZendureCloudService.swift
├── Service/ZendureHistoryService.swift
├── Service/ShellyCloudService.swift
├── Service/ShellyHistoryStore.swift
├── Service/KeychainStore.swift
├── ViewModel/SolarFlowViewModel.swift
└── View/
    ├── ContentView.swift
    ├── HistoryView.swift
    └── SettingsView.swift
```
