# Icon Composer guide

[简体中文](README.zh-CN.md) · [Documentation](../../docs/README.md) · [Project overview](../../README.md)

BlueLink's icon is a two-layer Bluetooth ribbon drawn as clean vector paths. The canvas is 1024×1024 with no rounded mask, shadow, highlight, outer glow, or baked glass. Separate front/rear SVGs and matching transparent PNGs are provided. Icon Composer owns the background gradient: `#30C8EE → #1977DE → #2446B9` (top-left to bottom-right). If the tool accepts only two stops, use `#30C8EE → #2446B9`. `Background-reference.svg` is a color reference only, not a foreground layer.

## Rebuilding the icon

1. On a real Mac, create a macOS icon with the Icon Composer version bundled with Xcode. Set the native gradient background.
2. Import `01-RearRibbon.svg` and `02-FrontRibbon.svg` in that order and keep their 1024-canvas positions. If the SVG importer is inconsistent, use the matching transparent PNGs. Check that no layer is rescaled or moved.
3. Adjust glass, layer groups, and opacity in the native tool. Do not add exaggerated effects. Check Default / Dark / Clear light / Clear dark / Tinted light / Tinted dark; front and rear layers must remain distinct and legible at 16/32 px.
4. Save the real document as `Apps/MacApp/AppIcon.icon`. Include it in the XcodeGen target sources/resources and verify the compiled configuration. Confirm that macOS selects this icon, not the old appiconset. Follow the installed Xcode/SDK for integration details.
5. `Assets.xcassets/AppIconLegacy.appiconset` is an independent legacy fallback. Do not import its pre-cropped images into Icon Composer. macOS 26/27 builds use `.icon`; use the bitmap fallback only if the toolchain requires it, and record why.
6. Inspect Finder, Dock, Settings, the About window, and every appearance. `branding/BlueLink-AppIcon-Rounded.png` is a static promotional preview, not a system-rendered screenshot.

## Current status

`Apps/MacApp/AppIcon.icon` is a real Icon Composer document and the only compiled app icon. The rear ribbon uses `opacity: 0.72` so front and rear layers remain distinguishable in Dark and Tinted appearances. The legacy appiconset is renamed `AppIconLegacy` to avoid a duplicate rendition. `ictool` has exported Default / Dark / ClearLight / ClearDark / TintedLight / TintedDark; previews are in `docs/screenshots/`.

Official references: https://developer.apple.com/design/human-interface-guidelines/app-icons/ · https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer · https://developer.apple.com/icon-composer/
