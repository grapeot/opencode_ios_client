# iOS 客户端能力协议

## 协议范围

本协议定义 OpenCode iOS 作为 capability consumer 时的 structured action、Health Quantification handoff、callback 验收和原 session continuation。当前版本为 V0，只注册 `health_quantification.export_all`。

## Structured Action

```json
{
  "id": "health-export-1",
  "type": "health_quantification.export_all",
  "reason": "同步昨晚睡眠数据，以完成睡眠分析"
}
```

`id` 只用于诊断，`type` 是 dispatcher 和权限 key，`reason` 只用于本地 UI。模型不得提供 URL 或 continuation 文本。未知 action 保留 envelope speech，但客户端不执行。

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

允许字段：

| 字段 | 允许值 |
|---|---|
| `status` | `success`、`partial`、`failed`、`busy` |
| `sent` | 0 至 `Int32.max` 的十进制整数 |
| `upserted` | 0 至 `Int32.max` 的十进制整数 |
| `failed` | `sleep,vitals,body,lifestyle,activity,workouts` 的无重复子集 |
| `error_code` | `category_failure`、`export_in_progress`、`invalid_server_url` |

未知字段、重复字段、userinfo、port、fragment、额外 path、非 canonical callback ID 或非法枚举全部拒绝。现有 session deep link 仍禁止任何 query 或 fragment。

## 本地持久化

```text
Application Support/ClientCapabilityCallbacks/
  Pending/<callback-id>.json
  Outbox/<callback-id>.json
```

Pending 保存 capability、Host Profile、Car context、session、assistant action 和确定性的 continuation message ID，15 分钟后过期。合法 callback 将 Pending 规范化为 Outbox；Outbox 最长保留 6 小时。重复 callback 不能产生第二条 continuation。目录最多保留 50 条，损坏、未知版本、非法文件名和过期记录在 bounded cleanup 中删除。

## Continuation Contract

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

`POST /session/:id/message` 使用由 callback ID 确定性派生的 `messageID`。重试前查询 session history：user message 不存在才提交；存在但 assistant 尚未完成时保留 Outbox；assistant 完成后验收 structured response并删除 Outbox。401、403、404 为 terminal failure，其余传输或 5xx 错误保留 Outbox重试。

Synthetic result 不构成新的用户授权。Continuation response 必须没有任何 client action；AI 必须重新读取 Health server 的 freshness 和样本，再回答原始请求。

## 安全边界

V0 接受 custom URL scheme 可能被同设备恶意 App 抢占的残余风险。callback ID 只证明调用方拿到了 bearer token，不证明 Health 数据真实完成同步。协议因此不在 URL 中承载健康事实或授权副作用，并强制 continuation 重新读取 server。需要抵御同设备恶意 App 时，应升级为 Associated Domains universal link，而不是扩大 custom scheme payload。
