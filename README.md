# Screen Brightness

Petite app de barre des menus macOS pour régler la luminosité **de chaque écran**, externes compris — là où le module « Moniteur » du Centre de contrôle reste grisé pour les écrans externes.

- Un slider par écran, au style du Centre de contrôle (Liquid Glass sur macOS 26+).
- Écrans externes pilotés en **DDC/CI** (le protocole que le moniteur utilise pour ses propres menus OSD) — la vraie luminosité du rétroéclairage, pas un filtre logiciel.
- **Gradation combinée** (façon BetterDisplay / Lunar) : au‑dessus de 20 % le slider règle le rétroéclairage en DDC ; en dessous, le rétroéclairage reste au minimum et l'image est assombrie en logiciel (table gamma) jusqu'au **noir complet à 0 %**, comme l'écran d'un MacBook.
- Écran externe sans DDC : gradation logicielle seule (gamma) sur toute la plage.
- Écran intégré (MacBook, iMac) piloté via le framework système DisplayServices.
- Détection automatique au branchement / débranchement / réveil.
- Option « Ouvrir au démarrage ».

## Prérequis

- Mac **Apple Silicon** (le chemin DDC utilise `IOAVService`, propre aux puces M).
- macOS 14 ou plus récent.
- Xcode (ou les Command Line Tools) pour compiler.
- Un moniteur avec **DDC/CI activé** dans son menu OSD (c'est le cas par défaut sur la plupart).

> ⚠️ Sur le port HDMI intégré de certains Mac (Mac mini M1, MacBook Pro M1/M2), le DDC ne passe pas : préférez USB‑C/DisplayPort. L'écran est alors assombri uniquement en logiciel (gamma), sans toucher au rétroéclairage.

## Installer

```bash
make install   # compile, copie dans /Applications et lance
```

Ou seulement compiler : `make app` → `build/ScreenBrightness.app`.

L'app est signée ad‑hoc : si Gatekeeper bloque un exemplaire copié depuis une autre machine, clic droit → Ouvrir.

## Architecture

```
Sources/ScreenBrightness/
├── ScreenBrightnessApp.swift     MenuBarExtra (.window)
├── Model/
│   ├── DisplayItem.swift         un écran : nom, luminosité 0…1, backend
│   └── DisplayController.swift   état observable, écritures coalescées, refresh auto
├── Hardware/
│   ├── DDC.swift                 trames DDC/CI (VCP 0x10) via IOAVService
│   ├── AVServiceLocator.swift    associe chaque CGDisplay à son service I²C (IORegistry)
│   ├── BuiltInDisplay.swift      écran intégré via DisplayServices
│   ├── GammaDimmer.swift         gradation logicielle : table gamma d'origine × facteur
│   └── DisplayHardware.swift     découverte + routage, répartition DDC / gamma (seuil 20 %)
└── UI/                           panneau façon Centre de contrôle
```

Tout l'accès matériel passe par une file série en arrière-plan ; un drag de slider n'envoie jamais plus d'une commande DDC en vol par écran.

La table gamma d'origine de chaque écran est capturée avant sa première gradation et rétablie quand il remonte à 100 % de sa plage logicielle. macOS réinitialise le gamma au branchement, au réveil ou lors d'un changement ColorSync : les gradations actives sont réappliquées après chaque redécouverte. À la fermeture de l'app, `CGDisplayRestoreColorSyncSettings()` remet tous les écrans à leur profil d'origine.
