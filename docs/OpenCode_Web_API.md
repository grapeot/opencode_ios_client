# OpenCode Web API 技术文档

> 最后核对：2026-08-23 · origin/dev @ 03bba464d

> 本文档基于 OpenCode 官方文档 (opencode.ai/docs) 及 anomalyco/opencode 仓库源码整理，用于了解 OpenCode 的 Web 界面与 HTTP API 能力。

## 1. 概述

OpenCode 是一个开源的 AI 编程 Agent，采用 **Client/Server 架构**。运行 `opencode` 时会同时启动 TUI 和 HTTP Server，其中 TUI 作为客户端与 Server 通信。该架构使得：

- Web 界面、Desktop App、IDE 插件均可作为**不同的客户端**接入同一后端
- 支持通过 HTTP API 进行**程序化调用**

### 1.1 仓库与版本说明

| 仓库 | 说明 |
|------|------|
| **anomalyco/opencode** | 官方主仓库，提供 `opencode serve`、`opencode web` 及完整 HTTP API |
| **opencode-ai/opencode** | 社区 fork，已归档，项目已迁移至 Crush |
| **chris-tse/opencode-web** | 第三方 Web UI，基于 OpenCode API 的 React 前端 |

本 repo 中 clone 的为 `anomalyco/opencode`（官方主仓库），含 serve/web 命令及完整 HTTP API。

当前 API 分为两层：

- **Legacy API**（无 `/api` 前缀）：实例级路由，通过 `x-opencode-directory` header 或 query 参数定位 workspace。
- **V2 API**（`/api` 前缀）：Protocol 层定义的新接口，面向 SDK 和跨 workspace 客户端。

---

## 2. 启动方式

### 2.1 无头 Server（仅 API）

```bash
opencode serve [--port <number>] [--hostname <string>] [--cors <origin>]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | 监听端口 | `0`（自动：先试 4096，被占用则取随机空闲端口） |
| `--hostname` | 监听地址 | `127.0.0.1` |
| `--mdns` | 启用 mDNS 发现（自动绑定 `0.0.0.0`） | `false` |
| `--mdns-domain` | mDNS 域名 | `opencode.local` |
| `--cors` | 允许的 CORS 来源（可传多次） | `[]` |

> 未指定端口时 server 先尝试 4096，被占用则取随机空闲端口（`startWithPortFallback` 逻辑）。可用 `--port` 或 config 的 `server.port` 显式指定，显式 `--port` 优先级最高；config 的 `server.port` 可选、无默认值。

### 2.2 Web 界面（API + 内置 Web UI）

```bash
opencode web
```

- 默认在 `127.0.0.1` 启动，端口先试 4096、被占用则取随机空闲端口
- 自动打开浏览器
- 与 `opencode serve` 共享同一 API

### 2.3 认证（可选）

```bash
OPENCODE_SERVER_PASSWORD=your-password opencode serve
# 或
OPENCODE_SERVER_USERNAME=admin OPENCODE_SERVER_PASSWORD=secret opencode web
```

- 用户名默认 `opencode`
- 适用于 `opencode serve` 与 `opencode web`
- 未设置密码时 server 会打印 warning 并处于无认证状态

---

## 3. OpenAPI 规范

- **地址**: `http://<hostname>:<port>/doc`
- **示例**: `http://localhost:4096/doc`
- **格式**: OpenAPI 3.1
- **用途**: 查看请求/响应类型、生成 SDK、Swagger 预览
- 响应为 JSON（`OpenApi.fromApi(PublicApi)` 生成），带 legacy 兼容层

---

## 4. API 分类总览

### 4.1 Global（全局）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/global/health` | 健康检查与版本 | `{ healthy: true, version }` |
| GET | `/global/event` | 全局事件流（SSE） | Event stream |
| GET | `/global/config` | 获取全局配置 | `Config` |
| PATCH | `/global/config` | 更新全局配置 | `Config` |
| POST | `/global/dispose` | 销毁所有实例，释放资源 | `boolean` |
| POST | `/global/upgrade` | 升级 opencode 到指定版本或最新 | `{ success, version }` 或 `{ success: false, error }` |

### 4.2 Control（控制面）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| PUT | `/auth/:providerID` | 设置认证凭证 | `boolean` |
| DELETE | `/auth/:providerID` | 删除认证凭证 | `boolean` |
| POST | `/log` | 写日志（body: `{ service, level, message, extra? }`） | `boolean` |
| POST | `/experimental/control-plane/move-session` | 跨项目移动 session | `204 No Content` |

### 4.3 Project

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/project` | 列出所有项目 | `Project[]` |
| GET | `/project/current` | 当前项目 | `Project` |
| POST | `/project/git/init` | 为当前项目初始化 git 仓库 | `Project` |
| PATCH | `/project/:projectID` | 更新项目属性（name, icon, commands） | `Project` |
| GET | `/project/:projectID/directories` | 列出项目已知目录 | `ProjectDirectories` |

### 4.4 Path & VCS

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/path` | 当前路径信息 | `Path` |
| GET | `/vcs` | 当前项目 VCS 信息 | `VcsInfo` |
| GET | `/vcs/status` | 工作树变更文件列表（无 patch） | `VcsFileStatus[]` |
| GET | `/vcs/diff` | 当前 git diff（支持 `mode`, `context` 参数） | `VcsFileDiff[]` |
| GET | `/vcs/diff/raw` | 原始 patch 文本 | `string` (text/x-diff) |
| POST | `/vcs/apply` | 应用 patch 到工作树 | `VcsApplyResult` |

### 4.5 Instance

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/instance/dispose` | 销毁当前实例 | `boolean` |
| GET | `/command` | 列出所有命令 | `Command[]` |
| GET | `/agent` | 列出所有 Agent | `Agent[]` |
| GET | `/skill` | 列出所有 Skill | `Skill[]` |
| GET | `/lsp` | LSP 服务状态 | `LSPStatus[]` |
| GET | `/formatter` | Formatter 状态 | `FormatterStatus[]` |

### 4.6 Config

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/config` | 获取配置 | `Config` |
| PATCH | `/config` | 更新配置 | `Config` |
| GET | `/config/providers` | 列出 Provider 及默认模型 | `{ providers, default }` |

### 4.7 Provider

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/provider` | 列出所有 Provider | `{ all, default, connected }` |
| GET | `/provider/auth` | Provider 认证方式 | `{ [providerID]: ProviderAuthMethod[] }` |
| POST | `/provider/:providerID/oauth/authorize` | OAuth 授权 | `ProviderAuthAuthorization` |
| POST | `/provider/:providerID/oauth/callback` | OAuth 回调 | `boolean` |

### 4.8 Sessions（会话管理）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/session` | 列出所有会话（支持 `scope`, `path`, `roots`, `start`, `search`, `limit` 查询参数） | `Session[]` |
| POST | `/session` | 创建会话（body 可选：`parentID`, `title`, `agent`, `model`, `metadata`, `permission`, `workspaceID`） | `Session` |
| GET | `/session/status` | 所有会话状态 | `{ [sessionID]: SessionStatus }` |
| GET | `/session/:sessionID` | 会话详情 | `Session` |
| DELETE | `/session/:sessionID` | 删除会话 | `boolean` |
| PATCH | `/session/:sessionID` | 更新会话（title, metadata, permission, time.archived） | `Session` |
| GET | `/session/:sessionID/children` | 子会话列表 | `Session[]` |
| GET | `/session/:sessionID/todo` | 会话 Todo 列表 | `Todo[]` |
| POST | `/session/:sessionID/init` | 分析项目并创建 AGENTS.md（body: `{ modelID, providerID, messageID }`） | `boolean` |
| POST | `/session/:sessionID/fork` | 从某条消息 fork 会话 | `Session` |
| POST | `/session/:sessionID/abort` | 中止运行中的会话 | `boolean` |
| POST | `/session/:sessionID/share` | 分享会话 | `Session` |
| DELETE | `/session/:sessionID/share` | 取消分享 | `Session` |
| GET | `/session/:sessionID/diff` | 会话 diff | `FileDiff[]` |
| POST | `/session/:sessionID/summarize` | 会话摘要（body: `{ providerID, modelID, auto? }`） | `boolean` |
| POST | `/session/:sessionID/revert` | 回滚某条消息（body: `{ messageID, partID? }`） | `Session` |
| POST | `/session/:sessionID/unrevert` | 恢复所有回滚 | `Session` |
| POST | `/session/:sessionID/permissions/:permissionID` | 响应权限请求（**deprecated**，改用 `/permission/:requestID/reply`） | `boolean` |
| DELETE | `/session/:sessionID/message/:messageID` | 删除单条消息（不 revert 文件变更） | `boolean` |
| DELETE | `/session/:sessionID/message/:messageID/part/:partID` | 删除消息中的某个 part | `boolean` |
| PATCH | `/session/:sessionID/message/:messageID/part/:partID` | 更新消息中的某个 part | `Part` |

### 4.9 Messages（消息与 AI 交互）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/session/:sessionID/message` | 列出会话消息（支持 `limit`, `before` 分页） | `{ info, parts }[]` |
| GET | `/session/:sessionID/message/:messageID` | 单条消息详情 | `{ info, parts }` |
| POST | `/session/:sessionID/message` | 发送消息并等待响应（SSE 流式） | `{ info, parts }` |
| POST | `/session/:sessionID/prompt_async` | 异步发送消息（不等待）；body `parts` 可包含 `text` / `file`（图片使用 `data:` URL） | `204 No Content` |
| POST | `/session/:sessionID/command` | 执行 slash 命令 | `{ info, parts }` |
| POST | `/session/:sessionID/shell` | 执行 shell 命令 | `{ info, parts }` |

### 4.10 Files（文件与搜索）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/find?pattern=<pat>` | 文本搜索（ripgrep） | `LegacyMatch[]` |
| GET | `/find/file?query=<q>` | 按名称查找文件/目录 | `string[]` |
| GET | `/find/symbol?query=<q>` | 工作区符号搜索（LSP） | `Symbol[]` |
| GET | `/file?path=<path>` | 列出文件/目录 | `FileNode[]` |
| GET | `/file/content?path=<p>` | 读取文件内容 | `FileContent` |
| GET | `/file/status` | 跟踪文件状态（git status） | `File[]` |

**`/find/file` 查询参数**：`query`（必填）、`type`（file/directory）、`directory`、`limit`（1–200）、`dirs`（可选）

### 4.11 MCP

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/mcp` | MCP 服务状态 | `{ [name]: MCPStatus }` |
| POST | `/mcp` | 动态添加 MCP 服务（body: `{ name, config }`） | `{ [name]: MCPStatus }` |
| POST | `/mcp/:name/auth` | 启动 MCP OAuth 流程 | `{ authorizationUrl, oauthState }` |
| POST | `/mcp/:name/auth/callback` | 完成 MCP OAuth（body: `{ code }`） | `MCPStatus` |
| POST | `/mcp/:name/auth/authenticate` | 启动 OAuth 并等待回调（打开浏览器） | `MCPStatus` |
| DELETE | `/mcp/:name/auth` | 删除 MCP OAuth 凭证 | `{ success: true }` |
| POST | `/mcp/:name/connect` | 连接 MCP 服务 | `boolean` |
| POST | `/mcp/:name/disconnect` | 断开 MCP 服务 | `boolean` |

### 4.12 Experimental（实验性）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/experimental/capabilities` | 实验性功能开关 | `{ backgroundSubagents }` |
| GET | `/experimental/console` | 活跃 Console provider 元数据 | `{ consoleManagedProviders, activeOrgName?, switchableOrgCount }` |
| GET | `/experimental/console/orgs` | 可切换的 Console org 列表 | `{ orgs: ConsoleOrgOption[] }` |
| POST | `/experimental/console/switch` | 切换活跃 Console org（body: `{ accountID, orgID }`） | `boolean` |
| GET | `/experimental/tool` | 某模型的工具及 JSON Schema（query: `provider`, `model`） | `ToolList` |
| GET | `/experimental/tool/ids` | 列出所有工具 ID | `string[]` |
| GET | `/experimental/worktree` | 列出沙箱 worktree | `string[]` |
| POST | `/experimental/worktree` | 创建 git worktree 并运行启动脚本 | `WorktreeInfo` |
| DELETE | `/experimental/worktree` | 删除 worktree 及其分支 | `boolean` |
| POST | `/experimental/worktree/reset` | 重置 worktree 分支到主分支 | `boolean` |
| GET | `/experimental/session` | 跨项目列出所有会话（支持 `roots`, `start`, `cursor`, `search`, `limit`, `archived`） | `GlobalSession[]` |
| POST | `/experimental/session/:sessionID/background` | 将阻塞的 subagent 转入后台 | `boolean` |
| GET | `/experimental/resource` | 获取所有 MCP resources | `{ [name]: MCPResource }` |

### 4.13 Question（AI 提问）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/question` | 列出所有待回答的 question | `QuestionRequest[]` |
| POST | `/question/:requestID/reply` | 回答 question（body: `{ answers: string[][] }`） | `boolean` |
| POST | `/question/:requestID/reject` | 拒绝 question | `boolean` |

### 4.14 Permission（权限）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/permission` | 列出所有待处理的权限请求 | `PermissionRequest[]` |
| POST | `/permission/:requestID/reply` | 响应权限请求（body: `{ reply, message? }`） | `boolean` |

### 4.15 PTY（伪终端）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/pty/shells` | 列出可用 shell | `ShellItem[]` |
| GET | `/pty` | 列出所有 PTY 会话 | `PtyInfo[]` |
| POST | `/pty` | 创建 PTY 会话 | `PtyInfo` |
| GET | `/pty/:ptyID` | 获取 PTY 会话详情 | `PtyInfo` |
| PUT | `/pty/:ptyID` | 更新 PTY 会话属性 | `PtyInfo` |
| DELETE | `/pty/:ptyID` | 终止并删除 PTY 会话 | `boolean` |
| POST | `/pty/:ptyID/connect-token` | 创建 WebSocket 连接 ticket | `ConnectToken` |
| GET | `/pty/:ptyID/connect` | WebSocket 连接（实时 PTY 交互） | WebSocket |

### 4.16 Workspace（实验性）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/experimental/workspace/adapter` | 列出可用 workspace adapter | `WorkspaceAdapterEntry[]` |
| GET | `/experimental/workspace` | 列出所有 workspace | `WorkspaceInfo[]` |
| POST | `/experimental/workspace` | 创建 workspace | `WorkspaceInfo` |
| POST | `/experimental/workspace/sync-list` | 注册 adapter 返回的缺失 workspace | `204 No Content` |
| GET | `/experimental/workspace/status` | workspace 连接状态 | `WorkspaceConnectionStatus[]` |
| DELETE | `/experimental/workspace/:id` | 删除 workspace | `WorkspaceInfo`（或空响应） |
| POST | `/experimental/workspace/warp` | 将 session 同步历史移入/移出 workspace（body: `{ id, sessionID, copyChanges }`） | `204 No Content` |

### 4.17 Project Copy（实验性）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/experimental/project/:projectID/copy/generate-name` | 从 task context 生成项目副本名称（body: `{ context? }`） | `{ name }` |

### 4.18 Sync（同步）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/sync/start` | 启动 workspace 同步循环 | `boolean` |
| POST | `/sync/replay` | 验证并重放完整 sync 事件历史（body: `{ directory, events[] }`） | `{ sessionID }` |
| POST | `/sync/steal` | 将 session 移入当前 workspace（body: `{ sessionID }`） | `{ sessionID }` |
| POST | `/sync/history` | 列出 sync 事件（body: `{ [aggregateID]: lastSeq }`） | `HistoryEvent[]` |

### 4.19 TUI 控制（供 IDE 等客户端）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/tui/append-prompt` | 追加到输入框 | `boolean` |
| POST | `/tui/open-help` | 打开帮助 | `boolean` |
| POST | `/tui/open-sessions` | 打开会话选择器 | `boolean` |
| POST | `/tui/open-themes` | 打开主题选择器 | `boolean` |
| POST | `/tui/open-models` | 打开模型选择器 | `boolean` |
| POST | `/tui/submit-prompt` | 提交当前输入 | `boolean` |
| POST | `/tui/clear-prompt` | 清空输入 | `boolean` |
| POST | `/tui/execute-command` | 执行命令（body: `{ command }`） | `boolean` |
| POST | `/tui/show-toast` | 显示 Toast（body: `{ title?, message, variant }`） | `boolean` |
| POST | `/tui/publish` | 发布 TUI 事件（union: promptAppend / commandExecute / toastShow / sessionSelect） | `boolean` |
| POST | `/tui/select-session` | 导航 TUI 到指定 session | `boolean` |
| GET | `/tui/control/next` | 等待下一个控制请求 | `TuiRequest` |
| POST | `/tui/control/response` | 响应控制请求（body 为待响应的控制请求内容，服务端按 unknown 透传） | `boolean` |

### 4.20 Events

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/event` | 实例级 SSE 事件流 | 首事件 `server.connected`，之后为 bus 事件 |

### 4.21 Docs

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/doc` | OpenAPI 3.1 规范 | JSON |

### 4.22 V2 API（`/api` 前缀）

V2 API 由 `@opencode-ai/protocol` 包定义，面向 SDK 和跨 workspace 客户端。绝大多数路径以 `/api` 为前缀；project-copy 组例外，沿用 `/experimental/project/:projectID/copy` 路径。

| Method | Path | 说明 |
|--------|------|------|
| GET | `/api/health` | 服务器健康检查 |
| GET | `/api/location` | 解析请求的 location 或默认 location |
| GET | `/api/agent` | 列出已注册 agents |
| GET | `/api/session` | 列出 sessions（支持 cursor 分页、`order`、`search`、`limit`） |
| POST | `/api/session` | 创建 session |
| GET | `/api/session/active` | 列出活跃 sessions |
| GET | `/api/session/:sessionID` | 获取 session |
| POST | `/api/session/:sessionID/agent` | 切换 session agent |
| POST | `/api/session/:sessionID/model` | 切换 session model |
| POST | `/api/session/:sessionID/prompt` | 发送消息（durable admission + 调度执行） |
| POST | `/api/session/:sessionID/compact` | 压缩 session 对话 |
| POST | `/api/session/:sessionID/wait` | 等待 session 完成 |
| POST | `/api/session/:sessionID/revert/stage` | 回滚 stage |
| POST | `/api/session/:sessionID/revert/clear` | 清除回滚 |
| POST | `/api/session/:sessionID/revert/commit` | 提交回滚 |
| GET | `/api/session/:sessionID/context` | 获取 session context |
| GET | `/api/session/:sessionID/history` | 获取 session 历史 |
| GET | `/api/session/:sessionID/event` | 获取 session 事件流 |
| POST | `/api/session/:sessionID/interrupt` | 中断 session |
| GET | `/api/session/:sessionID/message` | 列出 session 消息（cursor 分页） |
| GET | `/api/session/:sessionID/message/:messageID` | 获取单条消息 |
| GET | `/api/model` | 列出可用模型 |
| GET | `/api/provider` | 列出活跃 providers |
| GET | `/api/provider/:providerID` | 获取单个 provider |
| GET | `/api/integration` | 列出 integrations 及认证方式 |
| GET | `/api/integration/:integrationID` | 获取单个 integration |
| POST | `/api/integration/:integrationID/connect/key` | 使用 key 连接 |
| POST | `/api/integration/:integrationID/connect/oauth` | 启动 OAuth 连接 |
| GET | `/api/integration/attempt/:attemptID` | 轮询 OAuth attempt 状态 |
| POST | `/api/integration/attempt/:attemptID/complete` | 完成 OAuth 连接 |
| DELETE | `/api/integration/attempt/:attemptID` | 取消 OAuth 连接 |
| PATCH | `/api/credential/:credentialID` | 更新 credential 标签 |
| DELETE | `/api/credential/:credentialID` | 删除 credential |
| GET | `/api/permission/request` | 列出待处理权限请求 |
| GET | `/api/permission/saved` | 列出已保存权限 |
| DELETE | `/api/permission/saved/:id` | 删除已保存权限 |
| POST | `/api/session/:sessionID/permission` | 创建权限请求 |
| GET | `/api/session/:sessionID/permission` | 列出 session 权限请求 |
| GET | `/api/session/:sessionID/permission/:requestID` | 获取权限请求 |
| POST | `/api/session/:sessionID/permission/:requestID/reply` | 响应权限请求 |
| GET | `/api/fs/read/*` | 读取文件（location 相对路径） |
| GET | `/api/fs/list` | 列出目录 |
| GET | `/api/fs/find` | 递归查找文件 |
| GET | `/api/command` | 列出命令 |
| GET | `/api/skill` | 列出 skills |
| GET | `/api/pty` | 列出 PTY 会话 |
| POST | `/api/pty` | 创建 PTY 会话 |
| GET | `/api/pty/:ptyID` | 获取 PTY 会话 |
| PUT | `/api/pty/:ptyID` | 更新 PTY 会话 |
| DELETE | `/api/pty/:ptyID` | 删除 PTY 会话 |
| POST | `/api/pty/:ptyID/connect-token` | 创建 PTY WebSocket token |
| GET | `/api/pty/:ptyID/connect` | PTY WebSocket 连接 |
| GET | `/api/question/request` | 列出待处理 question |
| GET | `/api/session/:sessionID/question` | 列出 session question |
| POST | `/api/session/:sessionID/question/:requestID/reply` | 回答 question |
| POST | `/api/session/:sessionID/question/:requestID/reject` | 拒绝 question |
| GET | `/api/reference` | 列出 references |
| POST | `/experimental/project/:projectID/copy` | 创建项目副本 |
| DELETE | `/experimental/project/:projectID/copy` | 删除项目副本 |
| POST | `/experimental/project/:projectID/copy/refresh` | 刷新项目副本 |
| GET | `/api/event` | V2 事件流（SSE） |

---

## 5. 典型使用场景

### 5.1 程序化发送消息

```bash
# 创建会话
curl -X POST http://localhost:4096/session -H "Content-Type: application/json" -d '{"title":"My Task"}'

# 发送消息（替换 :sessionId）
curl -X POST http://localhost:4096/session/:sessionId/message \
  -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"解释这段代码的作用"}]}'
```

### 5.2 异步发送（不等待 AI 完成）

```bash
curl -X POST http://localhost:4096/session/:sessionId/prompt_async \
  -H "Content-Type: application/json" \
  -d '{"parts":[{"type":"text","text":"Refactor this function"}]}'
```

### 5.3 文件搜索与读取

```bash
# 查找文件
curl "http://localhost:4096/find/file?query=config"

# 读取文件
curl "http://localhost:4096/file/content?path=src/main.go"
```

### 5.4 IDE 插件驱动 TUI

通过 `--hostname`、`--port` 指定 TUI 的 Server 地址，IDE 插件可调用 `/tui/append-prompt`、`/tui/submit-prompt` 等接口预填并提交 prompt。

### 5.5 使用 V2 API（SDK 客户端）

```bash
# 列出 sessions
curl "http://localhost:4096/api/session?limit=10&order=desc"

# 发送 prompt（V2 用 prompt.text，不是 legacy 的 parts 形状）
curl -X POST http://localhost:4096/api/session/:sessionID/prompt \
  -H "Content-Type: application/json" \
  -d '{"prompt": {"text": "Hello"}}'
```

---

## 6. 相关生态

| 项目 | 说明 |
|------|------|
| **opencode web** | 官方内置 Web UI，随 `opencode web` 启动 |
| **opencode-web** (chris-tse) | 第三方 Web 前端，基于 React + SSE，需先运行 `opencode serve` |
| **OpenCode IDE 插件** | VS Code / Cursor 等插件，通过 API 与本地 Server 通信 |
| **@opencode-ai/protocol** | V2 API 协议定义包，SDK 生成依赖 |
| **@opencode-ai/sdk** | 官方 JS SDK（legacy + V2） |

---

## 7. 与 OpenClaw 的对比（简要）

| 维度 | OpenCode | OpenClaw |
|------|----------|----------|
| 入口 | TUI / Web / IDE / CLI | 消息平台（WhatsApp/Telegram 等） |
| 定位 | 编程 Agent | 生活/自动化 Gateway |
| API | 完整 HTTP API + OpenAPI + V2 Protocol | 以 Gateway 为主，非通用 HTTP API |
| 记忆 | 会话 + AGENTS.md + workspace sync | MEMORY.md / SOUL.md 等 |
| 扩展 | MCP / Skills / Worktree / Workspace | Skills（ClawHub） |

OpenCode 的 Web + API 架构，为「统一入口 + 程序化调用」提供了可复用的参考实现。

---

## 8. 参考链接

- [OpenCode 官方文档 - Server](https://opencode.ai/docs/server/)
- [OpenCode 官方文档 - Web](https://opencode.ai/docs/web/)
- [anomalyco/opencode](https://github.com/anomalyco/opencode)（官方仓库）
- [chris-tse/opencode-web](https://github.com/chris-tse/opencode-web)（第三方 Web UI）
- 源码路由定义：`packages/opencode/src/server/routes/instance/httpapi/groups/`
- V2 Protocol 定义：`packages/protocol/src/groups/`
