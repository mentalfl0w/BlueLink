# Icon Composer — 导入说明

[English](README.md) · [文档索引](../../docs/README.zh-CN.md) · [项目概览](../../README.zh-CN.md)

BlueLink 的图标是两层干净的蓝牙丝带矢量路径。1024×1024 正方形画布，不含圆角裁切、投影、高光、描边光晕或预渲染玻璃。仓库提供独立的前后层 SVG 与等尺寸透明 PNG。背景由 Icon Composer 原生设置：渐变 `#30C8EE → #1977DE → #2446B9`（左上到右下）；若当前工具只支持两端色，使用 `#30C8EE → #2446B9`。`Background-reference.svg` 仅用于色彩参考，不是前景玻璃层。

## 重建图标

1. 在真实 Mac 上，用随 Xcode 提供的 Icon Composer 新建 macOS 图标，设置上述原生渐变背景。
2. 依次导入 `01-RearRibbon.svg`、`02-FrontRibbon.svg`，保留 1024 画布位置；若 SVG 导入器处理不一致，改用对应的透明 PNG。检查图层没有被二次缩放或重定位。
3. 在原生工具中调整玻璃、层组与透明度，不添加夸张效果。检查 Default / Dark / Clear light / Clear dark / Tinted light / Tinted dark，确保前后层可辨、对比清晰，16/32 px 仍可识别。
4. 保存真实的 `Apps/MacApp/AppIcon.icon`，纳入 XcodeGen target sources/resources，并核实编译配置。确认系统选择该图标，而不是旧 appiconset。具体集成以已安装的 Xcode/SDK 为准。
5. `Assets.xcassets/AppIconLegacy.appiconset` 是独立可用的传统兼容资源。不要将其中的预裁切图标导入 Icon Composer。macOS 26/27 构建优先使用 `.icon`；只有工具链确实受限时才使用 bitmap fallback，并记录原因。
6. 实测 Finder、Dock、设置、关于窗口与不同外观。`branding/BlueLink-AppIcon-Rounded.png` 只是静态宣传预览，不是系统渲染截图。

## 当前状态

`Apps/MacApp/AppIcon.icon` 是真实 Icon Composer 文档，也是唯一编译进 App 的图标。后层丝带 `opacity: 0.72`，确保 Dark/Tinted 下前后层仍可区分。传统 appiconset 已重命名为 `AppIconLegacy`，避免重复 rendition。`ictool` 已导出 Default / Dark / ClearLight / ClearDark / TintedLight / TintedDark，预览位于 `docs/screenshots/`。

官方参考：https://developer.apple.com/design/human-interface-guidelines/app-icons/ · https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer · https://developer.apple.com/icon-composer/
