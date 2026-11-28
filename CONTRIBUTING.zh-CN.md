# 参与 BlueLink 开发

BlueLink 是一款专注的 macOS 菜单栏应用。请把改动限制在产品边界内，保持事件驱动的连接策略，并如实说明验证范围。有证据的小改动比大范围重写更容易审查。

[English](CONTRIBUTING.md) · [项目概览](README.zh-CN.md) · [文档索引](docs/README.zh-CN.md)

## 环境与工具

- macOS 26 或更高；当前验证环境为 macOS 27.3、Xcode 27.2、Swift 6.4.2、Apple M4。
- XcodeGen 2.46：`brew install xcodegen`。
- 不需要开发者证书即可构建和测试；本地构建使用 ad-hoc 签名。
- 运行时不得依赖 XcodeGen、Xcode、`blueutil`、Hammerspoon 或其他外部进程。

## 唯一工程规格

`Apps/MacApp/project.yml` 是工程唯一来源，`BlueLink.xcodeproj` 由它生成，不要手改 `project.pbxproj`。

```sh
./scripts/generate-project.sh
```

修改工程设置后重新生成，并确认 `xcodebuild -list -project BlueLink.xcodeproj` 正常。

## 构建与测试

```sh
./scripts/build.sh                 # Debug
./scripts/build.sh Release         # Release
./scripts/test.sh                  # 全部包测试 + App 测试 + 边界检查
./scripts/boundary-check.sh        # 只跑边界检查
./scripts/package-dmg.sh           # DMG/ZIP + SHA256；不签名、不公证、不发布
```

也可直接运行：

```sh
swift test --package-path Packages/BlueLinkCore
swift test --package-path Platform/MacIntegration
xcodebuild -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS' test
```

## 目录边界

- `Packages/BlueLinkCore`：Foundation-only 的领域状态、策略、协调器、端口与纯逻辑测试。禁止 import AppKit、SwiftUI、IOBluetooth、CoreAudio 等平台框架。
- `Platform/MacIntegration`：IOBluetooth、AppKit/NSWorkspace、CoreGraphics、CoreAudio、ServiceManagement、配置存储与诊断适配，依赖 Core。
- `Apps/MacApp`：Composition root、菜单栏与设置视图、本地化、App 级测试。视图只调用 `AppModel`，不持有蓝牙句柄。
- `scripts/`：工程生成、构建、测试、边界检查、打包与文档检查。
- `.github/workflows/ci.yml`：在 macOS 上构建与打包；版本标签和手动触发会创建未签名 GitHub Release。
- `branding/`：图标分层与品牌源文件。`docs/`：产品/工程规范、证据与截图。

`scripts/boundary-check.sh` 会阻止 Core 引入 UI/蓝牙框架、私有 API、`unchecked Sendable`、真实蓝牙地址和部署版本漂移。真实蓝牙地址不得提交；测试使用 `AA-BB-CC-DD-EE-FF` 一类合成值。

## 测试策略

- **Core**：注入 fake transport 与虚拟时钟，覆盖策略顺序、暂停、手动覆盖、迟到回调、重试耗尽、配置损坏/未知版本。
- **Platform**：映射、通知生命周期、脱敏、配置存储；默认不触发真实硬件副作用。
- **App**：状态呈现映射、本地化键（含插值）与 Info.plist 文案、真实 SwiftUI 视图的 AppKit 离屏渲染。离屏渲染是测试专用，不向 App 添加调试窗口或测试入口。
- **硬件**：`RealDeviceTests` 需显式环境变量，地址来自环境，不写入仓库；进入测试前记录连接状态，结束时恢复。未获授权不得对输入设备运行。

```sh
BLUELINK_REAL_DEVICE=1 \
BLUELINK_TEST_DEVICE_ID=AA-BB-CC-DD-EE-FF \
BLUELINK_TEST_DEVICE_NAME="Test Device" \
swift test --package-path Platform/MacIntegration --filter RealDeviceTests
```

## 本地化与文档

- 文案在 `Apps/MacApp/Localization/Localizable.xcstrings` 与 `InfoPlist.xcstrings`，源语言英文，必须同时提供 zh-Hans。
- 插值键使用格式说明符（如 `Reconnecting · attempt %lld`）；新增文案后运行 App 测试，`LocalizationTests` 会检查代表性键与插值。
- 动态拼接的 `Text(String)` 不会自动本地化；条件文案使用 `LocalizedStringKey` / `LocalizedStringResource` 或 `String(localized:)`。
- 设备名称、蓝牙地址等用户数据不翻译。
- 面向人的 Markdown 必须有英文主文件和简体中文对照：`NAME.md` 与 `NAME.zh-CN.md`，两者互相链接。范围包括 README、贡献指南、文档索引、`docs/` 下全部规范，以及图标说明。`AGENTS.md` 面向 Agent，使用全英文。
- 英文截图使用 `-en` 后缀，中文截图使用 `-zh` 后缀；界面变化时两套同时更新。
- 行为变化同步修改策略、测试、决策记录和变更日志。每次交付在 `docs/CHANGELOG.zh-CN.md` 记录日期、变更、实际命令与结果。

## 截图

- 截图由 `UISnapshotTests` 生成，不手工修改 UI 图片。
- 测试通过 `NSHostingView` 渲染真实 SwiftUI 视图，并把英文、中文版本写入 `/tmp/bluelink-shots`。
- 只把审核过的图片复制到 `docs/screenshots`，并标注为离屏渲染，而不是实时窗口截图。
- 不得向 App 注入模拟设备、假状态或专用截图模式。

## 打包、签名与发布

- `scripts/package-dmg.sh` 生成 ad-hoc 本地产物，仅用于测试。它不是 Developer ID 签名，未公证，不能宣称 Gatekeeper 免提示。
- `BlueLinkUpdateRepository` 指向 `mentalfl0w/BlueLink`。Sparkle 使用稳定更新源 `https://github.com/mentalfl0w/BlueLink/releases/latest/download/appcast.xml`；自动检查和下载默认关闭，用户在设置中开启。没有有效 Sparkle 密钥的构建回退到手动 GitHub Releases 检查。
- 推送稳定版本标签会在构建、边界与文档检查通过后运行发布任务。稳定版会从 ZIP 生成并校验 `appcast.xml`，与 DMG、ZIP、SHA256 一同发布。EdDSA 私钥必须保存在仓库 secret `SPARKLE_EDDSA_PRIVATE_KEY_BASE64`，绝不提交。发布说明使用 GitHub 从已合并 PR 生成的 What's Changed；改动应通过 PR 合入。手动 `workflow_dispatch` 使用显式版本执行同样流程。
- 预发布标签不生成 appcast，保证 `releases/latest/download/appcast.xml` 始终指向稳定版。
- 未经用户明确授权，不得使用 Developer ID 签名、公证、上传资产、创建 Release、推 tag 或操作远程主机。
- 发布说明必须区分签名/公证状态与实测范围。

## 提交前检查

- [ ] 改动位于已记录的产品与安全边界内。
- [ ] `./scripts/test.sh` 通过，包括边界检查与文档检查。
- [ ] 新行为有能捕获合理回归的测试。
- [ ] 未提交真实蓝牙地址、凭据、令牌或签名身份。
- [ ] 行为或命令变化时，中英文文档同步更新。
- [ ] 界面变化时重新生成截图，并标注为离屏渲染。
- [ ] 最终报告说明通过项、未测试项与下一步安全动作。

## 文档与证据

行为语义以[连接策略](docs/CONNECTION_POLICY.zh-CN.md)为准，验证证据见[验收矩阵](docs/VERIFICATION.zh-CN.md)。每次交付在[变更日志](docs/CHANGELOG.zh-CN.md)记录日期、变更、实际命令与结果。未实测项写 **Not tested**；编译通过或离屏渲染不能替代硬件证据。
