# Asset Provenance

## App Icon

- File: `apps/ios/AIWindow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- Source: original project-specific geometric drawing in `scripts/render_app_icon.swift`
- Created: 2026-07-25
- Third-party inputs: none
- Embedded text or logos: none
- Output: 1024 x 1024 PNG, RGB, no alpha channel
- SHA-256: `518dc29d6115dba31812b6490a915a6c3a10238f569031cb60ec59a51e557dfc`

Rebuild the tracked bitmap on macOS with:

```sh
xcrun swift scripts/render_app_icon.swift \
  --overwrite \
  apps/ios/AIWindow/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

The flat palette and window/feed geometry are defined numerically in the
script. The asset does not copy or incorporate AI HOT, LINUX DO, Apple, or any
other third-party visual identity. The project licenses this original asset
under the repository's MIT License.
