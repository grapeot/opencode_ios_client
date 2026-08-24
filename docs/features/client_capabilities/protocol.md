# iOS 客户端能力协议

> 最后核对：2026-08-24 · 对照 OpenCodeClient 当前实现

## 协议范围

本协议定义 OpenCode iOS 作为 capability consumer 时的 structured action、Health Quantification handoff、callback 验收和原 session continuation。当前版本为 V0，只注册 `health_quantification.export_all`。

## Structured Action

模型在 Car Mode 下返回一个 `CarResponseEnvelope`（`version`、`status`、`speech`、`confirmation`、`clientActions`），其中 `clientActions` 最多 1 项。Health export action 的 schema：

```json
{
  "id": "health-export-1",
  "type": "health_quantification.export_all",
  "reason": "同步昨晚睡眠数据，以完成睡眠分析"
}
```

字段约束（`CarModeProtocol.outputFormat`，`additionalProperties: false`）：

- `id`：1–100 字符，只用于诊断与去重。
- `type`：固定 `health_quantification.export_all`，是 dispatcher 和权限 key。
- `reason`：1–240 字符、trim 后非空，只用于本地 UI 展示。

模型不得提供 URL 或 continuation 文本；callback URL 与参数一律由 OpenCode iOS 构造（system prompt 明确禁止模型臆造）。未知 `type` 归入 `unknown` 分支，envelope 的 `speech` 保留，但客户端不执行该 action。

## 授权与 Dispatch（2026-08 核对更新）

权限状态 `ClientCapabilityPermission` 为 `ask`（默认）或 `allow_always`，持久化在 UserDefaults，key 为 `clientCapability.healthExportAll.permission.v1`；Settings 里可手动撤销回 `ask`。

- 模型返回 health export action 后，`requestClientCapability` 判断权限：`allow_always` 直接 dispatch；否则写入 `pendingClientCapabilityRequest`，由 `ClientCapabilityPermissionView` 弹出，提供三选一：Allow once / Allow always / Cancel。
- `dispatchClientCapability` 先 `createPending`（生成 `callbackID`、落 Pending），再通过 `UIApplication.shared.open` 打开 launch URL；launch 失败则删除 Pending 并抛 `launchFailed`。
- 同一 capability 若已有未过期的 Pending 或 Outbox 记录，`createPending` 抛 `duplicateCapability`，UI 显示 "already running"，不会重复发起。
- 每条记录绑定发起时的 Host Profile：存 `hostProfileID` 与 `hostConfigurationSignature`（对 transport、serverURL、basic auth username、SSH 配置做 SHA-256）。

## Launch Contract

```text
healthquantification://export-all?callback=<percent-encoded-callback-url>
```

解码后的 callback 固定为：

```text
opencode://client-action-return/<callback-id>
```

`callback-id` 是 32 个随机字节的无 padding base64url，当前生成长度 43；consumer 接受 43 至 128 个 ASCII 字母、数字、`-`、`_`。它同时是 request identity 和一次性 bearer token。OpenCode 先持久化 Pending，再调用 `UIApplication.open`；launch 失败时删除 Pending。

## Return Contract

```text
opencode://client-action-return/<callback-id>?status=success&sent=1240&upserted=1240
```

允许字段（`status`、`sent`、`upserted` 必填；`failed`、`error_code` 可选）：

| 字段 | 必填 | 允许值 |
|---|---|---|
| `status` | 是 | `success`、`partial`、`failed`、`busy` |
| `sent` | 是 | 0 至 `Int32.max` 的十进制整数 |
| `upserted` | 是 | 0 至 `Int32.max` 的十进制整数 |
| `failed` | 否 | `sleep,vitals,body,lifestyle,activity,workouts` 的无重复子集，逗号分隔 |
| `error_code` | 否 | `category_failure`、`export_in_progress`、`invalid_server_url` |

未知字段、重复字段、query 为空、userinfo、port、fragment、额外 path 段、非 canonical callback ID（percent-decoded 后须与自身一致）或非法枚举全部拒绝。现有 session deep link（`opencode://session/<id>`）仍禁止任何 query、fragment、userinfo、port，且 session ID 须以 `ses_` 开头、含 `[A-Za-z0-9_-]`。

## 本地持久化（2026-08 核对更新）

```text
Application Support/ClientCapabilityCallbacks/
  Pending/<callback-id>.json
  Outbox/<callback-id>.json
```

Pending 记录（`version: 1`）保存 `callbackID`、`capability`、`hostProfileID`、`hostConfigurationSignature`、`carContextKey`、`sessionID`、`assistantMessageID`、`actionID`、确定性的 `continuationMessageID`（值为 `msg_client_<callback-id>`）、`createdAt`、`expiresAt`（`createdAt + 15 分钟`）与 `result`（初始为 null）。

合法 callback 将 Pending 规范化为 Outbox（写入 `result` 并删除 Pending）；Outbox 最长保留 6 小时（自 `createdAt` 起）。重复 callback 不能产生第二条 continuation（Outbox 已存在时 `consume` 返回 nil）。目录最多保留 50 条（Pending 与 Outbox 合计），损坏、未知版本、非法文件名和过期记录在 bounded cleanup 中删除，超出 50 条时按 `createdAt` 从最旧开始丢弃。写入走临时文件 + 原子 move。

## Continuation Contract（2026-08 核对更新）

客户端向 Pending 中记录的 session 发送：

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

`POST /session/:id/message` 使用由 callback ID 确定性派生的 `messageID`（即 `continuationMessageID = msg_client_<callback-id>`）。请求体还带 `system`（`clientResultSystemPrompt`）、`format`（Car Mode 的 json_schema）、`agent: "build"` 与 Car Mode 模型。

提交前查询 session history 做幂等判断：

- 若不存在 `id == continuationMessageID` 的 user message → 直接提交。
- 若存在但 assistant 尚未完成 → 保留 Outbox，每 2 秒轮询一次，最多 15 次；仍未完成则标记 continuation 失败（Outbox 保留）。
- 若 assistant 已完成 → 验收 structured response 并删除 Outbox。

提交与验收都受 host/route 守卫约束：须 `isConnected`、`currentHostProfileID` 与记录一致、`hostConfigurationSignature` 与当前配置一致、且 `deepLinkRouteID` 代际未变；Host Profile 被删除或配置变更时删除 Outbox 并报 `continuationFailed`。

401、403、404 为 terminal failure（删除 Outbox 并标记失败），其余传输或 5xx 错误保留 Outbox 待重连或过期后重试。

Synthetic result 不构成新的用户授权。Continuation response 必须没有任何 client action（`clientActions` 为空），且须为 assistant、同 session、已完成、envelope `version == 1`、`speech` 非空；AI 必须重新读取 Health server 的 freshness 和样本，再回答原始请求。

## 安全边界（2026-08 核对更新）

V0 接受 custom URL scheme 可能被同设备恶意 App 抢占的残余风险。callback ID 只证明调用方拿到了 bearer token，不证明 Health 数据真实完成同步。callback URL 只承载导出结果摘要（`status`、`sent`、`upserted`、`failed`、`error_code`），不承载健康数据内容或授权副作用；continuation 通过 system prompt 强制 AI 重新读取 server，而不是直接采信 URL 里的事实。需要抵御同设备恶意 App 时，应升级为 Associated Domains universal link，而不是扩大 custom scheme payload。
