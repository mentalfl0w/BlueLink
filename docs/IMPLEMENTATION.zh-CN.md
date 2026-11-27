# 实现计划（交给 OMP 执行）

[English](IMPLEMENTATION.md) · [文档索引](README.zh-CN.md)

从当前目录创建独立 BlueLink 项目，按 AGENTS.md 与规范完成可用 App，不停在规划。不复制 Daybreak 代码或功能。以当前 Daybreak main 的项目配置、贡献指南和决策日志为参照；源文件组织为：

```text
BlueLink/
  AGENTS.md / README.md / README.zh-CN.md / CONTRIBUTING.md
  Apps/MacApp/
    project.yml / BlueLinkMacApp.swift
    Core/                 # AppModel、composition root、生命周期
    UI/                   # MenuBar、Settings、DevicePicker、About、window frosting
    Localization/         # Localizable.xcstrings、InfoPlist.xcstrings
    Assets.xcassets/      # 本包已有资源
    AppIcon.icon          # 在 Mac 上生成并集成
    Tests/                # 必要 App-level tests
  Packages/BlueLinkCore/
    Package.swift / Sources/BlueLinkCore/ / Tests/BlueLinkCoreTests/
  Platform/MacIntegration/
    Package.swift / Sources/MacIntegration/ / Tests/MacIntegrationTests/
  BlueLink.xcodeproj/     # 由 XcodeGen 生成
  branding/ / docs/ / scripts/ / .github/workflows/ci.yml
```

Core 使用值类型和最小端口（BluetoothClient/SystemStateSource/Clock 等），策略 reducer、状态机、协调器（可注入 clock/transport）。Platform 负责系统适配、生命周期通知、设备调用、音频、登录项及必要持久化。AppModel @MainActor 订阅快照、发布用户意图；视图不持有蓝牙句柄。避免空壳 DDD、重复 store、每操作一个协议。Core 和 Platform 分别可 swift test。脚本检查 import boundaries，借鉴 Daybreak 当前 composition 规则。

## Phase A — 验证与骨架

检查本机 Swift/Xcode/macOS、当前 Daybreak 参考组织（若本地有 checkout 只读确认），确定 Bundle ID、最低部署版本（暂定 26.0）、Swift 6 strict。核对 IOBluetooth 公开 API、线程、通知、真实设备枚举，验证屏幕状态在当前 Mac 下可观察。通过正常 app 开发路径和单元测试验证，不引入用户可见测试模式；缺硬件时明确未测试。使用 XcodeGen 2.40+、本地 Swift Package；生成可构建 app skeleton。图标真实 .icon 的导入、编译验证可并行进行。

## Phase B — P0 垂直切片

Core 实现 CONNECTION_POLICY，注入假时钟和蓝牙客户端，先覆盖快速事件、暂停、超时/迟到回调；Platform 接入 workspace、display、IOBluetooth；App 实现设备选择、状态、暂停、手动操作、独立策略与配置恢复。真实设备获授权后验证息屏/亮屏和意外断连；无硬件也完成可运行切片和测试。禁止用定时 keepalive 或全局蓝牙控制掩盖缺陷。

## Phase C — 产品化

完成 Settings、权限/登录启动、音频首选（可选，默认关闭）、本地化、诊断、原生外观和正式图标集成。完整检查一次 UI，真实截图有则保存 docs/screenshots。更新检查：GitHub Releases API 仅在仓库确定后启用，语义版本比较、错误及网络状态；默认手动检查，可选低频检查，后台不做频繁请求。ad-hoc 分发下提供官方 release 下载入口，不静默替换。具备签名及 Sparkle 安全条件时才升级为安全自动安装，另记 ADR。不要虚构远端 URL、版本或发布状态。

## Phase D — QA 与交付

执行 VERIFICATION 中适用测试；测空闲 CPU、内存、无持续蓝牙操作、事件到发起连接延迟（与连接完成时间分开）。完成 CI、无签名构建、可重复 DMG/ZIP 脚本；获授权时对测试副本或 CI 产品 ad-hoc 签名验证，Developer ID/公证另列。无未完成 P0、假数据、不可用按钮。无法实测场景 Not tested，不要求专门测试机或下载模拟器，不阻塞已实现的阶段。更新 README 双语、贡献指南、DECISIONS、CHANGELOG，给出构建包路径及真实结果。未经授权不远端发布。

## 交付状态（2026-11-27）

| 阶段 | 状态 | 证据 |
|---|---|---|
| Phase A | 完成 | 环境/API 探测；XcodeGen 工程可生成、构建；`.icon` 编译并渲染多外观；Core/Platform 包骨架与测试可运行 |
| Phase B | 完成 | 策略表、协调器、重试、配置、IOBluetooth/显示/系统事件适配；App 设备选择、手动操作、暂停；44 Core + 24 Platform 测试通过（1 项硬件测试跳过） |
| Phase C | 完成 | 设置、登录项、音频路由、诊断、更新检查占位、中英文、真实图标、菜单栏模板、设置/添加设备毛玻璃窗口；19 App 测试通过 |
| Phase D | 完成（范围见限制） | `./scripts/test.sh` 全绿；M01 实机通过；DMG/ZIP + SHA256 生成并挂载核对；README/CONTRIBUTING/DECISIONS/CHANGELOG/VERIFICATION 更新 |

未完成/未验证项与原因见 `docs/VERIFICATION.md`：真实息屏/亮屏与睡眠（M02–M07、M10）、登录项重启（M11）、其他输入设备（M12）、实际出声（M13）、Finder/Dock 小尺寸（M14）、空闲资源采样（M15）。ad-hoc 产物未签名分发、未公证、未发布。
