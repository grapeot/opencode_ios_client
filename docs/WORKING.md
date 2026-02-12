# OpenCode iOS Client — Working Document

> 实现过程中的进度、问题与决策记录

## 当前状态

- **最后更新**：2026-02-12
- **Phase**：Phase 2 完成，UX 简化完成，UI 打磨完成
- **编译**：✅ 通过
- **测试**：✅ 35 个单元测试通过

## 已完成

- [x] Session 列表：Chat Tab 左侧列表按钮，展示 workspace 下所有 Session，支持切换、新建、下拉刷新
- [x] PRD 更新（async API、默认 server、移除大 session/推送/多项目）
- [x] RFC 更新（MarkdownUI、原生能力、Phase 4 暂不实现）
- [x] Git 初始化、.gitignore（含 opencode-official）、docs 移至 docs/
- [x] 初始 commit：docs、OpenCodeClient 脚手架
- [x] Phase 1 基础：Models、APIClient、SSEClient、AppState
- [x] Phase 1 UI：Chat Tab、Settings Tab、Files Tab（占位）
- [x] Phase 1 完善：SSE 事件解析、流式更新、Part.state 兼容、Markdown 渲染、工具调用全行显示
- [x] Phase 2：Part 渲染（reasoning 折叠、step 分隔线、patch 卡片）、权限手动批准、主题切换
- [x] UX 简化：一行 toolbar（左：新建/重命名/查看 session；右：3 模型图标），移除 Compact、Import、Model Presets
- [x] Phase 3：文件树（递归展开、按需加载）、文件内容（代码行号、Markdown Preview 切换）、Files Tab 双模式（File Tree / Session Changes）、文件搜索
- [x] Tool/Patch 点击跳转：write/edit/apply_patch 等含 path 的 tool，点击可「在 File Tree 中打开」文件预览（path 来自 metadata、state.input.path/file_path/filePath、patchText 解析）
- [x] apply_patch path 解析修复：patchText 以 "*** Begin Patch\n*** Add File: " 开头，改用 range(of:) 查找
- [x] Tool 卡片增加「在 File Tree 中打开」按钮（label 旁文件夹图标）+ context menu
- [x] Markdown 预览：使用 MarkdownUI 库（swift-markdown-ui 2.4.1）替代自定义渲染，完整支持 GFM（表格、标题、代码块、列表等）
- [x] 单元测试：defaultServerAddress、sessionDecoding、messageDecoding、sseEvent、partDecoding
- [x] UI 打磨：放大输入框（3-8 行，capsule 形状）、模型选择器胶囊渐变、渲染风格 SF Symbols、消息气泡优化、工具/补丁/权限卡片圆角柔化、MarkdownUI 用于 chat 消息渲染

## 待办

- [ ] **Sync Streaming**：delta 增量更新、Tool 完成后收起（见 [SYNC_STREAMING_RESEARCH.md](SYNC_STREAMING_RESEARCH.md)）
- [ ] Phase 3：完善 Diff 行级高亮、语法高亮（可选）
- [ ] 与真实 OpenCode Server 联调验证

## 遇到的问题

1. **Local network prohibited (iOS)**：连接 `192.168.180.128:4096` 时报错 `Local network prohibited`。需在 Info.plist 添加：
   - `NSLocalNetworkUsageDescription`：说明为何需要本地网络，首次访问会弹出权限弹窗
   - `NSAppTransportSecurity` → `NSAllowsLocalNetworking`：允许 HTTP 访问本地 IP
   - 用户需在弹窗中要点「允许」才能连接

2. **发送后卡住**：发送失败时无反馈，输入框已清空导致用户不知道失败。修复：发送失败时恢复输入、显示错误 alert、发送中显示 loading

3. **发送后无实时更新**：发送成功、web 端已有回应，但 iOS 端需重启才能看到。原因：
   - SSE 仅在 `willEnterForegroundNotification` 时连接，首次启动时未连接
   - 部分事件（如 `server.connected`）无 `directory` 字段，解析失败
   - 修复：在 `refresh()` 成功后调用 `connectSSE()`；`SSEEvent.directory` 改为可选；发送成功后启动 60 秒轮询（每 2 秒 loadMessages）作为 fallback

4. **loadMessages 解析失败**：LLM 输出 thinking delta 时，`Part.state` 期望 String 但 API 返回 object（ToolState）。报错：`Expected to decode String but found a dictionary`。修复：新增 `PartStateBridge`，支持 state 为 String 或 object，object 时提取 `status`/`title` 用于 UI 显示

5. **Unable to simultaneously satisfy constraints**：键盘相关 (TUIKeyboardContentView, UIKeyboardImpl) 的约束冲突。来自系统键盘，非应用代码，通常无需修复。

6. **术语澄清**：Sync streaming 实指 Think（ReasoningPartView）的展开/收起行为，非 Tool。

## 决策记录

（记录实现过程中的技术决策）

## API 验证（192.168.180.128:4096）

- **GET /global/health**：✅ `{ healthy, version }`
- **GET /config/providers**：✅ 返回 `providers: array`（非 dict），每项含 `id`, `name`, `models: { modelID: ModelInfo }`。已修复 iOS 解析。
- **Import from Server**：依赖 config/providers，解析修复后应可正常导入。

用户指定模型对应：
- OpenAI GPT-5.2：✅ `openai` / `gpt-5.2`
- POE Opus Claude 4.6：✅ `poe` / `anthropic/claude-opus-4-6`
- z.ai coding plan GLM-4.7：✅ `zai-coding-plan` / `glm-4.7`

## Diff 问题

`GET /session/:id/diff` 实测返回 `[]`，即使 session 有 write 操作。GH #10920 等表明可能是 OpenCode server 端 session_diff 追踪问题，官方 web 客户端也可能遇到。暂不修复，待 server 端修复。
