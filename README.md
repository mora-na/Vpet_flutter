# VPet Flutter (Phase 1)

This directory is the cross-platform runtime prototype for VPet (mobile + Windows + macOS).

## What is implemented

- Flutter app scaffold
- Data-driven frame player for `Mu`
- Actions supported: `default`, `move`, `sleep`
- Asset export script from the existing VPet mod folders

## Prerequisites

- Flutter SDK installed locally (`flutter` command available)

## First run

```bash
cd vpet_flutter
python3 tools/export_mu_assets.py
flutter pub get
flutter run
```

## Asset source mapping

The exporter reads from:

- `../VPet-Simulator.Windows/mod/0000_core/pet/Mu/Default/Nomal/1`
- `../VPet-Simulator.Windows/mod/0000_core/pet/Mu/MOVE/walk.right/A_Nomal`
- `../VPet-Simulator.Windows/mod/0000_core/pet/Mu/MOVE/walk.right/B_Nomal`
- `../VPet-Simulator.Windows/mod/0000_core/pet/Mu/MOVE/walk.right/C_Nomal`
- `../VPet-Simulator.Windows/mod/0000_core/pet/Mu/Sleep/B_Nomal`

