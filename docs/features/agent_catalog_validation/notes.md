# Agent 目录校验与删除失败可见

日期：2026-09-27

## 背景

连上只暴露 `build` 的 host 时，客户端可能仍带着上一个 server 的 agent 名发 prompt，对方回 501。另一条是删除：host 对 `DELETE /session/:id` 回 501 时，如果错误信息看不到状态码和 body，用户会以为已经删掉。

iOS 的选择态是 `selectedAgentIndex`，不是持久化的 agent 名。`Message` 也不解码 `info.agent`，没有从历史推断 agent 的路径。跨 host 残留来自内存里的 agent 列表和 index：切 host 时 `resetConnectionRuntimeForHostSwitch` 原先不清 agents。占位列表（`OpenCode-Builder` 等）也不是当前 server 的 `GET /agent` 结果。

删除路径本身已经在 `APIClient.makeRequest` 里对 status >= 400 抛 `APIError.httpError`，`AppState.deleteSession` 只在请求成功后才删本地行，列表 UI 用 `error.localizedDescription` 弹错误。缺口是 `APIError` 没有 `LocalizedError`，弹窗看不到状态码和 body。

## 改动

`AgentInfo.effectiveSelectedAgent(selection:agents:)`：目录为空则保留 selection；目录含该名则保留；否则取第一个可见 agent，再否则 `"build"`。

应用点：

- `loadAgents()` 成功后，用这次返回的列表重校验 `selectedAgentName`，并同步 picker index。
- `sendMessage()` 经 `agentNameForPrompt()` 再校验。还没有当前 host 的目录时，不发送占位名，固定用 `"build"`。
- `loadMessages()` 成功后同样重校验。没有从消息推断 agent；目录为空时不改 selection。
- 切 host 时清空 agent 列表和目录标记，selection 回到 `"build"`，避免用上一个 server 的列表给新 host 背书。
- 默认 selection 是 `"build"`，不是占位列表的 index 0。server 目录里有 `build` 时会选它，即使它不是列表第一项。没有 `build` 时才回退到第一个可见 agent。

删除：`APIError` 改为 `LocalizedError`。非 2xx 的描述是 `HTTP <status>: <body>`。UI 和本地列表的失败分支不用改。

## 测试

`OpenCodeClientTests`：

- 纯函数：未知回退、已知保留、空目录不动、没有可见 agent 时回 `"build"`。
- `loadAgents` / `sendMessage` / `loadMessages` 对未知名的纠正，以及空目录不改 selection。
- 切 host 丢掉上一个 server 的 agent。
- `APIError` 文案含状态码和 body；delete 501 时本地行保留。

未跑 UI test。删除弹窗仍走原有 `actionError = error.localizedDescription`。
