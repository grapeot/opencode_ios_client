# iOS 客户端能力 RFC

## 实现结论

V0 阶段在客户端引入了一条独立于常规 Session 深度链接（deep link）的“本地优先”回调链路。传统的 `opencode://session/...` 仍需等待服务端建立连接后再解析目标会话；而 `opencode://client-action-return/...` 则强制先在本地消费 Pending 记录并落入 Outbox，再等待网络可用时向服务端提交。这种设计保证了即使 OpenCode 在 Health export 期间被系统挂起（suspended）或进程被杀（terminated），关联上下文（correlation）也不会丢失。

## 组件

- `Models/CarMode.swift`：实现基于 `type` 的容错型 Action Union 解码；对已知的 Maps 和 Health 动作强类型化，遇到未知 Action 时依然保留完整的 `speech` 内容。
- `Models/ClientCapability.swift`：定义权限模型、回调记录（callback record）与 Health 结果枚举。
- `Services/ClientCapabilityCallbackStore.swift`：负责 Pending/Outbox 管理、文件原子写入、超时过期判定、Single-flight 限制以及受限容量清理（bounded cleanup）。
- `AppState+ClientCapabilities.swift`：承载授权鉴权、Handoff 跳转、回调消费、重试前查询（query-before-retry）以及 Continuation 结果投影逻辑。
- `Utils/OpenCodeDeepLink.swift`：内置针对 Session 与 Callback 两套互相独立、边界严格的解析器。
- `APIClient.promptStructured`：支持传入确定性的 `messageID` 可选参数。

## 状态与相关性

磁盘存储仅划分两个离散阶段：Pending 阶段用于等待外部 Callback 返回，Outbox 阶段则代表 Callback 已经过本地验收但 Continuation 尚未与服务端确认完成。每条持久化记录均严格绑定 `hostProfileID + carContextKey + sessionID`；Callback 处理时绝不读取易变的 `currentSessionID`，也不会因用户当前切到了其他 Workspace 而改变原始投递目标。

在授权弹窗（permission sheet）弹出期间，用户可能会主动切换 Host。因此，请求在发起时便同步捕获了当前的 Host Profile；当用户点击允许时，若当前连接的 Host 已发生变更，客户端将直接拒绝拉起外部 App（launch），杜绝将原 Session 错误绑定到新 Host 的风险。Outbox 中的记录仅在记录所属的 Host 与当前活跃 Host 完全一致且处于已连接状态时才会触发网络提交，严禁静默跨 Host 提交。

## 幂等策略

`callback-id` 既是 Pending 文件的唯一命名，也是一次性的 Bearer Token。消费回调时采用“先写 Outbox，再删 Pending”的事务顺序；若 Outbox 中已存在同名记录，则直接忽略重复的 Callback。Continuation 提交时采用由 `callback-id` 派生的固定 ID `msg_client_<callback-id>`，每次重试前先拉取会话历史进行校验，避免在服务端已成功受理请求但 HTTP 响应在传输中丢失时，因重试而触发模型的第二轮推理。

在现有同步接口的正常执行链路中，服务端会直接返回 Assistant 响应。若历史记录中已存在该 Continuation 的 User Message 但 Assistant 尚未生成完毕，客户端将继续保留 Outbox，并等待应用冷启动、返回前台或网络重连时再次对账检查，绝不盲目重复发包。

## UI 与生命周期

首次触发 Health action 时，系统将展示不可下拉手势关闭的授权弹窗，强制用户在“取消”、“仅允许一次”与“始终允许”中做出显式选择。Settings 界面实时反映当前的授权状态，并仅提供撤销既有“始终允许”的权限操作。

在应用冷启动、返回前台、网络连接恢复、新建 Pending 以及收到 Callback 消息时，均会触发 Cleanup/Retry 管道。Callback 的本地验收完全不依赖网络连通性，而网络提交则必须等待对应 Host 处于连接状态。Continuation 的执行结果仅在用户仍停留在原始 Car 上下文时才会投射 Speech/TTS 播报；若用户已切换至其他上下文，则仅在后台默默更新原始会话记录，避免打扰用户当前正在进行的任务。

## 验证

Tier 1 与 Tier 2 测试全面覆盖了 Action 容错解码、严格 Callback 解析、标准规范 Launch URL 构造、Pending/Outbox 过期判定与防重消费、单次授权（allow-once）流转、原会话 Continuation 恢复以及确定性 Message ID 生成。基于 Fixture 的 XCUITest 重点覆盖了权限 Reason 展示与三项本地授权决定的交互分支。具体测试命令参见 `docs/tests.md`，本轮验证结果已完整归档在 `docs/WORKING.md` 中。
