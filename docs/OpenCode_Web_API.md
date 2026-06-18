# OpenCode Web API 技术文档

> 本文档基于 OpenCode 官方文档 (opencode.ai/docs) 及 anomalyco/opencode 仓库调研整理，用于了解 OpenCode 的 Web 界面与 HTTP API 能力。

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

---

## 2. 启动方式

### 2.1 无头 Server（仅 API）

```bash
opencode serve [--port <number>] [--hostname <string>] [--cors <origin>]
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--port` | 监听端口 | `4096` |
| `--hostname` | 监听地址 | `127.0.0.1` |
| `--mdns` | 启用 mDNS 发现 | `false` |
| `--mdns-domain` | mDNS 域名 | `opencode.local` |
| `--cors` | 允许的 CORS 来源（可传多次） | `[]` |

### 2.2 Web 界面（API + 内置 Web UI）

```bash
opencode web
```

- 默认在 `127.0.0.1` 随机端口启动
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

---

## 3. OpenAPI 规范

- **地址**: `http://<hostname>:<port>/doc`
- **示例**: `http://localhost:4096/doc`
- **格式**: OpenAPI 3.1
- **用途**: 查看请求/响应类型、生成 SDK、Swagger 预览

---

## 4. API 分类总览

### 4.1 Global

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/global/health` | 健康检查与版本 | `{ healthy, version }` |
| GET | `/global/event` | 全局事件流（SSE） | Event stream |

### 4.2 Project

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/project` | 列出所有项目 | `Project[]` |
| GET | `/project/current` | 当前项目 | `Project` |

### 4.3 Path & VCS

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/path` | 当前路径 | `Path` |
| GET | `/vcs` | 当前项目 VCS 信息 | `VcsInfo` |

### 4.4 Instance

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/instance/dispose` | 销毁当前实例 | `boolean` |

### 4.5 Config

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/config` | 获取配置 | `Config` |
| PATCH | `/config` | 更新配置 | `Config` |
| GET | `/config/providers` | 列出 Provider 及默认模型 | `{ providers, default }` |

### 4.6 Provider

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/provider` | 列出所有 Provider | `{ all, default, connected }` |
| GET | `/provider/auth` | Provider 认证方式 | `{ [providerID]: ProviderAuthMethod[] }` |
| POST | `/provider/{id}/oauth/authorize` | OAuth 授权 | `ProviderAuthAuthorization` |
| POST | `/provider/{id}/oauth/callback` | OAuth 回调 | `boolean` |

### 4.7 Sessions（会话管理）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/session` | 列出所有会话 | `Session[]` |
| POST | `/session` | 创建会话 | `Session`（body: `{ parentID?, title? }`） |
| GET | `/session/status` | 所有会话状态 | `{ [sessionID]: SessionStatus }` |
| GET | `/session/:id` | 会话详情 | `Session` |
| DELETE | `/session/:id` | 删除会话 | `boolean` |
| PATCH | `/session/:id` | 更新会话（如 title） | `Session` |
| GET | `/session/:id/children` | 子会话列表 | `Session[]` |
| GET | `/session/:id/todo` | 会话 Todo 列表 | `Todo[]` |
| POST | `/session/:id/init` | 分析项目并创建 AGENTS.md | `boolean` |
| POST | `/session/:id/fork` | 从某条消息 fork 会话 | `Session` |
| POST | `/session/:id/abort` | 中止运行中的会话 | `boolean` |
| POST | `/session/:id/share` | 分享会话 | `Session` |
| DELETE | `/session/:id/share` | 取消分享 | `Session` |
| GET | `/session/:id/diff` | 会话 diff | `FileDiff[]` |
| POST | `/session/:id/summarize` | 会话摘要 | `boolean` |
| POST | `/session/:id/revert` | 回滚某条消息（body: `{ messageID, partID? }`） | `Session` |
| POST | `/session/:id/unrevert` | 恢复所有回滚 | `Session` |
| POST | `/session/:id/permissions/:permissionID` | 响应权限请求 | `boolean` |

### 4.8 Messages（消息与 AI 交互）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/session/:id/message` | 列出会话消息 | `{ info, parts }[]` |
| POST | `/session/:id/message` | 发送消息并等待响应 | `{ info, parts }` |
| GET | `/session/:id/message/:messageID` | 单条消息详情 | `{ info, parts }` |
| POST | `/session/:id/prompt_async` | 异步发送消息（不等待） | `204 No Content` |
| POST | `/session/:id/command` | 执行 slash 命令 | `{ info, parts }` |
| POST | `/session/:id/shell` | 执行 shell 命令 | `{ info, parts }` |

### 4.9 Commands

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/command` | 列出所有命令 | `Command[]` |

### 4.10 Files（文件与搜索）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/find?pattern=<pat>` | 文本搜索 | Match 数组 |
| GET | `/find/file?query=<q>` | 按名称查找文件/目录 | `string[]` |
| GET | `/find/symbol?query=<q>` | 工作区符号搜索 | `Symbol[]` |
| GET | `/file?path=<path>` | 列出文件/目录 | `FileNode[]` |
| GET | `/file/content?path=<p>` | 读取文件内容 | `FileContent` |
| GET | `/file/status` | 跟踪文件状态 | `File[]` |

**`/find/file` 查询参数**：`query`（必填）、`type`（file/directory）、`directory`、`limit`（1–200）、`dirs`（可选）

### 4.11 Tools（实验性）

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/experimental/tool/ids` | 列出所有工具 ID | `ToolIDs` |
| GET | `/experimental/tool?provider=<p>&model=<m>` | 某模型的工具及 JSON Schema | `ToolList` |

### 4.12 LSP / Formatter / MCP

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/lsp` | LSP 服务状态 | `LSPStatus[]` |
| GET | `/formatter` | Formatter 状态 | `FormatterStatus[]` |
| GET | `/mcp` | MCP 服务状态 | `{ [name]: MCPStatus }` |
| POST | `/mcp` | 动态添加 MCP 服务 | MCP status |

### 4.13 Agents

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/agent` | 列出所有 Agent | `Agent[]` |

### 4.14 Logging

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| POST | `/log` | 写日志 | `boolean`（body: `{ service, level, message, extra? }`） |

### 4.15 TUI 控制（供 IDE 等客户端）

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
| GET | `/tui/control/next` | 等待下一个控制请求 | Control request |
| POST | `/tui/control/response` | 响应控制请求（body: `{ body }`） | `boolean` |

### 4.16 Auth

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| PUT | `/auth/:id` | 设置认证凭证 | `boolean` |

### 4.17 Events

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/event` | SSE 事件流 | 首事件 `server.connected`，之后为 bus 事件 |

### 4.18 Docs

| Method | Path | 说明 | 响应 |
|--------|------|------|------|
| GET | `/doc` | OpenAPI 3.1 规范 | HTML 页面 |

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

---

## 6. 相关生态

| 项目 | 说明 |
|------|------|
| **opencode web** | 官方内置 Web UI，随 `opencode web` 启动 |
| **opencode-web** (chris-tse) | 第三方 Web 前端，基于 React + SSE，需先运行 `opencode serve` |
| **OpenCode IDE 插件** | VS Code / Cursor 等插件，通过 API 与本地 Server 通信 |

---

## 7. 与 OpenClaw 的对比（简要）

| 维度 | OpenCode | OpenClaw |
|------|----------|----------|
| 入口 | TUI / Web / IDE / CLI | 消息平台（WhatsApp/Telegram 等） |
| 定位 | 编程 Agent | 生活/自动化 Gateway |
| API | 完整 HTTP API + OpenAPI | 以 Gateway 为主，非通用 HTTP API |
| 记忆 | 会话 + AGENTS.md | MEMORY.md / SOUL.md 等 |
| 扩展 | MCP / Skills | Skills（ClawHub） |

OpenCode 的 Web + API 架构，为「统一入口 + 程序化调用」提供了可复用的参考实现。

---

## 8. 参考链接

- [OpenCode 官方文档 - Server](https://opencode.ai/docs/server/)
- [OpenCode 官方文档 - Web](https://opencode.ai/docs/web/)
- [anomalyco/opencode](https://github.com/anomalyco/opencode)（官方仓库）
- [chris-tse/opencode-web](https://github.com/chris-tse/opencode-web)（第三方 Web UI）
