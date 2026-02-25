# Session 消失问题调研报告

> 2026-02-25

## 状态

- **已修复**（2026-02-25）：采用方案 A（防御性修复），见下方「已实现修复」
- **相关文档**：RFC §4.3.1、lessons.md §16

## 问题现象

1. **点 New Session 后切到 Session List**：新建的 session 在列表里不见了，从汉堡菜单返回后之前打的字也没了，整个 new session 消失
2. **新建 session 后切后台再回前台**：新 session 消失，回到最早的 session

## 根因分析

### 1. API 实测结论（基于 localhost:4096 实测）

| 操作 | 结果 |
|------|------|
| `POST /session` 创建 session | 成功，返回 session 含 `directory`、`projectID` |
| 创建时传 `directory` 或 `worktree` | **被忽略**，server 使用其 current project |
| `GET /project/current` | Server 当前 project 为 agentic_trading |
| `POST /session` 创建的新 session | 落在 agentic_trading，directory 为 `/Users/grapeot/co/vatic/agentic_trading` |
| `GET /session?directory=/Users/grapeot/co/knowledge_working` | **不包含**刚在 agentic_trading 下创建的 session |

### 2. 核心不兼容点

**Server 行为**：
- `POST /session` 的 body 仅支持 `{ parentID?, title? }`，不支持 `directory` / `worktree` / `projectID`
- 新 session 始终创建在 **server 的 current project**（由 TUI/Web 最后使用的 project 决定）
- `GET /session?directory=X` 只返回 directory 匹配 X 的 sessions

**iOS 行为**：
- `createSession()` 调用 `POST /session`，不传 project/directory
- `loadSessions()` 使用 `effectiveProjectDirectory`（用户在 Settings 选的 project）调用 `GET /session?directory=...`
- `loadSessions()` **完全替换** `sessions` 数组，不做 merge

**冲突**：当 server 的 current project ≠ iOS 用户选的 project 时：
1. 新建的 session 落在 server 的 project A
2. iOS 用 project B 的 directory 去拉列表
3. 新 session 不在 GET 结果里
4. `sessions = serverResponse` 覆盖本地，新 session 从列表消失

### 3. 触发场景

| 场景 | 触发点 | 结果 |
|------|--------|------|
| 点 Session List | `SessionListView` 的 `.task { refreshSessions() }` | `loadSessions()` 覆盖 `sessions` |
| 切后台再回前台 | `willEnterForeground` → `restoreConnectionFlow()` → `refresh()` | `refresh()` 内含 `loadSessions()`，同样覆盖 |

### 4. 官方 Web 端行为变化（你观察到的）

你提到官方 web 端现在点 new session 只出对话框、发送后才建 session。这与 API 无关，是 **Web UI 的交互设计**：可能改为「先输入首条消息再创建 session」的 lazy 模式。OpenCode changelog 未明确记录此变更，但说明官方客户端也在演进，与「何时创建 session」的语义有关。

## 网上讨论

- **#9434**：如何从 CLI 创建空 session，结论是 `opencode run "prompt"` 会创建
- **#10468**：Worktrees 在 web 上表现不佳
- **#6696 / #6697**：Session 与 project/directory 的关联、切换时 working directory 未正确恢复
- **Changelog**：`Filter sessions at database level`、`Show all project sessions from any working directory` 等，说明 session 列表过滤逻辑有改动

## 修复方向

### A. iOS 端防御性修复（推荐，已实现）

在 `loadSessions()` 中：当 `currentSessionID` 指向的 session **不在** server 返回列表时，**保留**该 session 在本地 `sessions` 中（单独 fetch `GET /session/:id` 补全并 prepend），避免新建 session 被覆盖掉。

**已实现**：
- `APIClient.session(sessionID:)`：GET /session/:id 拉取单条 session
- `loadSessions()`：若 currentSessionID 不在 loaded 中，fetch 该 session 并 prepend 到 sessions，保证 currentSession 仍可解析

### B. 创建时对齐 project（需 API 支持）

若 OpenCode 未来支持 `POST /session` 传 `worktree` 或 `projectID`，iOS 应在创建时传入 `effectiveProjectDirectory` 对应的 project，确保新 session 落在用户选的 project 下。

### C. 不传 directory 时的一致性

当 `effectiveProjectDirectory == nil`（用户选 Server default）时，`GET /session` 不带 directory，会返回所有 project 的 sessions，新 session 会出现在列表中，问题不触发。

## 测试

### 单元测试

`SessionMergePreserveCurrentTests` 覆盖 `mergeCurrentSessionIfMissing` 逻辑：

```bash
cd OpenCodeClient && xcodebuild test -scheme OpenCodeClient \
  -destination 'platform=iOS Simulator,id=302F88CA-C2D3-4DC0-8E12-B3ED82D5A3C8' \
  -only-testing:OpenCodeClientTests/SessionMergePreserveCurrentTests
```

### 手动验证

1. 确保 OpenCode server 运行，且 server 的 current project（`GET /project/current`）与 iOS Settings 所选 project **不同**
2. 在 iOS 中：Settings → Project 选一个 project（如 knowledge_working）
3. 点 New Session，输入一些文字（不发送）
4. 点 Session List：新 session 应仍在列表顶部
5. 切后台再回前台：新 session 应仍在
6. 若仍有问题，在 Console.app 中过滤 `OpenCodeClient` / `AppState`，查看 `loadSessions` / `createSession` 的 debug log

---

## 间歇性消失（刷新后出现、过一会儿又消失）

### 现象

新建 session、发送消息正常，点 Session List 时不见 → 刷新后出现 → 过一会儿又消失，**Web 端也消失**。

### 可能原因（待 log 验证）

1. **session.updated 带 archived**：OpenCode 的 compact/summarize 可能将 session 标记为 archived。iOS 收到 `session.updated` 后替换本地 session；`sortedSessions` 默认过滤 `archived != nil`，session 从列表消失。若 Web 端也过滤 archived，则两端一致消失。
2. **session.deleted**：某处触发删除（如 compact 的副作用、或 server 端逻辑），SSE 推送 `session.deleted`，客户端移除。
3. **GET /session 服务端过滤**：`roots`、`archived` 等 query 可能影响返回结果；不同时刻、不同 client 传参不同，导致时有时无。
4. **Project/directory 竞态**：server 的 current project 或 instance 状态变化，导致同一 session 有时在、有时不在 filtered 结果中。

### 快速验证：archived 假设

若怀疑是 archived 导致：Settings → 打开「Show archived sessions」，看消失的 session 是否重新出现。若出现，则说明 server 将其标记为 archived，iOS 默认过滤掉了。

### 诊断 log（已添加）

复现时用 Console.app 过滤 `OpenCodeClient` 或 `AppState`，关注：

- `session.updated`：收到时打 id、archived、dir、op（replace/insert）
- `session.deleted`：收到时打 sessionID
- `loadSessions`：打 directory、count、archived 数量、currentInList、前 5 个 session id

若看到 `session.updated` 的 archived 从 nil 变为有值，或收到 `session.deleted`，即可定位触发源。
