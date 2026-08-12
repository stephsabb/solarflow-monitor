# Publication et mises à jour automatiques

## Préparation unique

1. Le dépôt est `stephsabb/solarflow-monitor`. Activer **Settings → Pages → Deploy from a branch**, dossier `/docs` sur `main`.
2. Générer la clé Sparkle :

   ```sh
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

3. Copier la valeur publique affichée dans `work/Info.plist`, sous la clé `SUPublicEDKey`.
4. L’app utilise déjà `https://stephsabb.github.io/solarflow-monitor/appcast.xml` dans **Configuration → Interface**.

La clé privée Sparkle reste dans le trousseau du Mac. Elle ne doit jamais être ajoutée au dépôt.

## Signature Apple

Installer un certificat **Developer ID Application**, puis définir :

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Nom (TEAMID)'
```

Pour la notarisation, enregistrer les identifiants avec `xcrun notarytool store-credentials`, puis définir `NOTARY_PROFILE`.

## Nouvelle version

Mettre à jour `CFBundleShortVersionString` et `CFBundleVersion` dans `work/Info.plist`, puis :

```sh
export GITHUB_OWNER='compte-github'
export GITHUB_REPOSITORY='solarflow-monitor'
export NOTARY_PROFILE='SolarFlowNotary'
Scripts/publish-release.sh
git add docs/appcast.xml
git commit -m 'Publie la nouvelle version'
git push
```

Le script compile l’app, embarque Sparkle, signe le paquet, le soumet à Apple,
agrafe et vérifie le ticket de notarisation, recrée l’archive notarifiée, crée la
GitHub Release et régénère le catalogue.
