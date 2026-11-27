# Connection policy — canonical contract

[English](CONNECTION_POLICY.md) · [文档索引](README.zh-CN.md)

## State

使用稳定、规范化的经典蓝牙地址作为 DeviceID（名称仅展示）。保存 ManagedDevice: id, cachedName, policy, paused, optional preferred audio UID。全局 enabled、schemaVersion。配置是事实来源；连接状态来自系统，不持久化为事实。

SystemSnapshot: power = awake / goingToSleep / asleep / unknown; display = awake / asleep / unknown; session = active / inactive / unknown; bluetooth = available / unavailable / unauthorized / unknown。无头及硬件断电不能可靠观测时 unknown。

DeviceSnapshot: observed = unknown / connected / disconnected / unavailable; operation = idle / connecting / disconnecting / settling，错误和 audio readiness 独立。desired = connected / disconnected / unmanaged。区分触发事件、实际观察和期望；不要把错误覆盖真实连接状态。

每设备默认：connectOnDisplayWake=true, disconnectOnDisplaySleep=true, reconnectOnUnexpectedDisconnect=true, disconnectOnSystemSleep=true, preferredAudio=false, paused=false。全局 enabled 默认 true，但空托管列表不操作任何设备。切换开关只影响其独立策略。

## Policy evaluation

规则自上而下，匹配即止：

| 条件 | 自动目标 |
|---|---|
| 未托管、暂停或全局关闭 | unmanaged；取消待重试，当前连接保持 |
| 会话非 active 或蓝牙不可用/未知 | unmanaged；不主动争抢或开启蓝牙 |
| goingToSleep / asleep | 若系统休眠断开开启则 disconnected（willSleep 时尽力执行）；否则 unmanaged |
| 电源未知 | unmanaged |
| display=unknown | unmanaged |
| display=asleep | 若息屏断开开启则 disconnected，否则 unmanaged；不重连 |
| display=awake 且有本亮屏周期手动断开覆盖 | unmanaged |
| 真实亮屏事件、应用启动或恢复管理、明确配置变化 | connectOnDisplayWake 开启则 connected，否则 unmanaged |
| display=awake，真实意外断连 | reconnectOnUnexpectedDisconnect 开启则 connected，否则 unmanaged；不将 connectOnDisplayWake 当持续强制连接 |
| 其他 | 保留合法当前意图或 unmanaged；不得发出不必要操作 |

采用事件上下文而非单一布尔映射，避免关闭自动重连后仍被亮屏连接规则反复连接。亮屏事件定义为已确认 asleep→awake 的新周期；启动读到 awake 可以触发一次初始化协调，但重复 wake 通知不得重置手动覆盖或重试预算。系统唤醒但屏幕未亮不创建连接意图。

手动连接/断开可在正常可用会话、蓝牙可用时执行，不依赖自动开关；手动断开覆盖当前亮屏周期，下一真正亮屏周期或明确恢复管理时清除；持久暂停跨重启。手动连接覆盖旧意图；进入新息屏/休眠后仍按策略处理。用户在系统设置断开与设备掉线可能无法区分，诚实说明；提供易用暂停，避免争抢手机。移除托管、退出不主动改变连接。若不可取消操作已发出，只记录其迟到结果，不在暂停后发新自动操作。

## Reconciliation

事件→刷新受影响快照→纯策略计算→按 DeviceID 串行协调→平台调用→观察确认→依据最新意图继续。初始注册通知与 snapshot 读取应避免遗漏窗口（注册后查询并去重）。连接/断开通知重复、乱序、丢失时，限时状态查询可辅助确认；无事件时不持续轮询。禁止并行对同设备 open/close。底层超时后不能假装已结束；保留 in-flight 或隔离直到终止/可靠确认，再补偿最新目标。每个操作有 operationID，意图有 generation，取消延时任务并处理过期完成。

重试预算初始为首试+4 次（1/2/4/8 秒退避，实际超时基于 SDK/实测），单次超时、抖动有界。连续意外断连另有速率上限：60 秒内允许 3 次自动重连，第 4 次意外断连停止自动重连并显示可手动重试的失败；该计数与重试预算只在新的真实亮屏、蓝牙服务恢复、有效配置改变或显式重试时清零，成功连接本身不清零，避免“连上又掉”的无界循环。重复通知不重置预算。预算耗尽后停止，无永久定时器。屏幕关闭、暂停或移除及时取消待重试；连接完成迟到时重新评估，若期间已息屏则补发断开。睡眠前仅尽力断开，不用 assertion 延长休眠。

## Audio

A2DP/HFP 等 profile 是否恢复并非 IOBluetooth ACL 连接的充分结果。默认尊重系统音频路由。可选首选输出由用户显式选择稳定 AudioDeviceUID；只在合适的连接事件且输出设备就绪后切换一次。等待有界、用设备列表通知；不反复切回、不改变输入/音量、不因音频缺失重连蓝牙。多个音频设备只允许一个全局自动切换首选；默认关闭。
