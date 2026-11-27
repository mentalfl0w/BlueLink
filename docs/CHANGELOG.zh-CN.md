# Changelog / Evidence

[English](CHANGELOG.md) · [文档索引](README.zh-CN.md)

## 2026-11-27 — 1.0.0 实现交付

### 交付内容

- 完成 `Packages/BlueLinkCore`：设备/状态模型、策略表、重试、配置、端口与 `ConnectionEngine` 协调器。
- 完成 `Platform/MacIntegration`：IOBluetooth transport、蓝牙/显示屏/系统事件监视、音频路由、登录项、配置存储、脱敏诊断日志、更新检查（默认关闭）。
- 完成 `Apps/MacApp`：菜单栏面板、设备选择、设置（通用/设备/诊断/关于）、AppModel composition、中英文、真实 Icon Composer 图标、菜单栏模板。
- 新增 `scripts/generate-project.sh`、`build.sh`、`test.sh`、`boundary-check.sh`、`package-dmg.sh`，以及 `.github/workflows/ci.yml`。
- 新增 `README.md`、`README.zh-CN.md`、`CONTRIBUTING.md`、`LICENSE`、`docs/screenshots/`。

### 实际命令与结果

| 命令 | 结果 |
|---|---|
| `swift test --package-path Packages/BlueLinkCore` | 44 项通过 |
| `swift test --package-path Platform/MacIntegration` | 24 项执行，23 通过，1 项硬件测试跳过 |
| `xcodebuild test -project BlueLink.xcodeproj -scheme BlueLink -destination 'platform=macOS'` | 19 项通过 |
| `./scripts/test.sh` | 全部通过，边界与文档检查通过 |
| `./scripts/check-docs.sh` | 中英文文档成对、关键截图存在、无失效本地链接 |
| `BLUELINK_REAL_DEVICE=1 … --filter RealDeviceTests` | 通过，5.976 s；启动连接、手动断开、手动连接与系统状态一致，结束恢复初始状态 |
| `./scripts/package-dmg.sh` | 成功；`dist/BlueLink-1.0.0-1.dmg` 3.6 MB、`.zip` 3.2 MB、SHA256 生成 |
| DMG 挂载检查 | 版本 1.0.0（1），部署目标 26.0，`LSUIElement=true`，ad-hoc 签名；已卸载 |

验证环境：macOS 27.3（26C5047e）、Xcode 27.2（27B52）、macOS 27.2 SDK、Swift 6.4.2、XcodeGen 2.46.0、Mac mini M4 16 GB。

### 图标与本地化

- `Apps/MacApp/AppIcon.icon` 由真实 Icon Composer 文档编译；后层丝带 `opacity: 0.72`，`ictool` 已验证 Default/Dark/ClearLight/ClearDark/TintedLight/TintedDark。
- 传统 `AppIcon.appiconset` 重命名为 `AppIconLegacy.appiconset`，避免与 `.icon` 产生重复 rendition；新增 `MenuBarIcon.imageset` 模板。
- `Localizable.xcstrings`、`InfoPlist.xcstrings` 完成 zh-Hans；修复条件 `Text`、`.help`、诊断 On/Off、失败摘要、About 条目与日志文案的漏译。App 测试验证代表性与插值键。

### 评审修复

- 蓝牙可用性从 unknown→available 时通过 `.systemChanged` 重建预算并重新协调；删除无生产者的独立蓝牙事件。
- 连接完成时若已息屏，立即补发断开；断开完成时若期间已亮屏，恢复 `.connected` 意图并补发连接。
- 增加连续意外断连上限（60 秒 3 次），第 4 次停止自动重连并显示 `.reconnectRateLimited` 失败；下一亮屏或手动重试恢复。
- IOBluetooth 断开通知在每次连接/断开回调后替换注册，只有新注册成功后才释放旧注册，避免注册失败时丢失监视；需连续两次真机掉线复核。
- 设置窗口打开时激活 App 并将窗口置前；窗口通过 accessor 打标，已打开时再次点击也能提升。新增窗口生命周期测试。
- 关于页加入作者卡片（GitHub 头像 + 邮箱 + GitHub 链接），头像与 Daybreak 使用同一公开 GitHub 地址并内置离线回退；末尾与 Info.plist、LICENSE 的版权改为 © 2026 Dylan Liu。
- 产品文案与图标去具体设备类型，统一使用“蓝牙设备”/通用无线电图标。
- 设置窗口与“添加设备”sheet 增加原生毛玻璃背景（`NSVisualEffectView`，Reduce Transparency 时回退为不透明）；Form 滚动背景隐藏，避免盖住材质。
- 菜单栏设备列表按设备数固定高度（72–322 pt），修复 `MenuBarExtra` 中裸 `ScrollView` 高度塌缩导致中间区域空白；engine 状态未就绪时显示加载占位。
- 新增 5 项 Core 恢复/竞态测试，Core 总数 39→44；App 新增 3 项毛玻璃窗口断言（15→18）；消除 App 目标全部 Swift 编译警告，移除菜单栏图集未引用 PNG。

### 未验证 / 限制

- 未实测息屏、亮屏、系统睡眠、dark wake、长时间闲置恢复（M02–M07、M10）。
- 未验证签名包登录项注册/重启（M11）、其他输入设备/音频设备实机（M12）、音频输出设备实际出声（M13）、Finder/Dock 16/32 pt 图标（M14）、空闲资源（M15）。
- 产物为 ad-hoc 签名，未 Developer ID 签名、未公证；首个公开版本已于 2026-11-28 发布，见下文。
- 菜单栏拥挤时图标可能被 macOS 隐藏。

## 2026-11-28 — 文档与仓库整理

- 面向人的文档改为英文主文件 + 简体中文 `*.zh-CN.md` 对照：README、贡献指南、文档索引、全部规范与图标说明；每对文件都有语言切换链接。
- 重写中英文 README，使用 GitHub 支持的 HTML：居中图标、状态徽章、截图表格、功能与安全边界、构建命令、验证摘要和限制。
- 新增英文界面截图（菜单栏与全部设置页）；中文截图由同一测试重新生成。
- Agent 启动内容并入 `AGENTS.md`，补充文档、截图与验证规则，并移除临时 `specs/` 工作目录。
- 清除工作区中可重新生成的 `build/`、`dist/` 与 `.DS_Store` 产物。
- 新增 `scripts/check-docs.sh`，检查中英文成对、截图存在与本地 Markdown 链接；CI 与 `test.sh` 执行。
- 诊断页的设备详情全部本地化，补上重试、暂停、手动干预后缀；此前只翻译外层标签，Core 枚举原始值和后缀仍为英文。新增 locale 回归测试。
- 通过 SwiftUI 环境 locale 重新渲染诊断页截图，英文图不再出现中文系统状态。
- 更新验收与变更日志：Platform 24 项（1 项跳过）、App 19 项。
- 更新通道指向公开仓库 `mentalfl0w/BlueLink`；检查器读取 GitHub Release，不自动下载或安装。
- CI 增加标签/手动触发的发布路径：解析版本、打包未签名 DMG/ZIP/SHA256，并在构建、边界与文档检查通过后发布 GitHub Release。分支和 PR 运行保持只读。
- 创建公开 GitHub 仓库，配置 macOS、Swift、SwiftUI、Bluetooth、菜单栏应用、IOBluetooth 与桌面应用 topics。
- 发布首个公开版本 `v1.0.0`。

## 2026-11-28 — 1.0.1 修复

- CI 拆分构建与打包：先构建 Release app，再打包现有产物；`package-dmg.sh --no-build` 避免第二次编译。
- 修复 `build.sh` 在未设置 `BLUELINK_VERSION`/`BLUELINK_BUILD_NUMBER` 时无法构建的问题；SHA256 sidecar 现在写入可移植文件名，不再包含 runner 绝对路径。
- 更新检查在未认证 Releases API 不可用时回退到 GitHub Release 页面重定向，API 返回 403 不再直接导致检查失败。
- 发布说明改由 `scripts/generate-release-notes.sh` 按 Conventional Commit 类型生成；CI 在 release job 拉取完整标签历史并传给 `gh release create`。
- 应用版本升至 1.0.1。

## 2026-11-28 — 1.0.2

- 发布 1.0.2，验证新的 Conventional Commit 发布说明流水线；相对 1.0.1 无用户可见行为变化。
