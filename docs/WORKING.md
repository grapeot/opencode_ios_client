# OpenCode iOS Client — Working Document

> 实现过程中的进度、问题与决策记录

## 当前状态

- **最后更新**：2026-05-01
- **分支**：`visionos`（from master）
- **编译**：✅ `OpenCodeClientVision` xrsimulator build 通过
- **测试**：✅ iOS build/test 回归验证通过
- **Phase**：visionOS UI ergonomics、forked package migration 与 layered app icon

## 默认工作流约定

### "用最新的 code 编译" 的默认语义

在这个项目里，这句话默认**不是**指直接拿远端最新代码原地编译。

默认含义是：

1. 进入 `adhoc_jobs/opencode_ios_client/opencode-official`
2. `fetch origin`，获取最新 `origin/dev`
3. 在**保留当前本地提交**的前提下，把当前本地集成分支 rebase 到最新 `origin/dev` 之上
4. 用 rebase 后的 server 代码继续编译、测试、部署 iOS client / server 联调环境

这条约定的目标是固定一种工作语义：**最新代码 = 最新上游 `origin/dev` + 当前本地补丁栈**。

这里的“本地提交”专指：当前分支上**已经提交**、但还没有集成到最新 `origin/dev` 之上的那些提交；**不包含** working tree 里的未提交改动。

只有当需求明确说明“不要本地提交，只编译纯上游最新代码”时，才跳过 rebase，直接基于干净的 `origin/dev` 工作。

### 为什么这样约定

- `opencode-official` 当前可验证的主线是 `dev` / `origin/dev`，不是 `master`
- 本地通常会有一组尚未上游化的 patch；直接编译纯上游会丢掉这些行为差异
- 先 rebase 再编译，能更早暴露上游变更与本地 patch 的冲突，而不是把问题留到更后面

### 执行边界

- 这是一个**保留本地提交**的集成工作流，不是“强制重置到远端”
- 如果 rebase 出现冲突或失败，默认先暂停并确认处理方式，不继续进入编译/部署阶段
- 如果只是做只读调研、API 对照或回归定位，不默认触发这条工作流

### Success criteria

- 成功标准不只是“编译产出了 binary”，还包括**运行路径正确**
- 在 `knowledge_working` 下启动 OpenCode 时，所执行的必须是这次 workflow 产出的最新 binary，而不是之前遗留在磁盘上的旧 binary
- 对当前工作流来说，只有当下面这类命令实际启动的是刚刚 rebase + build 得到的 binary，才算完成闭环验证：

```bash
OPENCODE_DB_PATH="$HOME/.local/share/opencode/opencode.db" \
OPENCODE_SERVER_PASSWORD="restart_Web@" \
/Users/grapeot/co/knowledge_working/adhoc_jobs/opencode_ios_client/opencode-official/packages/opencode/dist/opencode-darwin-arm64/bin/opencode web --hostname 0.0.0.0
```

- 如果该命令仍然指向旧构建产物，或无法证明它对应的是本轮 rebase 后的新 binary，则这次“用最新的 code 编译”不能算完成

### 运行验证边界

- 如果用户当前正在活跃使用 OpenCode，尤其已经有一个 `4096` 端口上的 server 在服务中，**不要**为了验证新 binary 去 kill、restart、或接管这个 live process
- 这种场景下，默认跳过会干扰现有使用的 runtime 验证步骤
- 如果仍然需要运行时验证，应使用单独的临时进程/临时端口完成，并且只管理自己新启动的那条验证进程，不触碰用户现有的 `4096` 进程

## 进行中

- [ ] **PR 合并** — `design-redesign` 分支所有改动已完成并通过测试，待创建 PR 合并到 master
- [ ] **Model 列表更新 — 删除 Opus/Sonnet，添加 DeepSeek（2026-04-23）**：删除 `anthropic/claude-opus-4-6` 和 `anthropic/claude-sonnet-4-6`，新增 `deepseek/deepseek-v4-pro`

## 已完成（近期）

- [x] **visionOS layered app icon（2026-05-01）**：
  - [x] 基于现有 `OpenCodeClient/Assets.xcassets/AppIcon.appiconset/AppIcon.png` 生成 visionOS 三层 icon：background / middle / foreground
  - [x] 最终采用程序按原图颜色分层，而不是直接采用模型输出透明层；这样 composite preview 与原图逐像素一致，避免透明背景被模型画成棋盘格、或绿幕抠图留下彩边
  - [x] 新增 `OpenCodeClientVisionAssets.xcassets/AppIcon.solidimagestack`，并只加入 `OpenCodeClientVision` target 的 Resources；共享 `OpenCodeClient/Assets.xcassets` 继续只保留 iOS `AppIcon`
  - [x] visionOS app icon catalog 使用 Xcode 生成的 `.solidimagestack` / `.solidimagestacklayer` 结构；每层 `Content.imageset` 使用 `idiom: vision`、`scale: 2x`，并指向 1024×1024 PNG
  - [x] `OpenCodeClient` 与 `OpenCodeClientVision` target 都使用 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`；由于两个 target 引用不同 asset catalog，iOS 使用 flat `AppIcon.appiconset`，visionOS 使用 `AppIcon.solidimagestack`
  - [x] 验证：`OpenCodeClient` iphonesimulator build 通过；`OpenCodeClientVision` xrsimulator build 通过；`assetutil --info` 确认编译后的 `Assets.car` 里存在 `SolidImageStack`，名字为 `AppIcon`，三层分别为 Back / Middle / Front

- [x] **visionOS 输入区交互尺寸与窗口默认大小（2026-05-01）**：
  - [x] 录音按钮 active 状态改为红色 icon + 红色 tint 背景/描边，避免 visionOS glass/material compositing 把原来的纯红背景洗成白色
  - [x] composer 右侧 mic / send / stop 三个 action buttons 在 visionOS 上从 32pt 放大到 48pt，并把垂直间距放宽到 12pt，降低 gaze interaction 难度；iPhone/iPad 保持原 32pt 尺寸
  - [x] stop 按钮在 AI busy 时改为与录音 active 态一致的红色 icon + tint 背景/描边，而不是纯红实心背景；这样在 visionOS glass/material 下更容易保持红色语义
  - [x] composer 底部容器 padding 改为 design token：visionOS 使用 32pt horizontal / 20pt vertical，iPhone/iPad 保持 16pt / 10pt，避免右下角按钮贴近 Apple Vision Pro window resize handle
  - [x] composer 输入框高度改为跨平台 token：visionOS 48–160pt，iPhone/iPad 32–100pt，避免大窗口里输入区仍按手机高度限制
  - [x] tool-call header 右侧 open-file 图标在 visionOS 上放大为 44pt hit target + `title3` icon，方便用眼控/手势打开 patch/edit 详情文件；iPhone/iPad 保持 24pt 紧凑尺寸
  - [x] visionOS split view 左侧 Workspace / Sessions sidebar 宽度调到 iPad 默认的 130%（`1.3 / 6.0`），最小宽度同步从 10% 提到 13%
  - [x] `OpenCodeClientVision` 默认窗口尺寸设为 2304×1080，约为系统默认宽度的 180%、高度的 150%，减少首次打开后手动拉大窗口的需求
  - [x] 后续根据实机观感把默认窗口调窄并略增高：宽度从 2304 降到 1382（约 60%），高度从 1080 增到 1188（约 110%）；再把宽度微调到 1500，高度保持 1188
  - [x] 后续继续把默认窗口宽度调到 2000，高度保持 1188
  - [x] 验证：`OpenCodeClientVision` xrsimulator build 通过；`OpenCodeClient` iphonesimulator build 通过

- [x] **visionOS 原生 target 基线（2026-04-30）**：
  - [x] 新增 `OpenCodeClientVision` application target，SDK 指向 `xros`，device family 设为 Vision，源码复用现有 `OpenCodeClient/` synchronized root group
  - [x] 保留 iPad 三栏 `NavigationSplitView` 作为 visionOS 的主 layout；不引入 tab-based 顶层导航
  - [x] visionOS 首版不支持 SSH tunnel：`Settings` 中隐藏 SSH Tunnel section，启动/前后台恢复流程不再尝试自动连接 tunnel；底层 `SSHTunnelManager` 在 visionOS 使用 stub，避免链接 Citadel / swift-nio-ssh
  - [x] visionOS 首版先用系统 `AttributedString(markdown:)` 验证 target 能独立编译；后续已切换到本地 patched MarkdownUI / NetworkImage
  - [x] 兼容 visionOS API：将 `scrollDismissesKeyboard(.immediately)` 包装为平台条件修饰符，visionOS 下跳过该 unavailable modifier
  - [x] 验证：`xcodebuild -project "OpenCodeClient.xcodeproj" -target "OpenCodeClientVision" -configuration Debug -sdk xrsimulator CODE_SIGNING_ALLOWED=NO build` 通过
  - [x] 后续验证：本地 patched MarkdownUI / NetworkImage 已能让 visionOS target 直接使用 `MarkdownUI.Markdown`

- [x] **MarkdownUI / NetworkImage visionOS package patch（2026-05-01）**：
  - [x] 最初新增 `third_party/swift-markdown-ui`（2.4.1）和 `third_party/NetworkImage`（6.0.1）本地 package source，用 Xcode local package reference 替代远端 MarkdownUI reference
  - [x] 后续迁移到 GitHub forks：`grapeot/swift-markdown-ui` tag `2.4.1-visionos.1` 和 `grapeot/NetworkImage` tag `6.0.1-visionos.1`，Xcode project 使用 exact version 引用，不再 vendor `third_party/`
  - [x] `swift-markdown-ui/Package.swift` 升到 Swift tools 5.9，声明 `.visionOS(.v1)`，并把 `NetworkImage` 指向 `https://github.com/grapeot/NetworkImage` exact `6.0.1-visionos.1`
  - [x] `NetworkImage/Package.swift` 升到 Swift tools 5.9，声明 `.visionOS(.v1)`；`NetworkImage.swift` 增加 visionOS availability，并用 1x1 transparent `CGImage` 作为空图占位，避开 UIKit/AppKit-only empty image initializer
  - [x] `MessageRowView` 与 `FileContentView` 在 visionOS 上恢复使用 `MarkdownUI.Markdown`，删除临时 native Markdown fallback
  - [x] 打开 visionOS Markdown embedded image 支持：`OpenCodeClientVision` 显式链接 `NetworkImage`，`FileContentView` 与 `MessageRowView` 在 visionOS 上复用 iOS 的 `WorkspaceMarkdownImageProvider` / `MarkdownImageResolver` 路径
  - [x] visionOS 上点击 Markdown embedded image 时改为打开独立 Image Preview window；iPhone/iPad 继续使用原有 sheet 预览
  - [x] 验证：`xcodebuild -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClientVision" -configuration Debug -sdk xrsimulator CODE_SIGNING_ALLOWED=NO build` 通过
  - [x] 验证：`xcodebuild -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` 通过
  - [x] 后续验证：打开 visionOS Markdown image gate 后，`OpenCodeClientVision` xrsimulator build 与 `OpenCodeClient` iphonesimulator build 均通过

- [x] **默认模型切换到 GPT-5.5（2026-04-28）**：
  - [x] 默认发送模型从 DeepSeek 切换为 `openai/gpt-5.5`
  - [x] GPT 预设显示名和 model ID 从 `GPT-5.4` / `gpt-5.4` 升级为 `GPT-5.5` / `gpt-5.5`
  - [x] 为已保存旧 `openai/gpt-5.4` 选择的 session 增加兼容映射，避免模型 selector 回退
  - [x] 新增默认选择与旧 GPT 选择迁移测试

- [x] **Markdown 报告图片渲染修复（2026-04-15）**：
  - [x] 根因确认：Android 能显示报告内图片，不是 markdown 内容问题；Android 会先把相对图片路径解析成 `data:` URI 再渲染，而 iOS 聊天视图原来只做了路径解析，没有把能渲染 `data:` URL 的 image provider 接上
  - [x] `MessageRowView`：为聊天中的 `ResolvedMarkdownView` 补上 `WorkspaceMarkdownImageProvider`，让已经被 `MarkdownImageResolver` 转换好的 `data:` URI 真正显示出来
  - [x] `WorkspaceMarkdownImageProvider`：增加 `workspaceDirectory` 参与路径相对化，避免 markdown 图片在文件预览里带着绝对 workspace 前缀走错 `/file/content` API path
  - [x] `FileContentView`：将 `state.currentSession?.directory` 传入 `MarkdownPreviewView` / `WorkspaceMarkdownImageProvider`，让文件预览与聊天视图在 workspace 路径语义上保持一致
  - [x] 测试修正：`WorkspaceMarkdownImageProviderTests.decodesBase64DataURL()` 改为使用真实 1x1 PNG 的 base64，而不是无效的 `"hello"` payload；新增 absolute-workspace prefix stripping 覆盖
  - [x] 验证：`xcodebuild -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' build` 通过；同目标 `test` 通过
  - **Commit**: `5554fe9` — fix: render markdown report images on ios
  - **Commit**: `45044d4` — test: align markdown image provider data-url coverage

- [x] **视觉重设计 Phase 2 — Mic 按钮 + 色彩统一 + 交互修复（2026-04-01）**：
  - [x] Mic 按钮移至发送按钮上方 VStack，添加圆角描边（1.5pt brand blue）使其可识别为可点击按钮
  - [x] Brand primary 从深蓝 `(0.15, 0.25, 0.55)` 改为系统蓝 `(0.0, 0.478, 1.0)`，与 iOS accent 统一
  - [x] 全局 7 处 `.accentColor` 替换为 `DesignColors.Brand.primary`（ChatToolbarView 4 处、SessionListView 1 处、ContextUsageView 1 处、ToolPartView 1 处）
  - [x] Transcribing 状态恢复可见（`surfaceLight`/`surfaceDark` 背景替代 `Color.clear`）
  - [x] 恢复 AI 工作中仍可发送消息（send 按钮始终可见，stop/abort 在下方同时显示）
  - **Commit**: `122f29c` — fix: mic button to right side with border, unify brand color to system blue
  - **Commit**: `4bf2e12` — fix: restore transcribing visual feedback and send-while-busy

- [x] **Design Token 测试覆盖（2026-04-01）**：
  - [x] 新增 `DesignTokensTests`（9 个测试）：spacing 精确值 + 单调递增、corner radii 正向排序、brand primary/gold RGB 范围、opacity 合法范围 + 暗色 > 亮色、animation slots 存在性、semantic 色互不相同
  - [x] 所有测试通过，`xcodebuild test` green

- [x] **视觉重设计 Phase 1（2026-04-01）**：
  - [x] `docs/design.md` — 11 个改进方向的完整设计文档
  - [x] `DesignTokens.swift` — 集中设计系统（Brand 主色深蓝+金黄、语义色、暖灰中性色、七档排版、间距、圆角、动画预设、阴影）
  - [x] 17 个视图文件重设计：MessageRowView、ChatTabView、ChatToolbarView、ToolPartView、PatchPartView、PermissionCardView、QuestionCardView、SessionListView、ContextUsageView、StreamingReasoningView、TodoListInlineView、FileTreeView、FileContentView、SettingsTabView、SplitSidebarView、ContentView、L10n
  - [x] 消息方向 B（无气泡 + 4pt 左侧色条），AI 消息纯文字无容器
  - [x] Composer 重设计（mic 内嵌左侧、send/stop 右侧方形按钮、输入框无描边）
  - [x] Toolbar model+agent 合并为配置 sheet，Rename 降为 .secondary
  - [x] 卡片语言统一：信息卡片去描边、操作卡片左侧色条
  - [x] Context ring 缩小 18pt + ≥85% 脉冲动画
  - [x] 所有新增 L10n key（configureTitle/Model/Agent/NoAgents）含中英翻译
  - [x] Gemini subagent 误操作修复（PathNormalizer、APIConstants/StorageKeys 恢复、hardcoded strings）
  - **Commit**: `b6ed2ac` — feat: redesign visual design system — design tokens, card language, composer, toolbar
  - **尚未实现的进阶项**（P1: session 摘要预览、子 session 连接线、session 切换淡入淡出、permission 滑入动画、消息出现动画；P2: tool 卡片 spring 展开、Logo 空状态呼吸动画、深色 Logo 资源）

- [x] **避免 session 切换时在 view update 内同步改状态（2026-03-30）**：
  - [x] 将 `ChatTabView` 中响应 `currentSessionID` 变化的草稿同步与滚动状态重置改为 `Task { @MainActor in }`
  - [x] 降低运行时 `Modifying state during view update` 告警概率，不改变现有 session 切换行为

- [x] **GLM-5.1 预设切回 GLM-5-turbo（2026-03-30）**：
  - [x] 将模型预设显示名从 `GLM-5.1` 更新为 `GLM-5-turbo`
  - [x] 将底层 model ID 从 `glm-5.1` 更新为 `glm-5-turbo`
  - [x] 为已保存旧 `glm-5.1` 选择的 session 增加兼容映射，避免 selector 回退到其他模型

- [x] **Chat Composer 视觉紧凑化与 Return 键行为调整（2026-03-28）**：
  - [x] 视觉：将 composer 最小高度从 44pt 继续压至 32pt，并将输入框容器/底部栏的垂直 padding 收紧到 5pt/6pt，使输入区高度更接近右侧圆形按钮，不再浪费底部空间
  - [x] 行为：修改 `ChatComposerTextView` 使 Return 键（含外接键盘 Enter）始终插入换行而非发送，并将键盘 Return 键类型从 `.send` 改回 `.default`
  - [x] 安全：保留 IME marked text 组合态安全，确保输入法确认操作不触发非预期行为；发送仅通过右侧圆形箭头按钮触发
  - [x] 测试/文档：更新 `ChatComposerKeyAction` 单元测试以匹配新行为，并同步更新 README 关于 iPad 键盘行为的说明

- [x] **iPad 中文输入法 + 物理键盘 Enter/Shift+Enter 提前发送修复（2026-03-28）**：
  - [x] 根因：Chat composer 使用 `TextField(axis: .vertical)` 的 `.onSubmit`，并额外挂了发送按钮的 `.keyboardShortcut(.return)`；在 iPad 外接键盘场景下，这两条 Return 路径会在中文输入法仍处于 marked text/composition 时抢先触发发送
  - [x] 修复：将 chat 输入框替换为一个局部 `UITextView` bridge，在 delegate 中按 `markedTextRange` 区分 IME 组合态；普通 `Enter` 发送，`Shift+Enter` 插入换行，并移除裸 `Return` keyboard shortcut
  - [x] 测试/文档：新增 composer key decision 单测，更新 chat 输入框 UI smoke 为 `chat-input` accessibility identifier，并在 README 记录 iPad 外接键盘的 Enter/Shift+Enter 语义

- [x] **iPad 新建 session 后 sidebar 重复 entry 修复（2026-03-28）**：
  - [x] 根因：`createSession()` / `forkSession()` 的 optimistic `sessions.insert(..., at: 0)` 与 SSE `session.updated` 的写入路径都能把同一个 `session.id` 再塞进本地 `sessions`；iPad sidebar 常驻可见，所以重复 row 和双 selected 会立刻暴露；切到别的 session 后 `refreshSessions()` 用服务端 canonical 列表整体覆盖，本地重复随之消失
  - [x] 修复：在 `AppState` 增加按 `session.id` 去重的 `upsertSession()` helper，并统一用于 `createSession()`、`forkSession()`、`session.updated`，确保本地 session 状态始终满足单 ID 唯一
  - [x] 测试：新增 create/fork duplicate collapse 回归测试，以及 `session.updated` 收敛重复 session 的状态流测试；验证 `xcodebuild build -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'generic/platform=iOS Simulator'` 与 `xcodebuild test -project "OpenCodeClient.xcodeproj" -scheme "OpenCodeClient" -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4'` 全部通过

- [x] **GLM-5-Turbo 预设切换到 GLM-5.1（2026-03-27）**：
  - [x] 将模型预设显示名从 `GLM-5-Turbo` 更新为 `GLM-5.1`
  - [x] 将底层 model ID 从 `glm-5-turbo` 更新为 `glm-5.1`

- [x] **GLM-5 预设切换到 GLM-5-Turbo（2026-03-20）**：
  - [x] 将模型预设显示名从 `GLM-5` 更新为 `GLM-5-Turbo`
  - [x] 将底层 model ID 从 `glm-5` 更新为 `glm-5-turbo`

- [x] **默认模型切换到 GPT-5.4（2026-03-19）**：
  - [x] 默认发送模型从 `zai-coding-plan/glm-5` 切换为 `openai/gpt-5.4`
  - [x] 新会话和未保存过模型选择的默认发送路径直接落到 GPT-5.4

- [x] **oh-my-opencode 默认 agent 与 Gemini model ID 修正（2026-03-17）**：
  - [x] 全局 `oh-my-opencode.json` 默认 agent 从 GLM-5 切换为 sisyphus ultraworker（Claude Opus 4.6）
  - [x] Gemini model ID 修正：`google/gemini-3-flash` -> `google/gemini-3-flash-preview`，`google/gemini-3-pro` -> `google/gemini-3.1-pro-preview`

- [x] **iPhone 左缘右滑打开 Session List（2026-03-19）**：
  - [x] 实现：`ChatTabView` 左侧新增窄透明 edge target，仅 compact width 启用；从左边缘向右拖拽满足阈值时走与 toolbar 相同的 `showSessionList = true`
  - [x] 约束：要求起点贴左边缘、横向位移足够、纵向漂移有限，避免把普通纵向滚动误判成打开 session list
  - [x] 测试：新增 `SessionListEdgeSwipeBehaviorTests`，覆盖合法左缘右滑、非左缘起手、以及过度纵向拖拽三种情况

- [x] **Model selection 切换 session 后显示错误模型修复（2026-03-14）**：
  - [x] 根因：`inferAndStoreModelForCurrentSessionIfMissing()` 有 `guard selectedModelIDBySessionID[sessionID] == nil` 前置条件，当 persistence 有旧值时直接跳过推断，导致 `selectedModelIndex` 保留上一个 session 的值
  - [x] 修复：重命名为 `syncModelFromMessageHistory()`，移除 persistence 非空即跳过的 guard，每次加载完 messages 后都从消息历史推断实际模型并更新选择；`applySavedModelForCurrentSession()` 保留为同步快速路径

- [x] **Context ring 常驻可见 + AI 处理中保持数值（2026-03-14）**：
  - [x] 根因 1：`ChatTabView` 在 `state.isBusy` 时向 `.navigationBarTrailing` 注入 `ProgressView`，视觉上遮盖 ring → 删除该 ProgressView block
  - [x] 根因 2：AI 处理中服务器创建新 assistant 消息带 `tokens: {total: 0}`，旧过滤 `tokens != nil` 命中该空消息导致 ring 显示 0% → 改为 `tokens != nil && tokens.total > 0`，跳过空 token 消息
  - [x] 缓存机制：`AppState._cachedContextUsage`（`@ObservationIgnored`）缓存最后一次有效 snapshot；messages 加载中/provider config 缺失时返回缓存值（同 session 限定）；切换 session 时清缓存

- [x] **语音转写 partial transcript 实时展示（2026-03-11）**：
  - [x] AIBuildersAudioClient：`transcribe` 新增可选 `onPartialTranscript` 回调，`streamPCMOverRealtimeWebSocket` 收到 `transcript_delta` 时累积并回调
  - [x] AppState.transcribeAudio：透传 onPartialTranscript
  - [x] ChatTabView：转写过程中将 partial 实时写入输入框，完成后用 final 替换；失败时恢复 prefix

- [x] **Markdown 大文件/长行崩溃修复（2026-03-11）**：
  - [x] 根因：MarkdownUI 对超长单行（如 transcript 段落 3000+ 字符）或大文件会 freeze/crash（GH #426、#396）
  - [x] 修复：FileContentView 在渲染前检测 `maxLineLength > 1500` 或 `totalLength > 60KB`，满足时直接用 RawTextView 跳过 MarkdownUI
  - [x] MarkdownPreviewView 内保留二次 fallback；loadContent 与 onAppear 保留调试日志

- [x] **Realtime Speech 语音转写修复（2026-03-11）**：
  - [x] 根因 1：API URL 构造错误——`URL(string: "/v1/...", relativeTo: base)` 会替换 base 的 path，导致 `https://space.ai-builders.com/backend` 请求到 `/v1/...` 而非 `/backend/v1/...`
  - [x] 修复：`buildAPIURL` 确保 base path 以 `/` 结尾，使相对路径正确追加；session 创建、testConnection 均改用该 helper
  - [x] 根因 2：m4a 转 PCM 失败——`AVAudioConverter` 对 AAC/m4a 有已知问题，抛出 `nilError`
  - [x] 修复：改用 `ExtAudioFile` API 读取并转换，直接输出 24kHz 16-bit mono PCM
  - [x] 新增 `buildAPIURLPreservesMountPath`、`buildAPIURLWithoutMountPath` 单元测试
  - [x] 增加 SpeechProfile 调试日志（session POST url、ws_url、websocket connect、各步骤失败详情）

- [x] **Session 树状层级视图（2026-03-03）**：
  - [x] 背景：agent 派出 background sub-agent 时会创建子 session（`Session.parentID` 指向父 session），此前所有 session 平级显示导致列表 cluttered
  - [x] 实现：`SessionNode` 树结构 + `AppState.buildSessionTree(from:)` 静态方法，按 `parentID` 递归构建层级；孤儿 session（parentID 指向不存在的 session）自动提升为根节点
  - [x] UI：子 session 缩进（depth × 24pt）、字号缩小（`.subheadline`）、颜色变淡（`.secondary`）；父 session 左侧显示 chevron 折叠/展开按钮
  - [x] `expandedSessionIDs: Set<String>` 跟踪展开状态（默认收起），`toggleSessionExpanded()` 切换
  - [x] iPhone（`SessionListView`）和 iPad（`SplitSidebarView.SessionsSidebarList`）同步更新为树状递归渲染
  - [x] 单元测试：7 个测试覆盖层级构建、孤儿处理、排序、多级嵌套、空输入、归档过滤、折叠状态切换

- [x] **Session 创建仅限 Server default（2026-02-25）**：
  - [x] 根因：`POST /session` 不支持传 directory，新 session 始终落在 server 的 current project；iOS Project 选择器只过滤列表，不改变创建目标
  - [x] 实现：仅 Server default 时提供创建按钮；选具体 project 时新建按钮置灰 + info 图标提示去服务器端切换
  - [x] `canCreateSession`、`chatCreateDisabledHint`；ChatToolbarView、SessionListView 置灰 + info
  - [x] 文档：lessons §16、RFC §4.3.1、PRD §4.4.3
- [x] **Project 选择功能（2026-02-25 完成）**：
  - [x] PRD/RFC 更新：添加 Project (Workspace) 设计
  - [x] 实现 `Project` 数据模型、`APIClient.projects()`、`sessions(directory:limit:)`
  - [x] 更新 `AppState`：projects、selectedProjectWorktree、customProjectPath、effectiveProjectDirectory
  - [x] Settings UI：Project Picker（Server default / 项目列表 / Custom path）
  - [x] 单元测试：Project 解码、effectiveProjectDirectory 逻辑；修复 SessionDeletionSelectionTests.makeSession 缺 archived 参数
  - [x] 解决「手机端只能看两周前 sessions」根因：Web 与 iOS 默认看的 project 不同，现支持按 project 过滤
- [x] **Agent 选择功能（2026-02-21 完成）**：
  - [x] RFC/PRD 更新：添加 Agent 数据模型、API、UI 设计（v0.2 / RFC-002）
  - [x] 实现 `AgentInfo` 数据模型（含 mode 过滤：primary/all 显示，subagent 隐藏）
  - [x] 实现 `APIClient.agents()` 方法
  - [x] 更新 `AppState`：添加 agents 列表（prefill 5 个默认 agent）、selectedAgentIndex、loadAgents()
  - [x] 更新模型列表：GLM-5（默认）/ Opus 4.6 / Sonnet 4.6 / GPT-5.3 Codex / GPT-5.2 / Gemini 3.1 Pro / Gemini 3 Flash
  - [x] 更新 `ChatToolbarView`：chip 横向滚动改为下拉列表（Model + Agent）
  - [x] 更新 `promptAsync`：传递选中的 agent
  - [x] 单元测试：Agent API 解码 + mode 过滤测试
  - [x] OpenCode-Builder 设为默认 agent
- [x] **渲染性能优化 1/3（行级去全局状态订阅）**：`MessageRowView/ToolPartView/PatchPartView` 移除 `@Bindable AppState` 直连，改为最小必要数据 + 文件打开回调，降低长会话下无关状态变更触发的整页重算
- [x] **渲染性能优化 2/3（Scroll Anchor 轻量化）**：`scrollAnchor` 从“全量拼接所有 message/streaming 字符串”改为基于 `messageCount + lastMessageSignature + streaming chars` 的 O(1)/小常量签名，避免长会话下每次状态变化都全量遍历
- [x] **渲染性能优化 3/3（Markdown 快速路径）**：对纯文本消息走 `Text` 渲染，仅在检测到 Markdown 语法特征时使用 `MarkdownUI`，降低长会话中大量普通文本消息的解析与布局开销
- [x] **消息分段加载（3 轮对话）**：默认仅拉取最近 3 轮（6 条）message，聊天页顶部显示“下拉加载更多历史消息”，每次下拉再扩展 3 轮并重新拉取
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
- [x] **iPhone 发热明显热点修复（滚动）**：移除 running activity 每秒计时对 `scrollAnchor` 的影响，避免每秒触发 `scrollTo("bottom")` 动画
- [x] **全量 Code Review 文档重写（2026-02-13）**：删除并重写 `docs/code_review.md`，聚焦架构/性能/安全的明显问题与优先级
- [x] **SSH TOFU 安全基线**：替换 `acceptAnything`，首次连接信任 host key，后续强校验并支持重置信任主机
- [x] **SSE 主通道收敛**：移除 busy 常驻轮询，改为 SSE 重连后一次性 bootstrap 同步（messages + permissions）
- [x] **AppState 重构（PermissionController）**：权限事件解析/回写与 pending 映射从 AppState 抽离，补行为测试
- [x] **AppState 重构（Iteration C - ActivityTracker）**：activity 状态推导/防抖/时长规则抽离，补行为测试
- [x] **Activity Row 提前 completed 修复**：当 session.status 变 idle 但仍有 running/pending tool 或 streaming 时保持 running，不提前停表
- [x] **SSH UX 完整化**：Settings 增加「Copy Public Key」「Reverse Tunnel Command + Copy」与灰字提示（启用 SSH 后需点上方 Test Connection）
- [x] **Session 快速切换竞态修复（全量拉取）**：对 `loadMessages/loadSessionDiff` 增加 requestedSessionID 校验，丢弃过期响应，避免 A→B→A 后被旧 B 结果覆盖
- [x] **Activity Row 提前 completed（二次）修复**：`running/completed` 判定改为“当前 turn + busy 状态优先”，不再依赖 `completedAt == nil`，避免仍在运行时误显示 completed
- [x] **SSH UX 修复**：默认 Server Address 改为 `127.0.0.1:4096`；开启 SSH 后配置变更自动重连；View Public Key 在 enabled 场景不再空白；`Set Server Address` CTA 改为显式蓝色按钮
- [x] **Settings 关闭按钮一致性**：sheet 右上角改为英文 `Close`，避免英文界面出现中文“关闭”
- [x] **Localization 规划**：新增 `docs/dev_localization.md`，给出 en/zh-Hans 双语落地路线与分批迁移计划
- [x] **SSH 前后台自动恢复修复**：进入后台时主动断开 SSH/SSE；回前台恢复时若健康检查失败，强制重建一次 SSH tunnel 再 refresh
- [x] **SSE 重连状态补偿**：SSE bootstrap 与 `server.connected` 事件时补拉 `/session/status`，避免仅补消息不补状态
- [x] **Busy 卡死/Abort 无效感修复**：poll 合并时对“缺失于 poll 结果但本地仍 busy/retry”的会话降级为 idle，并同步清理 streaming；abort 后立即补拉状态+消息
- [x] **Todo 渲染兼容性修复（OpenCode 升级）**：兼容 `TodoItem` 新旧字段（`status/priority/id` 与 legacy `completed`），并修复 tool state `metadata.todos`/`output(JSON)` 解析；`metadata.input` 非字符串时不再导致 todo 卡片空白
- [x] **SSH runtime crash 防护（NIO channel state）**：修复 `SSHTunnelManager` 中跨线程调用 channel/context close 的并发问题（统一切回 NIO eventLoop 执行），避免 `Sent channel window adjust on channel in invalid state` 触发 fatal
- [x] **SSH Public Key 交互补强（二次）**：`View Public Key` 改为始终走 `generateOrGetPublicKey()`（不再优先读可能为空的缓存值），并将 `Copy Public Key` + `View Public Key` 合并为同一行按钮，减少 Settings 区域占用
- [x] **Tailscale / Server Address UX（2026-03-01）**：ATS 例外为 `ts.net` 添加 `NSIncludesSubdomains`；`correctMalformedServerURL` 修正 `host://host:port` 畸形格式；`ensureServerURLHasScheme` 无 http/https 时自动补 `http://`；修正时机改为 lose focus（`@FocusState` + `onChange`），避免每字符改写；Server Address 键盘 `submitLabel(.done)` 显示 Done

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
- [x] **Session 操作按钮顺序调整**：Chat 顶部 toolbar 左侧按钮顺序改为 Session 列表 → 重命名 → Compact → 新建 Session
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
- [x] **模型替换（OpenAI）**：GPT-5.2 替换为 GPT-5.3 Codex Spark（短名 `Spark`），并将 GPT-5.3 Codex 的 iPhone 短名改为 `GPT`
- [ ] **iPhone 发热排查与优化（暂缓）**：按当前优先级先暂停，后续再做 Instruments 复核与进一步优化
- [x] **Activity Row 逐 turn 保留校验（代码审查）**：已完成一轮代码级检查（逐 turn completed + 新 turn running 逻辑）；真机交互回归继续跟进
- [x] **全量 Codebase Review 文档重写**：删除旧 `docs/code_review.md` 并按当前代码重写，聚焦架构/可重构点/明显性能与安全问题
- [x] **SSE 主通道 + 一次性 bootstrap**：移除 busy 常驻轮询，保留重连/进入会话的一次全量补偿同步
- [x] **AppState Refactor Iteration B（PermissionController）**：先补测试，再抽离权限控制逻辑并保持外部接口不变

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

8. **SSH runtime fatal（NIO channel state）**：在 Settings 页滚动等场景偶发 `Sent channel window adjust on channel in invalid state`。定位为 `SSHTunnelManager` 中从 NW 回调线程直接调用 NIO `channel.close/context.close`，导致状态机竞态；修复为统一通过 `eventLoop.execute` 调度关闭。

9. **Simulator SpringBoard 崩溃（非 App 进程）**：最新崩溃日志显示 `Process: SpringBoard`，线程 `com.apple.xpc.activity.com.apple.SplashBoard` 触发 `dispatch_assert_queue`，属于模拟器系统组件异常，不是 `OpenCodeClient` 进程崩溃。结论：与当前业务代码改动无直接因果；排查优先使用“重启/抹除 simulator + 重新安装 app”路径。

10. **View Public Key 部分场景仍空白**：在 SSH enabled 但连接失败时，旧逻辑会先读本地缓存公钥，存在命中空字符串导致 sheet 为空的风险。修复：打开 sheet 时统一通过 `generateOrGetPublicKey()` 获取并做 trim + empty guard，异常时走错误弹窗。

11. **Tailscale MagicDNS 需 ATS 例外**：公司策略要求所有 host 使用 ATS/HTTPS，但 Tailscale MagicDNS（`*.ts.net`）解析的服务器通常跑 HTTP。修复：在 Info.plist 的 `NSAppTransportSecurity` 下添加 `NSExceptionDomains` → `ts.net` → `NSExceptionAllowsInsecureHTTPLoads: true` + **`NSIncludesSubdomains: true`**（关键：无此键则 `ts.net` 不匹配子域名如 `quantum.tail63c3c5.ts.net`），仅对 Tailscale 域名豁免 HTTPS 要求；其他域名仍受 ATS 约束。**Server Address 畸形格式**：iOS `.textContentType(.URL)` 或粘贴可能产生 `host://host:port` 格式，导致请求连到 80 端口、ECONNREFUSED。修复：`correctMalformedServerURL` 修正畸形；`ensureServerURLHasScheme` 无 http/https 时补 `http://`；修正时机为 **lose focus**（`@FocusState` + `onChange`），避免每字符改写；键盘 `submitLabel(.done)` 显示 Done。

## 决策记录

（记录实现过程中的技术决策）

## API 验证（localhost:4096）

- **GET /project**：✅ 返回 `Project[]`，含 id/worktree/vcs/time
- **GET /session?directory=&limit=**：✅ 按 worktree 过滤 sessions，limit 默认 100
- **GET /global/health**：✅ `{ healthy, version }`
- **GET /config/providers**：✅ 返回 `providers: array`（非 dict），每项含 `id`, `name`, `models: { modelID: ModelInfo }`。已修复 iOS 解析。
- **GET /agent**：✅ 返回 `[AgentInfo]`，含 name/description/mode/hidden/native 字段。iOS 端过滤 mode=subagent。
- **Import from Server**：依赖 config/providers，解析修复后应可正常导入。

当前模型预设（4 个）：
| 显示名称 | providerID | modelID |
|----------|------------|---------|
| GLM-5-turbo | `zai-coding-plan` | `glm-5-turbo` |
| GPT-5.4 | `openai` | `gpt-5.4` |
| GPT-5.3 Codex | `openai` | `gpt-5.3-codex` |
| DeepSeek | `deepseek` | `deepseek-v4-pro` |

Agent prefill（5 个，OpenCode-Builder 默认）：
- OpenCode-Builder (mode=all)
- Sisyphus (Ultraworker) (mode=primary)
- Hephaestus (Deep Agent) (mode=primary)
- Prometheus (Plan Builder) (mode=all)
- Atlas (Plan Executor) (mode=primary)

## Diff 问题

`GET /session/:id/diff` 实测返回 `[]`，即使 session 有 write 操作。GH #10920 等表明可能是 OpenCode server 端 session_diff 追踪问题，官方 web 客户端也可能遇到。暂不修复，待 server 端修复。
