# OpenCode iOS Client — Working Document

> 实现过程中的进度、问题与决策记录

## 当前状态

- **最后更新**：2026-02-13
- **Phase**：Phase 3 完成 + SSH Tunnel 基础设施
- **编译**：✅ 通过（iphonesimulator / generic destination）
- **测试**：✅ 所有测试通过（含 SSH tunnel 相关测试）

## 进行中

- [x] **SSH Tunnel 远程访问**（Citadel 集成完成）：
  - [x] SSHKeyManager：Ed25519 密钥生成/存储（Keychain）/公钥显示
  - [x] SSHTunnelManager：连接/断开/状态
  - [x] SSHTunnelConfig 数据模型
  - [x] Settings UI：SSH Tunnel 配置区域
  - [x] AppState 集成：SSH 连接状态
  - [x] 单元测试
  - [x] 添加 Citadel 依赖（SPM）
  - [x] 实现实际 SSH 连接逻辑（本地 127.0.0.1:4096 → SSH DirectTCPIP → VPS 127.0.0.1:remotePort）
  - [x] 修复 project deployment target（避免 UITests 无法在 simulator 上运行）
- [x] **UI 改进**（低优先级）：busy 状态用菊花代替圆形按钮
- [x] **权限请求交互修复**：支持 Allow once / Allow always / Reject，并确保 POST `/session/:id/permissions/:permissionID` 带 body `{"response":...}`
- [x] **SSH Public Key UI**：未连接时也应可生成/查看/复制公钥（避免 sheet 内按钮全灰）
- [x] **Permission 卡片位置**：permission 对话卡片应渲染在消息流底部（默认滚动到最底可见），并位于 activity/thinking 行的上方
- [x] **Activity 计时持久化**：计时从消息 `time.created/time.completed` 推导，避免重启 app/切换 session 后从 0 重置
- [x] **Activity/Busy 状态抖动**：session.status 轮询结果不覆盖近期 SSE；activity 文案更新做 2.5s debounce + debug log
- [x] **Per-turn Activity 行**：每个 user turn 的末尾保留 completed activity 行（显示耗时）；当前 in-progress turn 在底部显示 running activity 行

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
- [x] Phase 3：文件树（递归展开、按需加载）、文件内容（代码行号、Markdown Preview 切换）、Files Tab（仅 File Tree）+ 文件搜索
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
- [x] Phase 3：Think Streaming delta
- [x] Phase 3：iPad / Vision Pro 布局：`horizontalSizeClass == .regular` 时左右分栏（左 Files、右 Chat），Settings 为 toolbar 按钮
- [x] iPad / Vision Pro 布局升级：三栏（NavigationSplitView）— 左 Workspace（Files+Sessions）/ 中 Preview / 右 Chat
- [x] iPad 三栏列宽比例：Workspace ≈ 1/6；Preview ≈ 5/12；Chat ≈ 5/12
- [x] iPad 三栏可拖动：设置默认 ideal 宽度，但允许用户拖动分隔条调整
- [x] iPad 文件预览内联：左侧选择文件或 Chat tool/patch 点击文件时，更新中间 Preview（不再弹 sheet）
- [x] iPad Preview 刷新按钮：中间栏右上角提供手动刷新（重新加载文件内容）
- [x] 测试覆盖：SSE 事件结构、session 过滤、PathNormalizer、路径规范化
- [x] iPad 消息流密度优化：tool/patch/permission 卡片在 iPad 三列网格横向填充；text part 仍整行显示
- [x] PathNormalizer 加固：percent-encoding 解码、file:// 兼容、最基本的 ../ 防御、绝对路径 → workspace 相对路径解析（修复 tool read 预览空内容类问题）
- [x] 文档同步：PRD/RFC 补充 iPad 三列网格说明；lessons.md 增加“PRD/RFC→code→test→build/test”的工作流
- [x] Code review 已归档
- [x] 语音输入（AI Builder Speech Recognition）：录音（mic 权限）→ 调用 `/v1/audio/transcriptions` → 文本追加到输入框
- [x] iPad 外接键盘：回车发送（submitLabel/send + keyboardShortcut Return）
- [x] 网络安全边界：WAN 禁止 http://（强制 https://）；Settings 展示 scheme 与提示
- [x] 3.1 apply_patch 显示为 "patch"（ToolPartView.toolDisplayName）
- [x] 3.2 Settings HTTP 时 scheme 橙色 + info 图标
- [x] 1.1 AppState 详细规划
- [x] Bug: tool layout — thinking 并入最后一条 MessageRowView，不另起行打断网格
- [x] Bug: Diff/文件预览 — 横向滚动、minWidth 填满、textSelection
- [x] Bug: Markdown 源码视图宽度 — Markdown/Preview 切换后源码视图只占左半边导致提前换行（改用 RawTextView 让文本充满可用宽度）
- [x] Todo 2.4 按方案 B 暂不强调
- [x] 最近 commit/push：9b4b842（tool layout、Diff 预览、Settings HTTP info、1.1 规划、2.4）
- [x] **GLM-4.7 → GLM5**：模型更新为 `zai-coding-plan` / `glm-5`
- [x] **新增模型**：增加 `openai` / `gpt-5.3-codex-spark`（GPT-5.3 Codex Spark）
- [x] **iPhone 模型短名**：iPhone 顶栏模型 chip 显示 `GPT` / `Spark` / `Opus` / `GLM`，iPad 显示全称
- [x] **Tool 卡片颜色区分**：`todowrite` 使用绿色强调，其它 tool 使用主题色（accentColor），便于快速扫读
- [x] **Patch 卡片样式对齐**：与 tool 卡片一致的淡底色 + 细描边，信息更清晰
- [x] **卡片视觉一致性**：tool/patch/permission/user message 统一淡底色透明度（0.07）+ 细描边（0.14）风格
- [x] **Session title 自动更新**：监听 SSE `session.updated` 事件 + 发送后轮询刷新，无需手动重命名
- [x] **Thinking 打字机效果修复**：收到 `message.part.updated`（reasoning）时固定在消息列表底部显示 `StreamingReasoningView`，不再依赖 messages 已有 reasoning part
- [x] **录音前校验 AI Builder Token**：token 为空 / 正在测试 / 测试未通过时弹窗提示先去 Settings 配置
- [x] **Test Connection 转圈状态**：Settings AI Builder 连接测试时显示 "Testing..." + ProgressView
- [x] **AI Builder 测试状态可持久化**：Test Connection 成功后，OK 状态跨 App 重启保持；仅在 token/baseURL 变更时自动失效
- [x] **发送/录音按钮上下并排**：iPhone/iPad 均改为 VStack 布局，send 在上、mic 在下、abort（如有）在最下
- [x] **Session 列表按更新时间排序**：使用 `sortedSessions` 按 `time.updated` 降序排列
- [x] **Session 行时间显示按更新时间**：Session 列表的“xx 分钟前”改为 `time.updated`
- [x] **Session 列表去蓝色**：列表文本使用中性色（灰），当前 Session 用背景高亮
+- [x] **Session 操作按钮顺序调整**：Chat 顶部 toolbar 左侧按钮顺序改为 Session 列表 → 重命名 → Compact → 新建 Session
 - [x] **切换 Session 空白 bug 修复**：切换时先清空 messages/parts/streaming 状态再加载新 session 数据
- [x] **服务端错误信息展示**：assistant message 带 `error.data.message` 时在消息中以红色卡片显示
- [x] **iPad 侧边栏上下分区**：左侧改为上 Files（File Tree）下 Sessions（列表点击切换右侧 Chat Session）
- [x] **Workspace 左栏等高**：iPad Workspace 左栏 Files/Sessions 两块高度 1:1
- [x] **iPad Workspace 文件预览内联**：在 Workspace 左侧 File Tree 点文件，更新中间 Preview 栏
- [x] **todowrite 仅渲染 todo**：Tool 卡片不再显示 todowrite 的 raw JSON input/output，只保留渲染后的 todo 列表
- [x] **Context usage ring**：Chat 顶部模型与齿轮之间新增上下文占用环，点击弹出 token/cost 明细（无数据时灰色空环）
- [x] **Context provider config 加载修复**：`GET /config/providers` 解码兼容 array/dict 变体；点击 ring 时若未加载则自动触发加载，并在失败时显示错误信息
- [x] **Context sheet 默认大小优化**：iPad 打开即为 large（避免先小后逐步变大）
- [x] **输入草稿持久化**：按 sessionID 持久化未发送输入，切换 session 可恢复；发送成功后清空
- [x] **模型选择按 Session 记忆**：切换 session 时自动恢复该 session 上次选择的模型（避免全局覆盖）
- [x] **发送重复消息修复**：busy/polling 场景下去重 optimistic temp user message，避免 UI 显示两条
- [x] **Busy/Retry 会话轮询增强**：将 `retry` 与 `busy` 同等视为 busy；busy 时自动轮询刷新，退出 busy 自动停止
- [x] **Chat Activity 消息**：将“当前操作 + 耗时”渲染为消息流中的最后一条（按 session 记忆）；运行中每秒更新，结束后定格为 Completed 并保留到下一次运行；文案参考 web：reasoning 以 `**title**` 提取为 `Thinking - title`，tool 以类型映射到 “Searching/Making edits/Running…”
- [x] **loadMessages 解码兜底**：支持空 body/非数组 payload（`messages`/`data`/`result` 包裹、单对象）以避免轮询因解析失败中断
- [x] **Streaming 期间消息可见性**：轮询合并保留临时 user 消息与 streaming assistant draft（避免 busy 空列表时 UI 闪回/丢失）
- [x] **Chat 空状态优化**：无 session / busy(retry) / 空消息分别展示不同提示；scroll anchor 纳入 streaming delta 长度避免滚动不刷新

## 待办

- [x] **Code Review 1.1**：AppState 拆分（SessionStore/MessageStore/FileStore/TodoStore，保持对外 API 不变）
- [x] **Code Review 1.2**：SSE 调研（API 单行 data 已满足，RFC 规划，加 Accept/Cache-Control 头）
- [x] **Code Review 1.3**：SSE message.updated 按 sessionID 过滤
- [x] **Code Review 1.4**：PathNormalizer 统一路径规范化（Utils/PathNormalizer.swift）
- [ ] **Phase 4：iPad / Vision Pro 布局优化**：可考虑（可选）Preview 栏支持“固定/关闭当前文件”等更细粒度控制

### Code Review 改进（来自 code_review.md）

- [x] **4.2 Race Condition**：Session 切换添加 `sessionLoadingID` 防止快速切换时竞态
- [x] **3.2 Error Presentation**：统一错误处理模式
- [x] **3.3 Magic Numbers**：提取常量（列宽比例、动画时长等）
- [x] **3.4 Test Coverage**：添加 AppState 层面测试
- [x] **3.5 View Decomposition**：拆分 ChatTabView
- [x] **3.1 AppState Size**（部分完成 - 已提取 Store，完整 Coordinator 待定）：继续提取 Coordinator
- [x] **4.1 Memory Leaks**：SSE 连接 deinit 处理
- [x] **4.4 Default Server**：修改默认服务器配置

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

7. **轮询时 messages 解析噪声**：busy/retry 期间偶发 `The data couldn’t be read because it is missing`（空 body / payload 形态不稳定）。修复：APIClient 增加空 body guard + 多形态解码兜底；AppState 捕获 DecodingError 仅记录日志，避免把 polling 当作连接失败。

## 决策记录

（记录实现过程中的技术决策）

## API 验证（192.168.180.128:4096）

- **GET /global/health**：✅ `{ healthy, version }`
- **GET /config/providers**：✅ 返回 `providers: array`（非 dict），每项含 `id`, `name`, `models: { modelID: ModelInfo }`。已修复 iOS 解析。
- **Import from Server**：依赖 config/providers，解析修复后应可正常导入。

用户指定模型对应：
- OpenAI GPT-5.3 Codex：✅ `openai` / `gpt-5.3-codex`
- OpenAI GPT-5.2：✅ `openai` / `gpt-5.2`
- POE Opus Claude 4.6：✅ `poe` / `anthropic/claude-opus-4-6`
- z.ai coding plan GLM5：✅ `zai-coding-plan` / `glm-5`

## Diff 问题

`GET /session/:id/diff` 实测返回 `[]`，即使 session 有 write 操作。GH #10920 等表明可能是 OpenCode server 端 session_diff 追踪问题，官方 web 客户端也可能遇到。暂不修复，待 server 端修复。
