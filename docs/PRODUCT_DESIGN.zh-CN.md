# Product design / 产品设计

[English](PRODUCT_DESIGN.md) · [文档索引](README.zh-CN.md)

## 视觉原则

参考当前 Daybreak 的原生内容优先、清晰语义、适度毛玻璃与系统控件，而不是复制壁纸 UI。macOS 26/27 最新 SDK，MenuBarExtra(.window) 或经验证的原生 NSStatusItem 方案。优先系统材质与控件；不全屏堆玻璃卡片，不做 Web dashboard、不使用固定灰背景模拟系统。支持亮暗模式、减少透明度/动画、VoiceOver、键盘导航。菜单栏不靠颜色单独传递状态。

## 信息架构

菜单栏：顶部 BlueLink、全局自动管理开关；紧凑托管设备列表（设备名称、图标、实际状态、连接/断开、暂停/恢复）；底部添加设备、设置、退出。失败时显示设备级可理解提示和重试；未添加设备则清晰空状态。一个设备时不展示过多层次，多设备时列表可滚动。

设置使用系统 Settings scene；设备页（已配对列表、策略独立开关、首选输出、移除托管）；通用（登录启动、全局管理、更新）；关于（图标、版本、项目/许可证）；高级诊断（实际/目标、屏幕/系统、最近错误、脱敏导出）。日常面板无需长解释；操作反馈及时，不展示伪成功。

首次运行：不接管任何设备；添加→请求必要权限→显示已配对列表→用户选择→确认策略→执行协调。输入设备默认隐藏或显著警告，当前用户的主要输入设备不可未经确认托管。支持取消，移除托管不取消系统配对。全局暂停不改变连接。手动断开后提示“本次亮屏期间不自动连接”，暂停则持续。

文案：亮屏时连接 / 息屏时断开 / 自动重连 / 系统休眠时断开 / 暂停自动管理 / 正在连接… / 已连接 / 等待设备 / 重试 / 登录时启动 / 检查更新。不要在界面出现内部类名、错误码或“状态收敛”术语；必要诊断可保留。采用 Localizable.xcstrings、InfoPlist.xcstrings，zh-Hans/en 完整，若增加 ja 必须完整。真实截图通过 App 拍摄或测试目标离屏渲染真实视图；不生成假产品数据，不添加专用截图模式。

## Icon — macOS 26/27

Apple HIG：1024² 分层画布，系统负责遮罩和动态效果；推荐 Icon Composer 原生多外观，而不是烘焙玻璃。见[图标说明](../branding/IconComposer/README.zh-CN.md)。提供独立前后丝带层、原生背景参考及传统图标资源。保留品牌图形的轮廓与蓝色渐变，不把整个圆角 PNG 作为 Icon Composer 前景。不将彩色 app icon 缩成菜单栏 icon；使用单色模板，检查 1x/2x。正式发布验收 Default/Dark/Clear/Tinted 外观和 Dock、Finder、菜单栏。视觉样稿非系统渲染截图。

已实现：`AppIcon.icon` 为唯一编译图标，传统资源改名 `AppIconLegacy` 保留为源；后层丝带 `opacity: 0.72`，保证 Dark/Tinted 下前后层可分。`ictool` 已导出 Default/Dark/Clear/ClearDark/TintedLight/TintedDark，截图在 `docs/screenshots/`。菜单栏面板使用 `MenuBarExtra(.window)`；菜单栏拥挤时由系统隐藏，未实现替代入口。设置窗口与“添加设备”sheet 使用原生 `NSVisualEffectView` 毛玻璃背景，Reduce Transparency 时回退为不透明窗口；Form 滚动背景隐藏，避免遮挡材质。菜单栏设备列表按设备数固定 72–322 pt 高度，超出滚动；engine 状态未就绪时显示加载占位。产品文案统一使用“蓝牙设备”，不再强调具体设备品类。
