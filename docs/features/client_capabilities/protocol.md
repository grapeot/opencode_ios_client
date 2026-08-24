# iOS 客户端能力协议

> 最后核对：2026-08-23 · 对照 OpenCodeClient 当前实现

## 协议范围

本协议规范了 OpenCode iOS 作为 capability consumer 角色时的行为标准，涵盖结构化动作（structured action）解析、Health Quantification 跨 App 跳转（handoff）、回调结果验收以及原 Session continuation 的全生命周期。当前 V0 版本仅注册 `health_quantification.export_all` 这一项具体能力。

## Structured Action

模型在 Car Mode 模式下统一返回 `CarResponseEnvelope` 容器（包含 `version`、`status`、`speech`、`confirmation` 与 `clientActions` 字段），其中 `clientActions` 数组最多允许包含 1 项操作。针对 Health export 动作的 Schema 定义如下：

```json
{
  "id": "health-export-1",
  "type": "health_quantification.export_all",
  "reason": "同步昨晚睡眠数据，以完成睡眠分析"
}
```

字段约束（定义于 `CarModeProtocol.outputFormat`，声明 `additionalProperties: false`）：

- `id`：长度介于 1–100 个字符之间，仅用于链路诊断与请求去重。
- `type`：固定取值为 `health_quantification.export_all`，作为动作分发路由（dispatcher）与权限校验的唯一 Key。
- `reason`：长度介于 1–240 个字符且去除首尾空白后非空，仅用于客户端本地 UI 的授权说明展示。

模型严禁在返回中指定 URL 或 continuation 文本；callback URL 及其携带的参数一律由 OpenCode iOS 在本地独立构造（System Prompt 中已明确禁止模型自行编造 URL）。对于未知的 `type` 类型，解析层将其归入 `unknown` 枚举分支，保留外层 Envelope 中的 `speech` 播报内容，但客户端绝不触发该动作的执行。

## 授权与 Dispatch（2026-08 核对更新）

权限状态 `ClientCapabilityPermission` 分为 `ask`（默认每次询问）与 `allow_always`（始终允许）两种，持久化保存在 UserDefaults 中，对应的 Key 为 `clientCapability.healthExportAll.permission.v1`；用户可在 Settings 页面中手动将其重置回 `ask` 状态。

- 当模型返回 Health export 动作后，`requestClientCapability` 触发鉴权逻辑：若权限为 `allow_always` 则直接执行 Dispatch；否则构建 `pendingClientCapabilityRequest` 状态并拉起 `ClientCapabilityPermissionView` 授权弹窗，供用户在“仅允许一次（Allow once）”、“始终允许（Allow always）”与“取消（Cancel）”三者中选择。
- 在 `dispatchClientCapability` 流程中，系统首先调用 `createPending` 生成 `callbackID` 并完成本地 Pending 记录落盘，随后通过 `UIApplication.shared.open` 打开目标 Launch URL；若拉起失败，则立即清理刚才创建的 Pending 记录并抛出 `launchFailed` 异常。
- 针对同一 capability，若本地已存在尚未过期的 Pending 或 Outbox 记录，`createPending` 将直接抛出 `duplicateCapability` 错误，UI 层同步弹出该能力正在执行中的提示（对应 L10n `capabilityAlreadyRunning`），避免发起并发重复请求。
- 每条持久化记录严格绑定发起请求时的 Host Profile 上下文：持久化存储 `hostProfileID` 与 `hostConfigurationSignature`（基于 Transport 模式、Server URL、Basic Auth 用户名及 SSH 配置计算的 SHA-256 哈希值）。

## Launch Contract

```text
healthquantification://export-all?callback=<percent-encoded-callback-url>
```

解码后的 callback 格式严格固定为：

```text
opencode://client-action-return/<callback-id>
```

`callback-id` 由 32 个随机字节经无 Padding 的 base64url 编码生成，当前实现长度固定为 43 个字符；接收方（consumer）校验规则允许 43 至 128 个由 ASCII 字母、数字、`-` 及 `_` 组成的字符。该 ID 同时作为本次请求的唯一标识（request identity）与一次性授权凭证（bearer token）。OpenCode 必须先将 Pending 记录持久化至本地磁盘，随后才调用 `UIApplication.open` 拉起外部应用；若拉起操作失败，则回滚删除该 Pending 记录。

## Return Contract

```text
opencode://client-action-return/<callback-id>?status=success&sent=1240&upserted=1240
```

允许接收的 Query 字段列表（其中 `status`、`sent`、`upserted` 为必填项；`failed`、`error_code` 为可选项）：

| 字段 | 必填 | 允许值 |
|---|---|---|
| `status` | 是 | `success`、`partial`、`failed`、`busy` |
| `sent` | 是 | 0 至 `Int32.max` 的十进制整数 |
| `upserted` | 是 | 0 至 `Int32.max` 的十进制整数 |
| `failed` | 否 | `sleep,vitals,body,lifestyle,activity,workouts` 的无重复子集，逗号分隔 |
| `error_code` | 否 | `category_failure`、`export_in_progress`、`invalid_server_url` |

任何包含未知 Query 字段、重复字段、空 Query、UserInfo、Port 端口号、Fragment 片段、多余 Path 分段、非规范化 Callback ID（即 URL 解码后的字符串与解码前不一致）或非法枚举值的请求，解析器一律严格拒绝处理。既有的 Session 深度链接（`opencode://session/<id>`）同样严格禁止携带任何 Query、Fragment、UserInfo 或 Port，且 Session ID 必须以 `ses_` 为前缀，总长度在 5–256 字符之间，并仅允许包含 `[A-Za-z0-9_-]` 字符集。

## 本地持久化（2026-08 核对更新）

```text
Application Support/ClientCapabilityCallbacks/
  Pending/<callback-id>.json
  Outbox/<callback-id>.json
```

Pending 记录（数据结构标明 `version: 1`）完整保存了 `callbackID`、`capability`、`hostProfileID`、`hostConfigurationSignature`、`carContextKey`、`sessionID`、`assistantMessageID`、`actionID`、确定性的 `continuationMessageID`（固定为 `msg_client_<callback-id>`）、`createdAt` 创建时间、`expiresAt` 过期时间（计算为 `createdAt + 15 分钟`）以及 `result` 执行结果（初始化为 null）。

当收到合法的 Callback 请求时，系统会将 Pending 记录校验并迁移至 Outbox 目录（填入 `result` 内容并安全删除原 Pending 文件）；Outbox 记录在本地最长保留 6 小时（以记录的 `createdAt` 时间起算）。重复收到的 Callback 绝不能生成第二条 Continuation 记录（当 Outbox 中已存在同名记录时，`consume` 方法直接返回 nil）。整个回调目录最多允许容纳 50 条记录（Pending 与 Outbox 数量合并计算），对于数据损坏、未知版本、非法文件名以及已过期的记录，将在受限清理（bounded cleanup）流程中自动删除；若有效记录数仍超出 50 条上限，则依据 `createdAt` 时间戳从最早的记录开始逐一丢弃。所有磁盘写入均通过“写入临时文件 + 原子重命名（atomic move）”机制执行，杜绝并发写入导致的文件损坏。

## Continuation Contract（2026-08 核对更新）

客户端负责向 Pending 中记录的原始 Session 发送如下结构化消息：

```json
{
  "kind": "client_action_result",
  "capability": "health_quantification.export_all",
  "invocation_id": "<callback-id>",
  "status": "success",
  "sent": 1240,
  "upserted": 1240,
  "failed_categories": [],
  "error_code": null
}
```

`POST /session/:id/message` 请求显式传入由 Callback ID 确定性生成的 `messageID`（即 `continuationMessageID = msg_client_<callback-id>`）。请求载荷中还一并附带 `system`（使用预置的 `clientResultSystemPrompt`）、`format`（匹配 Car Mode 的 json_schema 约束）、`agent: "build"` 以及 Car Mode 专用的模型配置。

在实际提交网络请求前，客户端必须先查询当前会话的历史消息以执行幂等判定：

- 若会话历史中尚不存在 `id == continuationMessageID` 的 User Message → 直接向服务端提交请求。
- 若已存在该消息但对应的 Assistant 回复尚未生成完成 → 继续保留本地 Outbox 记录，按照每 2 秒一次的频率进行轮询对账，最多尝试 15 次；若超时后仍未完成，则将本次 Continuation 标记为失败（本地保留 Outbox 供后续重试）。
- 若对应的 Assistant 回复已生成完毕 → 校验结构化响应数据，验收通过后彻底删除本地 Outbox 记录。

网络提交与结果验收均受到严格的 Host 与路由守卫（guard）约束：必须同时满足 `isConnected` 连接状态、`currentHostProfileID` 与记录中的 Host Profile 一致、`hostConfigurationSignature` 与当前运行配置完全匹配、且 `deepLinkRouteID` 路由代际未发生跃迁；若原始 Host Profile 已被用户删除，则静默清理该 Outbox 记录（不抛出错误）；若检测到配置发生变动（signature 不匹配），则删除 Outbox 并对外报错 `continuationFailed`。

当接口返回 401、403 或 404 状态码时，判定为终态错误（terminal failure），客户端将删除 Outbox 并标记失败；其余网络传输抖动或 5xx 服务端错误则继续保留 Outbox，等待网络重连或下一次触发时安全重试，直至记录过期。

由客户端合成的 Synthetic 结果在语义上不构成新的用户授权。Continuation 产生的响应载荷中严禁携带任何 Client Action（即 `clientActions` 必须为空），且必须为同 Session 下已完成的 Assistant 消息，满足 Envelope `version == 1` 且 `speech` 字段非空；AI 必须依据该结果重新从 Health 服务端读取数据的新鲜度与样本指标，进而完成对用户原始提问的最终回答。

## 安全边界（2026-08 核对更新）

V0 架构设计中明确接受 Custom URL Scheme 机制在理论上可能被同一设备上的恶意 App 抢占监听的残余风险。`callback-id` 仅用于证明调用方持有该一次性 Bearer Token，本身不能作为底层健康数据已真实完成同步的绝对可信凭证。Callback URL 仅负责传递导出操作的概要执行结果（`status`、`sent`、`upserted`、`failed`、`error_code`），绝不承载具体的健康数据明细，亦不触发任何授权变更副作用；在 Continuation 阶段，系统通过 System Prompt 强制要求 AI 重新主动向服务端拉取真实数据进行核验，而不是直接无条件采信 URL 中携带的状态描述。若后续需要全面抵御同设备恶意 App 的伪造风险，应将通信通道升级为基于 Associated Domains 的 Universal Links 机制，而非盲目扩充 Custom Scheme 下传输的数据载荷。
