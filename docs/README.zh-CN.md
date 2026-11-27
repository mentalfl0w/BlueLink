# 文档

[English](README.md) · [项目概览](../README.zh-CN.md) · [参与贡献](../CONTRIBUTING.zh-CN.md)

BlueLink 1.0.0 已实现并完成本地构建验证。自动化测试与实机 M01 通过；其余硬件场景在观察到结果前一律标记 **Not tested**。

所有维护中的规范都有英文主文件与简体中文对照。两版描述同一契约；若出现不一致，英文版本用于实现审查，行为语义始终以[连接策略](CONNECTION_POLICY.zh-CN.md)为准。

## 维护中的指南

| 文档 | 职责 |
|---|---|
| [连接策略](CONNECTION_POLICY.zh-CN.md) · [English](CONNECTION_POLICY.md) | 设备状态、事件、优先级、协调器契约与重试上限；行为语义唯一来源。 |
| [平台集成](PLATFORM_INTEGRATION.zh-CN.md) · [English](PLATFORM_INTEGRATION.md) | Apple 公共 API、权限、显示屏/蓝牙/音频边界与平台限制。 |
| [产品设计](PRODUCT_DESIGN.zh-CN.md) · [English](PRODUCT_DESIGN.md) | 菜单栏、设置信息架构、本地化、文案与图标规则。 |
| [实现计划](IMPLEMENTATION.zh-CN.md) · [English](IMPLEMENTATION.md) | 目录、阶段与交付状态。 |
| [验收矩阵](VERIFICATION.zh-CN.md) · [English](VERIFICATION.md) | 自动化结果、实机矩阵、截图与待验证项。 |
| [决策记录](DECISIONS.zh-CN.md) · [English](DECISIONS.md) | 已采纳 ADR、参考快照与开放问题。 |
| [变更日志](CHANGELOG.zh-CN.md) · [English](CHANGELOG.md) | 带日期的变更、实际执行的命令与观察结果。 |
| [图标说明](../branding/IconComposer/README.zh-CN.md) · [English](../branding/IconComposer/README.md) | Icon Composer 分层、原生外观与兼容资源。 |
| [参与贡献](../CONTRIBUTING.zh-CN.md) · [English](../CONTRIBUTING.md) | 构建、测试、本地化、文档、打包与签名政策。 |

`AGENTS.md` 面向 Agent，使用全英文，不属于面向人的文档集合。

## 快速验证

```sh
./scripts/test.sh
./scripts/package-dmg.sh
```

当前结果：Core 44 项通过；Platform 24 项执行、23 项通过、1 项硬件测试按设计跳过；App 19 项通过；边界与文档检查通过。实机 M01 单独通过。环境与证据见[验收矩阵](VERIFICATION.zh-CN.md)。

## 截图

测试目标会把真实 SwiftUI 视图离屏渲染为英文与简体中文两套：

- [菜单栏面板（中文）](screenshots/menu-bar-panel-zh.png) · [English](screenshots/menu-bar-panel-en.png)
- [设置 · 通用（中文）](screenshots/settings-general-zh.png) · [English](screenshots/settings-general-en.png)
- [设置 · 设备（中文）](screenshots/settings-devices-zh.png) · [English](screenshots/settings-devices-en.png)
- [设置 · 诊断（中文）](screenshots/settings-diagnostics-zh.png) · [English](screenshots/settings-diagnostics-en.png)
- [设置 · 关于（中文）](screenshots/settings-about-zh.png) · [English](screenshots/settings-about-en.png)
- 图标：[Default](screenshots/icon-default-256.png) · [Dark](screenshots/icon-dark-256.png) · [Tinted Light](screenshots/icon-tinted-light-200.png) · [Clear Light](screenshots/icon-clear-light-200.png)

以上均为离屏渲染，不是实时窗口截图。App 内没有截图模式或模拟数据。

## 维护规则

- 行为变化同步修改策略、测试、决策记录与变更日志。
- 每次交付记录日期、变更、实际命令与观察结果。
- 未实测场景写 **Not tested**；构建或离屏渲染不能替代硬件证据。
- 中英文对照保持结构一致，同一次改动中更新语言切换和交叉链接。
- 明确标注离屏渲染与实时截图，不得混用。
