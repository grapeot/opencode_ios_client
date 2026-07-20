# iOS 客户端能力 RFC

## 实现结论

V0 在客户端增加一条独立于 session deep link 的本地优先回调路径。`opencode://session/...` 仍等待 server 连接后解析目标 session；`opencode://client-action-return/...` 必须先消费本地 Pending、写入 Outbox，再等待网络提交。这样 OpenCode 在 Health export 期间被挂起或终止，也不会丢失 correlation。

## 组件

- `Models/CarMode.swift`：按 `type` 解码的 tolerant action union；已知 Maps/Health 强类型，未知 action 不丢弃 speech。
- `Models/ClientCapability.swift`：权限、callback record、Health result 枚举。
- `Services/ClientCapabilityCallbackStore.swift`：Pending/Outbox、原子写入、expiration、single-flight 和 bounded cleanup。
- `AppState+ClientCapabilities.swift`：授权、handoff、callback 消费、query-before-retry 和 continuation projection。
- `Utils/OpenCodeDeepLink.swift`：session 与 callback 两套互不放宽的严格 parser。
- `APIClient.promptStructured`：可选 deterministic `messageID`。

## 状态与相关性

磁盘只有两个阶段：Pending 等待 callback，Outbox 表示 callback 已验收但 continuation 尚未确认完成。每条记录固定保存 `hostProfileID + carContextKey + sessionID`；callback 不读取 `currentSessionID`，也不因用户当前查看其他 workspace 而改变目标。

授权 sheet 出现后用户可能切换 Host。请求因此同时捕获 Host Profile；批准时若当前 Host 已改变，客户端拒绝 launch，不把原 session 和新 Host 拼接。Outbox 只在记录 Host 正好是当前 Host 且已连接时提交，不静默切换 Host。

## 幂等策略

callback ID 是 Pending 文件名和一次性 token。消费时先写 Outbox，再删除 Pending；Outbox 已存在时重复 callback 直接忽略。Continuation 使用 `msg_client_<callback-id>`，每次重试先读取 history，避免 server 已接收请求但 HTTP response 丢失后产生第二个模型 turn。

当前同步 endpoint 在正常路径直接返回 assistant response。若 history 已有 continuation user message但 assistant 尚未完成，客户端保留 Outbox，等待启动、回前台或重连时再次检查；不会盲目重发。

## UI 与生命周期

首次 Health action 显示不可交互关闭的 permission sheet，用户必须选择取消、仅这次允许或以后自动允许。Settings 显示当前授权状态，并只允许撤销已有自动授权。

启动、回前台、连接恢复、创建 Pending 和收到 callback 时执行 cleanup/retry。回调验收不依赖连接；网络提交依赖当前 Host 连接。Continuation 只有在用户仍查看原 Car context 时才投影 speech/TTS，其他 context 只更新原 record，避免打断当前任务。

## 验证

Tier 1/2 覆盖 action tolerant decoding、严格 callback parser、canonical launch URL、Pending/Outbox expiration/duplicate consume、allow-once、原 session continuation 和 deterministic message ID。Fixture XCUITest 覆盖 permission reason 与三个本地决定。完整命令见 `docs/tests.md`，本轮结果记录在 `docs/WORKING.md`。
