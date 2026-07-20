# OpenCode iOS Client Capabilities

## 目标

在不开放任意 URL、不复制设备领域逻辑到 OpenCode、也不修改 OpenCode server tool loop 的前提下，为 OpenCode iOS 增加一个 typed、可授权、可恢复、可回到原 session 的设备能力。

正式 wire contract 以 [`../docs/client_capabilities_protocol.md`](../docs/client_capabilities_protocol.md) 为准。开始修改前优先读取该文件、`Models/ClientCapability.swift`、`AppState+ClientCapabilities.swift` 和 provider App 的 deep-link parser/result types。

## 适用判断

设备 entitlement、传感器或仅本机数据才适合 client capability。已有独立领域 App、权限 UI 和长期状态时，优先使用受限 deep link + callback；轻量系统 picker 可直接集成 OpenCode iOS；server 已能完成的工作继续使用 server tool/skill。

不要为了统一形式把数据库查询、网页 API、邮件或 Smart Home server 调用搬到 iOS。新 capability 没有清晰第二个消费者前，也不要抽取独立 framework 或通用 workflow engine。

## 硬边界

- 每个 action 必须是 stable typed case，模型不能提供 launch/callback URL。
- 本地 dispatcher、permission key 和 provider parser共同形成 allowlist；system prompt 不是安全边界。
- callback 必须使用高熵一次性 ID、短期 Pending 和较长但 bounded 的 Outbox。
- correlation 必须保存 Host、context 和 session；禁止 fallback 到当前 selection。
- callback payload 只能包含枚举、bounded 数字和 opaque ID，不能包含用户数据、token、server response 或自由文本错误。
- synthetic continuation 不是用户授权，返回 envelope 不得执行任何 client action。
- custom scheme callback 后必须重新读取权威 server 数据，不能把 callback 当作领域事实。

## 新能力的验收标准

- Structured schema、Swift decoder 和未知 action fallback 同时有测试；未知 action 不导致整条 assistant speech 丢失。
- 首次授权、allow once、allow always、撤销和拒绝均有确定行为，权限只按 capability 名持久化。
- Launch URL 由客户端固定构造，provider 严格限制 scheme/host/path/query。
- Pending 在 launch 前落盘；launch 失败会删除；过期、重复 callback 和损坏文件不产生 continuation。
- 断网 callback 先进入 Outbox，重连后只向记录的原 session 提交一次。
- deterministic message ID 和 query-before-retry 防止重复模型 turn。
- provider 与 consumer 的 success/partial/failed/busy、计数、类别、错误码 fixture 一致。
- 原 Maps action、session deep link、iPhone/iPad/visionOS平台门控和全量测试不回归。

## 已知陷阱

- 不要把所有 action 做成带大量 optional 字段的 struct。Health action没有 `destination`，固定 Maps shape 会让整个 structured message 解码失败。
- 不要复用连接后才处理的 session deep-link queue。callback 到达时 App 可能尚未连接，必须先完成本地消费。
- 不要在 Settings 的既有 Car toggle 上方插入高内容 section；这曾让 fixture UI 将 toggle 推出可见区域。保持现有关键控制顺序或同步更新可滚动测试。
- 不要在看到 continuation user message 后立即删除 Outbox。它只证明 server admission；应等待对应 assistant response，期间禁止重发。

## 输出位置

新增能力应更新 `docs/client_capabilities_protocol.md`、对应产品/RFC文档、Swift registry/dispatcher、provider contract 和测试。设计草案或一次性调查不要成为第三份协议 source of truth。
