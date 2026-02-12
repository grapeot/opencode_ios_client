# SSE 解析与重连策略

> Code Review 1.2 调研与规划

## 1. SSE 规范要点（WHATWG）

- **事件边界**：以空行 `\n\n` 作为单个 event 结束
- **字段**：`event:`、`data:`、`id:`、`retry:`；行首 `:` 为 comment（忽略）
- **多行 data**：同一 event 内多个 `data:` 行，用 `\n` 拼接
- **编码**：UTF-8

## 2. OpenCode `/global/event` 实测行为（已验证）

直连 `GET /global/event` 实测：

| 项目 | 结果 |
|------|------|
| 格式 | `data: {...}\n\n` 单行 JSON，连接即发 `server.connected` |
| event: 字段 | 未使用 |
| comment keep-alive | 未观察到 |
| 多行 data | 未出现 |
| 结论 | 当前按行解析 `data:` 已足够，无需实现多行/event/comment |

## 3. 当前实现（SSEClient）

- 按单行 `\n` 处理，遇 `data: ` 前缀即解析 JSON
- 未处理：多行 data、`event:`、comment、空行分隔
- 无重连：断线后需 `connectSSE()` 手动重连
- 未设置：`Accept: text/event-stream`、`Cache-Control: no-cache`

## 4. 建议改进

### 4.1 解析 ✅ 已满足

API 仅发单行 data，当前实现正确。可补充注释说明。

### 4.2 请求头（建议实现）

- `Accept: text/event-stream`
- `Cache-Control: no-cache`

### 4.3 重连（可选，后续）

- 当前：前台恢复时 `refresh()` + `connectSSE()` 已覆盖
- 若需断线自动重连：指数退避 1s→2s→4s→… 上限 30s

## 5. 实施顺序

1. ✅ API 验证完成
2. 添加请求头（低风险）
3. 重连策略：暂不实现，现有轮询 + 前台恢复已可用
