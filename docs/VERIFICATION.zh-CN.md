# 验收矩阵

[English](VERIFICATION.md) · [文档索引](README.zh-CN.md)

状态以实际执行结果为准。**Not tested** 不是通过；编译、离屏渲染或单元测试不能替代硬件结果。

## 验证环境（2026-11-27）

| 项目 | 值 |
|---|---|
| 机器 | Mac mini（Apple M4，16 GB） |
| 系统 | macOS 27.3，build 26C5047e |
| Xcode / SDK | Xcode 27.2（27B52），macOS 27.2 SDK |
| Swift | 6.4.2（swiftlang-6.4.2.1.9） |
| XcodeGen | 2.46.0 |
| 部署目标 | macOS 26.0 |
| 构建签名 | ad-hoc（`CODE_SIGN_IDENTITY=-`），无 Developer ID，未公证 |

## 自动化结果

全部命令在仓库根目录执行。

| 命令 | 结果 |
|---|---|
| `swift test --package-path Packages/BlueLinkCore` | 44 项通过，0 失败 |
| `swift test --package-path Platform/MacIntegration` | 24 项执行：23 项通过，1 项硬件测试按设计跳过 |
| `xcodebuild test -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS'` | 19 项通过（状态呈现 8、本地化 4、UI 渲染/窗口 7） |
| `./scripts/test.sh` | 上述全部 + 边界与文档检查通过 |
| `./scripts/boundary-check.sh` | 通过：无禁止 import、私有 API、`unchecked Sendable`、真实蓝牙地址或部署版本漂移 |
| `./scripts/check-docs.sh` | 通过：中英文文档成对、关键截图存在、无失效本地链接 |
| `./scripts/package-dmg.sh` | Release 构建成功；DMG 3.6 MB、ZIP 3.2 MB 及 SHA256 生成 |
| DMG 挂载检查 | `BlueLink.app` 版本 1.0.0（1），`LSMinimumSystemVersion=26.0`，`LSUIElement=true`，ad-hoc 签名，已卸载 |

自动化覆盖：

| 类别 | 覆盖情况 |
|---|---|
| 初始化 | 无托管不操作、亮屏连接、息屏断开、unknown 保持（策略表驱动测试） |
| 恢复 | 启动时蓝牙未知→可用会补连接；蓝牙关闭恢复重建预算；display unknown→awake 不算新亮屏周期（新增测试） |
| 策略 | 独立开关、暂停持久化、手动断开本周期抑制、重复 wake 不刷新手动覆盖 |
| 电源/会话 | dark wake 不连接、系统睡眠断开、inactive/蓝牙不可用停止 |
| 并发 | 单设备单操作、快速事件、迟到回调、超时、取消、移除/暂停后不发新操作；连接中息屏补断开、断开中亮屏补连接（新增测试） |
| 重试 | 虚拟时钟、首试 + 有限退避、耗尽停止、不重复刷新预算；60 秒内第 4 次意外断连停止，下一亮屏恢复（新增测试） |
| 音频 | 连接与音频可用分离、UID 匹配、超时不重连蓝牙、尊重系统路由 |
| 配置 | schemaVersion、损坏/未知版本不覆盖、原子保存、暂停跨重启 |
| 本地化 | zh-Hans 代表性文案、插值键、Info.plist 蓝牙说明均命中；`zh-Hans.lproj` 已编译进 App |
| UI | 空状态、状态映射、真实 SwiftUI 视图离屏渲染；未做键盘/VoiceOver 实机走查 |

## 实机结果

| ID | 操作 | 结果 |
|---|---|---|
| M01 | App 选择已配对设备并手动连接/断开 | **Passed（平台+协调器层）**：`BLUELINK_REAL_DEVICE=1 … --filter RealDeviceTests` 通过，5.976 s。启动连接、手动断开、手动连接均与 IOBluetooth 实际状态一致；测试结束恢复进入前状态。设备为已授权测试设备，地址未写入仓库。 |
| M02 | 系统息屏 | Not tested：本轮未对远程/本机执行息屏操作。 |
| M03 | 亮屏自动恢复 | Not tested：依赖 M02。 |
| M04 | 长时间闲置至设备自身待机 | Not tested。 |
| M05 | 整机睡眠/唤醒与 dark wake | Not tested：未获授权让本机睡眠。策略层 dark wake 已由自动化覆盖。 |
| M06 | 连续快速息屏亮屏 | Not tested：策略/并发由单元测试覆盖，未实机。 |
| M07 | 设备掉电、离线、返回范围 | Not tested：有限重试与连续断连上限由单元测试覆盖；未实机拔电/回连。 |
| M08 | 切换手机、手动断开、暂停/恢复 | 部分：手动断开与暂停逻辑有自动化；未做实机手机抢占。 |
| M09 | 蓝牙关闭/恢复、拒绝授权 | 部分：策略与 transport 错误映射有自动化；未实机切换系统蓝牙。 |
| M10 | 多显示器、拔插、镜像 | Not tested。显示屏聚合由单元测试覆盖，未实机拔插。 |
| M11 | 登录启动、退出、重复启动 | Not tested：`SMAppService` 注册需在系统设置中确认；ad-hoc 构建下未做登录/重启往返验证。 |
| M12 | 其他输入设备、音频设备 | 部分：输入设备分类与选择器过滤有测试；未实机托管其他设备。 |
| M13 | 首选音频输出、用户切换 | 部分：CoreAudio 枚举/路由有测试；未实机验证音频输出设备出声。 |
| M14 | 分发产物和 Icon Composer | **部分通过**：`.icon` 已由 Xcode 编译为 `IconImageStack`，`ictool` 渲染 Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark；`NSWorkspace` 返回 512 pt 新图标；菜单栏模板资源可加载。DMG 可挂载。未在 Finder/Dock 逐一实机截图，未验证 16/32 pt 网格。 |
| M15 | 空闲驻留与重复事件 | Not tested：未做 Activity Monitor/Instruments 采样。架构无空闲轮询、无定时器。 |

## UI 与截图

- `docs/screenshots/menu-bar-panel-{en,zh}.png`：真实 `MenuBarPanel` 视图的离屏渲染（英文、zh-Hans，空状态）。
- `docs/screenshots/settings-*.png`：真实 SwiftUI 视图经 AppKit 离屏渲染（测试生成，非窗口截图）。
- `docs/screenshots/icon-*.png`：`ictool` 导出的真实 `.icon` 多外观渲染。
- 设置窗口与“添加设备”sheet 使用原生 `NSVisualEffectView` 毛玻璃背景；窗口非不透明、Form 滚动背景隐藏。Reduce Transparency 回退为不透明窗口。自动化断言窗口 `isOpaque == false`、背景透明，且存在 `.underWindowBackground`/`.behindWindow` 材质，并真实弹出 sheet 验证；未做真实桌面背景下的视觉截图对比。
- 设置窗口打开时会激活 App 并置前；accessor 测试验证窗口标识与可见性，跨应用前台切换未做自动化截图。
- 菜单栏设备列表按设备数固定高度（72–322 pt），避免 `MenuBarExtra` 中 `ScrollView` 高度塌缩；未在真实菜单栏逐设备数复测全部尺寸。
- 菜单栏图标在系统菜单栏拥挤时可能被 macOS 隐藏；截取过程中出现过该现象。这是系统溢出行为，未实现替代入口。

## 未验证假设

- 签名 App 包中 `SMAppService.mainApp` 的登录项注册/审批流程。
- 附表 TCC 蓝牙授权在签名变化后的持久性。
- 真实息屏/亮屏、dark wake、系统睡眠的事件顺序与耗时。
- 实际音频播放与首选输出切换的端到端效果。
- IOBluetooth 断开通知在每次活动后重注册的生命周期：尚未用连续两次真实掉线验证。
- 长时间空闲 CPU/内存与多设备并发上限。
