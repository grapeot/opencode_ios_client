# OpenCode iOS Client — Working Document

> 实现过程中的进度、问题与决策记录

## 当前状态

- **最后更新**：2026-02-12
- **Phase**：Phase 3 完成（Think Streaming + iPad 分栏）
- **编译**：✅ 通过
- **测试**：✅ 60 个单元测试通过

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
- [x] Chat：AI response 支持文字选择/复制（含 Markdown 渲染）
- [x] Chat → 文件跳转：改用 URLComponents 编码 query，统一规范化 file path；补充空内容 warning log
- [x] Tool 卡片：理由/标题收起态最多两行 + 省略号，展开态显示完整 Reason
- [x] Session Todo（task list）：支持 `/session/:id/todo` 拉取 + SSE `todo.updated` 更新；`todowrite` tool 卡片内渲染 todo（方案 B，不做顶部常驻）
- [x] Phase 3：Think Streaming delta（见 [THINK_STREAMING.md](THINK_STREAMING.md)）
- [x] Phase 3：iPad / Vision Pro 布局：`horizontalSizeClass == .regular` 时左右分栏（左 Files、右 Chat），Settings 为 toolbar 按钮
- [x] iPad 预览优化：sheet 使用 `.presentationDetents([.large])` 大尺寸；Files 中点击文件弹 sheet（左栏窄不宜内联）
- [x] 测试覆盖：SSE 事件结构、session 过滤、PathNormalizer、路径规范化
- [x] iPad 消息流密度优化：tool/patch/permission 卡片在 iPad 三列网格横向填充；text part 仍整行显示
- [x] PathNormalizer 加固：percent-encoding 解码、file:// 兼容、最基本的 ../ 防御、绝对路径 → workspace 相对路径解析（修复 tool read 预览空内容类问题）
- [x] 文档同步：PRD/RFC 补充 iPad 三列网格说明；lessons.md 增加“PRD/RFC→code→test→build/test”的工作流
- [x] code_review.md 更新：补齐全 repo review 新发现项 + Security Review（准备推 GitHub 前检查）
- [x] 语音输入（AI Builder Speech Recognition）：录音（mic 权限）→ 调用 `/v1/audio/transcriptions` → 文本追加到输入框
- [x] iPad 外接键盘：回车发送（submitLabel/send + keyboardShortcut Return）
- [x] 网络安全边界：WAN 禁止 http://（强制 https://）；Settings 展示 scheme 与提示
- [x] 3.1 apply_patch 显示为 "patch"（ToolPartView.toolDisplayName）
- [x] 3.2 Settings HTTP 时 scheme 橙色 + info 图标
- [x] 1.1 AppState 详细规划（code_review 三阶段细化）
- [x] Bug: tool layout — thinking 并入最后一条 MessageRowView，不另起行打断网格
- [x] Bug: Diff/文件预览 — 横向滚动、minWidth 填满、textSelection
- [x] code_review 2.4 更新：按方案 B 暂不强调
- [x] 最近 commit/push：9b4b842（tool layout、Diff 预览、Settings HTTP info、1.1 规划、2.4）

## 待办

- [x] **Code Review 1.1**：AppState 拆分（SessionStore/MessageStore/FileStore/TodoStore，保持对外 API 不变）
- [x] **Code Review 1.2**：SSE 调研（API 单行 data 已满足，RFC 规划，加 Accept/Cache-Control 头）
- [x] **Code Review 1.3**：SSE message.updated 按 sessionID 过滤
- [x] **Code Review 1.4**：PathNormalizer 统一路径规范化（Utils/PathNormalizer.swift）
- [ ] **Phase 4：iPad / Vision Pro 布局优化**：可考虑（可选）从 Chat 点击文件时在左栏展示而非 sheet（当前 Chat 与 Files 均弹 sheet）

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

6. **术语澄清**：Think streaming 实指 Think（ReasoningPartView）的展开/收起行为，非 Tool。

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
