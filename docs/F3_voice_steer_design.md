# F3 · 语音 steer 与控制歧义消解设计调研与提案

本文回应设计方向给出的 F3 brief。brief 的作者没有代码访问权限，所有关于"当前行为"的描述都是从截图、README 和与维护者的对话里推断的假设。第一项工作是把这些假设拿到源码里核对，再基于真实情况设计控制模型。

brief 在开头就把框架立住了：这不是"把语音 UI 做漂亮"，当前 composer 难看是有原因的，那个原因才是真正的设计问题。核心是两个状态机（capture 和 run）纠缠在一起、某些控件语义重载。下面先报告 grounding 结果，再给出两个状态机的现状和碰撞点、控制模型的方案推荐，以及几个关键状态的草图。

调研基于对 app 内 composer/voice 相关文件和 VoiceFlowKit 包源码的阅读，关键结论都附了 `文件:行号` 出处。brief 里最关键的那条（语义重载的 "stop"）我亲自核对了源码。

---

## 一、对 brief §1–§3 假设的核对

这一轮 grounding 修正了 brief 几处实质假设，其中四处直接改变设计方向。

**修正一：ASR 不是 Apple 的 SFSpeechRecognizer，也不是端上 Whisper，而是服务端 OpenAI realtime API。** brief 把识别引擎、它的失败模式都当成待查项，这是对的。实际用的是 VoiceFlowKit 包（`github.com/grapeot/voiceflow`），底层走 OpenAI 的 `gpt-realtime` 模型，通过 WebSocket 把 PCM16/24kHz 音频实时推给服务端（`VoiceFlowConfig.swift:17-20`、`RealtimeTranscriptionClient.swift:85-86`）。这是纯服务端识别，端上不做任何识别。这条改变了后面好几个判断的前提。

**修正二：stall 的真实成因是一个 30 秒 finalize 超时，不是 Apple 的 1 分钟上限。** brief 推测可能是 Apple SFSpeechRecognizer 的限制或缓冲上限。真实机制是：用户停止录音后，客户端发 commit 给服务端、等服务端回 `session_stopped`（idle）事件来收尾；如果服务端 30 秒内没回，`waitForFinalizeResult()` 超时、把会话杀掉（`RealtimeTranscriptionClient.swift:337-338`、`427-436`）。长段落加多秒静默时服务端出字不够快，就卡在这个超时上。所以 stall 是"等服务端收尾等超时"，不是录音本身被截断。设计要针对的是这个机制：让用户在等待期看到"正在等服务端"的反馈，而不是面对静默。

**修正三：mid-recording 的 partial transcript 被刻意屏蔽，用户停止后才看到文字。** 这条直接推翻 brief §4b 的核心主张。brief 想"实时显示 partial transcript、标记低置信度词，让用户发送前抓住听错"。但 OpenCode 的 chat composer 明确屏蔽了录音过程中的 partial 事件（`ChatTabView+VoiceInput.swift:90-95` 的注释和 `.partialTranscript` case 直接 `continue`）。partial 只在停止后的 finalize 阶段才合并进输入框（`ChatTabView+VoiceInput.swift:158-167`）。换句话说，当前模型是 record → stop → transcribe → edit，不是边说边显示。"录音时实时校对"在这个架构下不成立。VoiceFlowKit 自己的 recorder app 会显示 live partial，但 OpenCode 的集成层刻意简化掉了。

**修正四：没有 pause/resume/append，brief 说的"暂停"实际是 abort 保存音频 + retry 重转。** brief 设想 stall 后 resume 续上同一段话、append 续录。源码里不存在这些。所谓的"暂停"是 `abortSpeechRecognition()`：停麦、不 finalize、把音频存到 `preservedSpeechAudio`（`ChatTabView+VoiceInput.swift:233-257`）。所谓的"replay/retry"是 `retryPreservedSpeechAudio()`：把同一段已存音频走 bulk（非流式）API 重转一遍（`ChatTabView+VoiceInput.swift:259-277`）。bulk 路径没有逐段落的 finalize 超时压力，所以是长段落 stall 的恢复手段。这是"对已录音频重转"，不是"续录"。续录在当前架构下要么扩展 VoiceFlowKit、要么重做合成流程。

**修正五（核心确认）：语义重载的 "stop" 是两个长得一模一样的 `stop.fill` 按钮。** brief 怀疑 "stop" 一个字管两件事，这点我亲自核对了源码，确认成立，而且比 brief 想的更具体：

- 左侧（mic 那一栏，`ChatTabView.swift:476-488`）：红色 `stop.fill`，仅当 `isTranscribing == true` 时出现，按下调 `abortSpeechRecognition()`，停的是转写。
- 右侧（send 那一栏，`ChatTabView.swift:558-572`）：红色 `stop.fill`，仅当 `state.isBusy == true` 时出现，按下调 `state.abortSession()`（`POST /session/{id}/abort`），停的是正在跑的 agent。

两个按钮同字形（`stop.fill`）、同颜色（红）、同样式，分处左右两栏。它们靠状态互斥（转写中 vs agent 运行中）保证不会同屏出现，所以不是物理位置撞车，但是视觉和语义撞车：用户看到一个红色 stop，得从周围状态推断"这个 stop 到底停什么"。在 iPhone 窄屏、或者紧张操作时，很容易按错。这就是 F3 要解决的核心。

**brief 判断对了、且不用动的部分：**

- 转写文本可编辑。语音和手打共用同一个 `inputText` 缓冲（`ChatTabView.swift:534-540` 的 `$inputText` 绑定），finalize 把转写结果合并进去，用户发送前能手改。edit-before-send 已经是现成的。
- IME commit 和硬件回车规则都已正确实现。`ChatComposerKeyAction`（`ChatComposerTextView.swift:11-15`）：有 marked text（中日文输入法 composing）时回车放行让输入法正常 commit；无 marked text 时裸回车插入换行；发送靠右侧 `arrow.up` 圆形按钮（`chat-send`）。send gate 在 `hasMarkedText` 时禁用发送。这些不要碰。
- 发送链路完整且 gate 正确：`sendCurrentInput()` → `sendMessage()` → `promptAsync()`（`POST /session/{id}/prompt_async`，带 model 和 agent）。这条不用改。
- model picker 不在拥挤的 composer 区。它在顶部 toolbar 右侧（`ChatToolbarView.swift:93-109`），是个 modal sheet，per-session（`selectedModelIDBySessionID`），中途切换不打断转写或草稿（`AppState+Models.swift:10-16`）。brief 担心的"model 挤在 capture/run 区"不成立。它离 composer 远，切换是"够到顶部、点开、选、关闭"的多步 modal，谈不上拥挤，但确实和输入流断开。

---

## 二、两个状态机的现状与碰撞点

brief 说得对：composer 上确实跑着两个独立状态机。下面把它们按代码现状画出来，标出碰撞点。

### Capture 状态机（采集）

线性流，无暂停/续录分支：

```
IDLE ──toggleRecording()──▶ STARTING ──▶ RECORDING ──tap mic──▶ TRANSCRIBING ──▶ IDLE
                                              │                      （成功，文本合并进 inputText）
                                              │
                                         abort（"暂停"）
                                              ▼
                                       已存音频 preservedSpeechAudio
                                              │
                                          retry（"重转"）
                                              ▼
                                       bulk 重转同一段音频 ──▶ IDLE
```

状态变量：`isStartingRecording` / `isRecording` / `isTranscribing` / `preservedSpeechAudio`（`ChatTabView.swift:52-71`）。关键性质：录音中屏蔽 partial（停止后才出字）；无 pause/resume；abort + retry 是恢复路径而非常规 UX；转写结果和手打共用一个可编辑缓冲。

### Run 状态机（agent）

```
IDLE ──sendCurrentInput()──▶ SENDING ──▶ AGENT RUNNING（state.isBusy）──abortSession()──▶ IDLE
                                                  │
                                              （SSE session.status 驱动 isBusy）
```

`isBusy` 由 `isBusySession(currentSessionStatus)` 推导，status 来自 SSE 的 `session.status` 事件或轮询 `/session/status`（`AppState.swift:624-625`、`AppState+SSE.swift:57-78`）。中断 agent 是 `abortSession()` → `POST /session/{id}/abort`。

### 碰撞点

碰撞集中在一处，但要分清它是什么、不是什么。

不是物理位置撞车。两个 `stop.fill` 一个在左栏（转写中）、一个在右栏（agent 运行中），靠状态互斥保证不同屏。

是视觉和语义撞车。同一个红色 `stop.fill` 字形承载两个完全不同子系统的"停"：停转写 vs 停 agent。用户无法从按钮本身判断按下会发生什么，得靠"现在是在转写还是 agent 在跑"这个不可见状态去推断。brief 说的"用户永远不该纠结自己按的是哪个 stop"，病根就在这里。

还有一个隐患值得记下来：互斥靠的是 `isTranscribing` 和 `state.isBusy` 不同时为真。但 `isBusy` 是 SSE 驱动的，如果 SSE 延迟、状态没及时更新，理论上存在两个红 stop 同屏的窗口。当前没有显式保证互斥的代码，这是个 latent risk。

---

## 三、控制模型方案：option 1（mode-switched）vs option 2（two zones）

brief 让评估两个结构方案、推荐一个。先说结论：基于 grounding，我推荐 **option 2（两个持久分区）的一个收敛版**，而不是 brief 倾向的 option 1（mode-switched 单面）。理由来自代码里 capture 和 run 状态实际怎么交错。

### 为什么不是 option 1

option 1 的设想是 composer 在 Capture 模式和 Run 模式之间整体切换，任一时刻只显示一套控件，靠切换消除重载。这个想法在"两个模式时间上互斥"时最干净。但代码里它们不是干净互斥的：agent 在跑（`state.isBusy`）的同时，用户完全可能想录下一条指令。这正是 steer 的高频场景，maintainer 并行盯多个 agent，一边看 agent 跑一边口述下一步。如果 composer 整体切到 Run 模式、把 mic 收起来，就挡住了 steer 本身。换句话说，capture 和 run 不是一个模式开关的两档，而是两条可以并行的轨道。用 mode-switch 去套，会在最关键的并行场景下卡住用户。

### 推荐：option 2 收敛版，两条持久轨道加中断 agent 移出 composer

把 composer 明确分成两个语义分区，各自只管一件事，永不复用字形：

第一，capture 轨道（左侧）。管口述本身：录音、停录、以及 stall 后的恢复。这里的"停"只停转写，用一个明确属于语音语义的字形，比如 `mic.slash` 或 `xmark`，绝不用 `stop.fill`。stall 恢复（当前的 abort+retry）作为这个轨道里的一个明确状态，不和 agent 中断共用任何视觉。

第二，send 轨道（右侧）。管发送：圆形 `arrow.up` 发送键，保持现状。

第三，中断 agent 移出 composer。这是消除重载最干净的一刀。brief §4a 也提到这个方向：interrupt-agent 控件只在 agent 运行时出现，且不放在 capture 区。建议把它放到对话流/顶部（比如 agent 正在跑时，对话区顶部出现一条明确写着"中断"的控件，带文字标签而非裸字形），这样它在物理位置和语义上都和"停录音"分开，用户不可能混淆。composer 右侧那个 `state.isBusy` 时出现的红 stop 就可以撤掉。

这样两个状态机各回各的物理区域：capture 在 composer 左侧、run 的中断在对话流，发送在 composer 右侧。三个区域语义独立、字形不复用，重载从根上消除。

### 让当前模式一望可知

brief 要求任一时刻用户都知道自己在"采集语音 / 审阅文本 / agent 在跑"。建议三态在 composer 材质上就分得开：

- 采集中：mic 区高亮（现有的红色 mic + 红圈底已经在做），输入框显示"正在听…"或连接阶段（连接中/已连接/等服务端收尾），不要静默。
- 审阅文本：转写结果落进可编辑输入框，mic 回到静默态，这时是普通的编辑+发送界面。
- agent 在跑：对话流顶部出现带标签的"中断"控件，composer 本身回到可输入态（因为用户可能要录下一条）。

### 针对 stall 设计，而不是 happy path

brief 说得对：happy path 已经能用，痛点在 stall。基于修正二（30 秒 finalize 超时）和修正四（abort+retry 是恢复路径），stall 体验应该这样处理：

- 把连接/收尾阶段暴露给 composer。用户停录后进入 finalize 等待时，显示"正在转写…"并给出进度感，而不是卡住的静默。这直接针对那个 30 秒超时窗口。
- 把 abort+retry 从"隐藏的恢复手段"提升为"明确的、低风险的状态"。stall 时给一句平静的提示（"转写卡住了，点这里重试"），retry 按钮（现有 `arrow.clockwise`）配文字说明它做什么（重转刚才那段，不丢音频）。
- 明确"重转"不是"续录"。当前 retry 是对已录音频重转，UI 文案要让用户知道音频没丢、这是在重试同一段，避免用户以为要重说一遍。

注意 brief §4b 里"实时显示 partial + 标记低置信度词"这一条，在当前 record→stop→transcribe 架构下不成立（修正三）。如果要做真正的边说边显示，那是改 VoiceFlowKit 集成层、放开 partial 屏蔽的一个独立工程决定，不在这次控制模型的范围里。这次先把重载和 stall 体验解决。

---

## 四、composer 关键状态草图

下面给五个关键状态的草图，都用现有 Quiet Tech 设计系统，不引入新视觉。主色 `#3B82F6`，红色保留给"中断/停止"类破坏性动作，圆角 `DesignCorners.medium`（12pt）。核心原则：capture 区的"停"和 run 区的"中断"字形永不相同。

### idle（空闲，可输入）

```
┌─────────────────────────────────────────────┐
│ 🎙  [ Ask anything…                    ]  ⬆  │   ← mic 静默灰 · 输入框 · send
└─────────────────────────────────────────────┘
```

### listening（采集中）

```
┌─────────────────────────────────────────────┐
│ 🔴  [ 正在听…                          ]  ⬆  │   ← mic 红 + 红圈底，输入框提示"正在听"
└─────────────────────────────────────────────┘
   再按 mic = 停录并转写（不是停 agent）
```

### transcribing / stalled（转写中，可能卡住）

```
┌─────────────────────────────────────────────┐
│ ⏳  [ 正在转写…                        ]  ⬆  │   ← mic 位转圈，显示 finalize 阶段
└─────────────────────────────────────────────┘
   若卡住（30s 超时附近）：
┌─────────────────────────────────────────────┐
│ ↻  [ 转写卡住了，点左侧重试这段        ]  ⬆  │   ← arrow.clockwise 重转（音频没丢）
└─────────────────────────────────────────────┘
   这里停转写的控件用 mic.slash / xmark，绝不用 stop.fill
```

### transcript-ready（文本就绪，可编辑）

```
┌─────────────────────────────────────────────┐
│ 🎙  [ 重构认证中间件，先看 token 刷新   ]  ⬆  │   ← 转写落进可编辑框，mic 回静默
└─────────────────────────────────────────────┘
   用户手改后发送；IME / 回车换行规则不变
```

### agent-running（agent 在跑，中断移出 composer）

```
   ┌───────────────────────────────┐
   │  ⏹ 中断 agent                 │   ← 对话流顶部，带文字标签，明确指向 agent
   └───────────────────────────────┘
   ……（对话流）……
┌─────────────────────────────────────────────┐
│ 🎙  [ 可以继续口述下一条指令…         ]  ⬆  │   ← composer 仍可输入，因为要 steer
└─────────────────────────────────────────────┘
```

最后这张是关键：agent 在跑时，中断控件在对话流顶部、带文字标签、指向 agent；composer 保持可输入，让用户能一边看 agent 跑一边录下一条。两个"停"在物理位置和文字上彻底分开，用户不可能再纠结按的是哪个。

---

## 五、交还设计方向：需要你定的几件事

第一，结构方案。我推荐 option 2 收敛版（两条持久轨道 + 中断 agent 移出 composer），而不是 brief 倾向的 option 1（mode-switched）。理由是代码里 capture 和 run 会并行（agent 跑时用户要 steer），mode-switch 会在这个高频场景挡路。这个判断需要你认可或推翻。

第二，中断 agent 放哪。我建议移出 composer、放对话流顶部带文字标签。也可以放顶部 bar。位置你定，但核心是它不能和 capture 区的"停录"共用字形或紧邻。

第三，capture 区"停"的字形。我建议 `mic.slash` 或 `xmark`，明确属于语音语义，和 agent 的 `stop.fill` 拉开。具体字形 hi-fi 时定。

第四，stall 体验的暴露程度。把 finalize 等待阶段（连接中/等服务端收尾）显示出来、把 retry 提升为明确状态，这是针对 30 秒超时的核心改动。要做到多详细（要不要显示倒计时、要不要区分网络慢和服务端慢）你定。

第五，partial 实时显示要不要做。brief §4b 想要的"边说边显示 + 标低置信度"，当前架构刻意屏蔽了 partial，做它要改 VoiceFlowKit 集成层，是个独立工程决定。我建议这次先不做、先解决重载和 stall，partial 单独评估。

工作量大致判断：消除重载（拆字形 + 中断移出 composer）是纯客户端、中等改动，主要在 `ChatTabView.swift` 的 composer 区和对话流。stall 体验暴露要碰 `ChatTabView+VoiceInput.swift` 的事件消费和阶段展示，小到中等。partial 实时显示要动 VoiceFlowKit 集成、放开屏蔽，单独排、最大。

按 brief 的循环，等你定了结构方案和上面几个点，你拿去做每个状态的 hi-fi、锁定 look，我再实现。
