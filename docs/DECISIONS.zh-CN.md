# Architecture decision log

[English](DECISIONS.md) · [文档索引](README.zh-CN.md)

- **ADR-001 Accepted**：采用 Daybreak 当前工程组织（XcodeGen、Apps/MacApp/Core/UI/Localization/Tests，独立 Swift Package、Platform/MacIntegration、docs、branding）；只做 Mac，省略移动端与同步。BlueLink 的最低部署版本定为 macOS 26.0，Swift 6 strict concurrency。Daybreak 仅只读参考，未复制其代码。
- **ADR-002 Accepted**：只使用 Apple 公共 API，设备级控制；不使用私有 API、外部 CLI、日志解析、UI 自动化或蓝牙私有数据库。
- **ADR-003 Accepted**：纯策略表 + 事件驱动协调；值类型表达身份/事件/快照，协议仅用于平台边界，actor 管理共享可变状态；实际连接、目标意图、在途操作、音频可用性分开。过期回调不丢弃，必须观测实际状态后重新协调。
- **ADR-004 Accepted**：用户主动选择设备，手动覆盖、持久暂停、有限重试；默认不自动切换音频。暂停不改变当前连接，未知状态不执行自动操作。
- **ADR-005 Accepted（已实施）**：`AppIcon.icon` 是唯一编译进 App 的 App 图标，包含渐变背景与独立前后丝带层，由真实 Icon Composer 文档格式生成。由于传统 `AppIcon.appiconset` 与 `.icon` 同名会产生重复 rendition，传统资源重命名为 `AppIconLegacy.appiconset`，保留为品牌源与回退参考，不参与编译。`ictool` 已渲染 Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark；`NSWorkspace` 返回 512 pt 图标；Xcode 将 `.icon` 编译为 `IconImageStack`。
- **ADR-006 Accepted（部分实施）**：GitHub Actions 构建并测试 ad-hoc 产物；`.github/workflows/ci.yml` 与 `scripts/package-dmg.sh` 已落地。即使 CI 启用，也不得未经用户授权创建 Release、上传资产、签名或公证。名称 BlueLink、Bundle ID `dev.bluelink.mac`、MIT 许可证已写入工程；正式发布前仍需用户确认。
- **ADR-007 Accepted**：`.icon` 的深色/着色/透明外观由系统派生，不单独烘焙。后层丝带使用 `opacity: 0.72`，避免系统深色/着色外观把前后层压成同一平面；三种外观下均保留层次。默认外观不透明度仍为 1。
- **ADR-008 Accepted**：本地化使用 `Localizable.xcstrings` 与 `InfoPlist.xcstrings`，源语言英文，交付 zh-Hans。禁止用动态 `Text(String)` 承载需要翻译的字面量；条件文案、`.help`、错误摘要使用 `LocalizedStringKey`/`LocalizedStringResource`。App 测试检查代表性键、插值格式与 Info.plist 文案，防止字符串目录漂移。
- **ADR-009 Accepted**：诊断日志仅本地写入，默认脱敏蓝牙地址与设备标识；导出为纯文本。日志消息是 App 自有文案，随界面本地化；底层系统错误保留系统语言/技术原文并标记为系统错误，不做二次猜测翻译。
- **ADR-010 Accepted**：更新检查保持关闭。未配置 `BlueLinkUpdateRepository` 时不发起网络请求，不伪造 GitHub URL、版本号或发布状态；手动检查按钮在未配置时禁用并说明原因。
- **ADR-011 Accepted**：UI 快照测试使用 `NSHostingView` + `cacheDisplay` 离屏渲染真实视图，仅存在于测试目标；产品不添加调试窗口、测试入口或假数据。文档中的菜单栏与设置截图均标注为离屏渲染。
- **ADR-012 Accepted**：菜单栏项遵循 macOS 溢出规则，不额外创建常驻窗口或 Dock 图标来规避隐藏。菜单栏过满时用户可能看不到入口；该行为记录为已知限制，不用非公开 API 强制置顶。
- **ADR-013 Accepted**：真实硬件测试必须显式设置 `BLUELINK_REAL_DEVICE=1`，设备 ID/名称从环境读取；默认测试跳过。测试进入时记录连接状态，结束时恢复，避免改变用户当前音频/连接状态。
- **ADR-014 Accepted**：蓝牙可用性变化统一经 `.systemChanged` 进入协调器。启动时控制器状态可能为 unknown，随后变为 available；该转换重置预算并以 `bluetoothRecovered` 触发一次协调，避免“启动不连接、只有重新息屏亮屏才恢复”。亮屏周期只接受已确认的 display asleep→awake；display unknown→awake 不重置手动断开覆盖或断连预算。连接或断开完成迟到时，除保留真实观察外必须再次协调当前系统状态；若期间已息屏/亮屏，补发对应断开/连接。
- **ADR-015 Accepted**：自动重连除 5 次退避预算外，增加连续断连上限：60 秒内第 4 次意外断连停止自动重连并标记 `reconnectRateLimited`，仅在亮屏、蓝牙恢复、有效配置改变或显式重试时清零。成功连接不清零，避免 flapping 设备形成无界循环。IOBluetooth 断开通知在每次连接/断开回调后注销旧注册并重新注册，只有新注册成功后才释放旧注册，防止注册失败时丢失监视；该生命周期尚需连续两次真实掉线验证。
- **ADR-016 Accepted**：设置窗口由 `openSettings` 打开后，显式激活 App 并 `makeKeyAndOrderFront`/`orderFrontRegardless`。Settings 视图用 `NSViewRepresentable` 给宿主窗口打上稳定标识，既能在首次出现时提升，也能在窗口已存在时由菜单按钮再次置前。跨应用前台切换仍受系统激活策略约束，未使用私有 API。
- **ADR-017 Accepted**：关于页展示作者 Dylan Liu 的公开 GitHub 信息（头像、邮箱、GitHub 链接）。头像使用与 Daybreak 相同的公开 GitHub 地址，并内置同一图片作为离线回退，避免网络失败时显示首字母占位。版权文本为 © 2026 Dylan Liu；MIT 许可与 Info.plist 版权字段保持一致。
- **ADR-018 Accepted**：设置窗口与“添加设备”sheet 使用 `NSVisualEffectView`（`.underWindowBackground`、`.behindWindow`、`.active`）提供原生毛玻璃背景；宿主窗口设为非不透明、背景透明，Form 的滚动背景隐藏。Reduce Transparency 时回退为不透明 `windowBackgroundColor`，Increase Contrast 时叠加语义色。菜单栏设备列表因 `MenuBarExtra` 不给裸 `ScrollView` 固有高度，按设备数计算 72–322 pt 固定高度，超出滚动；engine 状态未就绪时显示加载占位，避免中间区域塌缩成空白。

## Reference snapshot

2026-11-27 从 `mentalfl0w/Daybreak` 默认 main 实际读取 AGENTS.md、README.md、Apps/MacApp/project.yml、CONTRIBUTING.md、docs/README.md、docs/DECISIONS.md、Daybreak.xcodeproj/project.pbxproj。根据当前贡献指南，CI 由 `.github/workflows/ci.yml` 构建并 ad-hoc 签名 Mac DMG。未读取用户本地未推送修改，不复制其源代码。参考链接：https://github.com/mentalfl0w/Daybreak/tree/main

## Open questions

- 真实息屏/亮屏、dark wake、系统睡眠的事件顺序、延迟与失败模式（策略层已测，硬件未测）。
- 签名 App 包中 `SMAppService` 登录项的注册、审批与重启行为。
- 蓝牙 TCC 授权在 ad-hoc 签名变化后的持久性。
- 实际音频播放与首选输出切换的端到端效果。
- 菜单栏拥挤导致入口不可见时的产品级缓解方式（不引入私有 API）。
- 更新仓库地址与正式分发签名条件；确定前不启用更新。
