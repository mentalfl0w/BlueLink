# macOS 平台集成

[English](PLATFORM_INTEGRATION.md) · [文档索引](README.zh-CN.md)

## 证据与参考

用户已经实测 blueutil 连接/断开已授权测试设备正常。不得将该结果等同于 BlueLink、长时间深度待机、系统睡眠或音频恢复实测。调研时读以下实际源码和许可证，记录 revision：

- https://github.com/toy/blueutil — 设备枚举、openConnection、closeConnection、通知及确认；不要照搬私有蓝牙开关 API。
- https://github.com/six6liu/macos-bluetooth-disconnect-on-display-sleep — 需求对照，不继承日志脚本。
- https://github.com/odlp/bluesnooze 、 https://github.com/root913/bluenap — 休眠管理与选择性操作参考，不沿用私有接口。
- https://github.com/lapfelix/BluetoothConnector 、 https://github.com/Hammerspoon/hammerspoon — 原生事件及经典设备控制参考。
- https://c-command.com/toothfairy/ — 交互和音频状态参考。

Apple 官方： [IOBluetooth](https://developer.apple.com/documentation/iobluetooth)、[IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice)、[NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)、[CoreGraphics](https://developer.apple.com/documentation/coregraphics/quartz-display-services)、[CoreAudio](https://developer.apple.com/documentation/coreaudio)、[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)。具体 Swift 签名以本机 SDK 为准。

## Display / system events

在 NSWorkspace.shared.notificationCenter 监听 screensDidSleep/ Wake、willSleep/ didWake、sessionDidBecomeActive/ResignActive。用 CGGetOnlineDisplayList、CGDisplayIsAsleep 和公开 display reconfiguration callback 做初始化与变化确认。多屏至少一个实际可用屏幕醒着则 awake；全休眠则 asleep；无法判断、无头、虚拟屏歧义为 unknown。锁屏、屏保、会话切换、系统 dark wake 和物理显示器关机分别建模。物理关机若系统无可观察变化则不承诺支持。无需 Screen Recording 或 Accessibility。`pmset displaysleepnow` 只可在本地获授权测试使用。

## Bluetooth adapter

优先 IOBluetoothDevice.pairedDevices() 与公开地址构造、openConnection（优先异步公开回调与 page timeout）、closeConnection、isConnected、registerForConnectNotifications、registerForDisconnectNotification，管理 IOBluetoothUserNotification 生命周期。断开通知与当前链路绑定，因此每次连接/断开回调后先注销旧注册再重新注册，确保下一次掉线仍能观察到；若系统把注册视为持久，替换而非叠加也避免重复回调。此生命周期需在实机上以连续两次掉线验证。ObjC 回调与 RunLoop/线程约束先以小型编译验证、正常产品路径和实机测试确认。同步 API 不得阻塞 UI，须验证后台执行的线程/RunLoop要求。查询失败与无设备分开；若原生枚举不可靠，可评估系统自带 system_profiler 的结构化输出作为低频一次性兼容路径，需记录原因与耗时，不作为实时控制。BLE/GATT 设备不保证支持经典连接接口。

状态权限/蓝牙电源观测只使用经 SDK 验证的公开接口（例如公开 host controller 状态查询如果可用）；无法确定则 unknown，不冒充可用。初次启动不擅自操作设备；先用户授权、明确选择。按 SDK 配置 NSBluetoothAlwaysUsageDescription，String Catalog/InfoPlist 本地化；若沙盒会限制 IOBluetooth，需要真实验证再决定，不宣称 App Store 兼容。独立分发可采用非沙盒、最小权限。不要请求麦克风权限做输出管理。拒绝后停止重试，提供系统设置操作说明。

## Audio / login / diagnostics

CoreAudio HAL：枚举输出设备、监听设备列表与默认输出变更、读取 AudioDeviceUID、传输类型和输出能力，验证匹配。没有可靠蓝牙地址映射时让用户选定 UID，不能凭名称强配。用 kAudioHardwarePropertyDefaultOutputDevice 等公开属性设置默认输出，失败独立显示。SMAppService.mainApp 注册/注销、查询状态、处理 requiresApproval；不手工 LaunchDaemon。

更新使用 Sparkle 2.10.1 的 EdDSA 签名 appcast，经 HTTPS 获取；公钥写入 `Info.plist`，私钥只保存在 CI secret。`SURequireSignedFeed` 与 `SUVerifyUpdateBeforeExtraction` 阻止未签名或被篡改的更新被解压。不要另加自定义下载器或安装路径。

OSLog 分类 system/bluetooth/coordinator/audio/update，使用隐私修饰或短化标识。诊断只从正常界面展示/导出脱敏的状态和最近有界记录。不得上传日志或读取私有数据库。
