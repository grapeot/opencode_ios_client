# Session 消失问题调研报告

> 2026-02-25

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

### A. iOS 端防御性修复（推荐，可立即做）

在 `loadSessions()` 中：当 `currentSessionID` 指向的 session **不在** server 返回列表时，**保留**该 session 在本地 `sessions` 中（可单独 fetch `GET /session/:id` 补全），避免新建 session 被覆盖掉。

### B. 创建时对齐 project（需 API 支持）

若 OpenCode 未来支持 `POST /session` 传 `worktree` 或 `projectID`，iOS 应在创建时传入 `effectiveProjectDirectory` 对应的 project，确保新 session 落在用户选的 project 下。

### C. 不传 directory 时的一致性

当 `effectiveProjectDirectory == nil`（用户选 Server default）时，`GET /session` 不带 directory，会返回所有 project 的 sessions，新 session 会出现在列表中，问题不触发。

## 建议的验证步骤

1. 在 iOS 中加 log（见下节），复现时确认：
   - `createSession` 返回的 session 的 `directory`
   - `loadSessions` 使用的 `effectiveProjectDirectory`
   - `loadSessions` 后 `currentSessionID` 是否仍在 `sessions` 中
2. 在 Settings 中切换 Project 选项（Server default vs 指定 project），对比行为
3. 确认 server 的 current project（`GET /project/current`）与 iOS 所选 project 是否一致
