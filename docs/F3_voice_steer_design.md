# F3 · 语音 composer 控制模型改动规格

本文是 F3 的改动规格，可以独立读懂。一句话：**OpenCode iOS Client 是一个 Steer 终端，语音 composer 是用户远离键盘时介入 AI 工作的主控台；当前 composer 把停录音、终止转写、重试转写、中断 agent 混在相似控件里，增加了用户的控制负担。这次要把这些控制语义拆开，尤其让长段口述卡住时有一个明确、低风险、用户主动触发的出口。**

文末附“关键事实”速查，供实现时核对 ASR 引擎、stall 成因、控件清单和状态变量。

---

## 一、产品前提

PRD 对这个 App 的定位不是移动端代码编辑器，也不是状态监控器，而是 OpenCode 的移动端 Steer 终端。AI 在 Mac/Server 上执行和探索，人类在 iPhone/iPad 上阅读 Markdown 报告、审查方向、用语音快速纠偏。语音输入的价值不是“更方便地输入文字”，而是在离开键盘时仍然能低摩擦地下达方向性指令。

这决定了 F3 的设计目标：它不是 UI polish，而是控制模型修正。用户打开 App 时通常在多线任务中切换，可能正在读 AI 的分析、判断是否偏航、同时准备下一条语音指令。这个场景下最危险的不是按钮不够好看，而是用户需要先想清楚“这个 stop 到底停什么”“卡住了是不是音频丢了”“我现在能不能安全退出”。这些判断会消耗 Steer 闭环里最宝贵的注意力。

F3 要降低三类 cognitive burden：

第一，控制对象负担。每个控制必须让用户一眼知道它控制的是语音采集、转写等待、转写恢复，还是 agent 运行。

第二，失败恢复负担。长段口述卡住是常态，不是边缘错误。当前实现已经有主动出口：转写等待时左侧红色方块会强行中断当前 WebSocket/finalize 等待，并保留音频给用户重试。F3 要改的不是“补一个出口”，而是把这个出口的语义讲清楚，不再让它和 agent 中断共用同一个 stop 图标。

第三，并行状态负担。agent 在跑时，用户仍然可能要继续口述下一条 steer 指令；composer 不能因为 agent busy 就变成只能中断、不能输入的运行模式。

设计语言遵守 `docs/design.md` 的 Quiet Tech 约束：稳定按钮不换位，mic/send 保持各自底部槽位；临时 stop/retry 只能出现在对应主按钮上方；语义主要靠位置、形态和文字，不靠多色堆叠；红色只用于真正的中断/停止类动作。

---

## 二、要解决的问题

composer 上现在有两套状态机：

- **Capture/Transcribe**：录音、停录、等待服务端 finalize、卡住后 abort 保存音频、retry 重转同一段。
- **Run/Agent**：发送消息、agent 运行、用户中断正在跑的 agent。

问题不是它们同屏共存本身，而是控件语义混在一起。

当前最明显的问题是两个红色 `stop.fill`：一个在左侧 mic 轨道，停的是语音转写等待；一个在右侧 send 轨道，停的是正在跑的 agent。它们同字形、同颜色，只靠左右位置区分。更关键的是，它们并不可靠互斥：代码允许 agent busy 时继续录音，用户停录后进入 `isTranscribing`，这时 `state.isBusy` 仍可能为真，于是两个红色 stop 可以自然同屏。用户看到两个同形同色 stop 时，需要靠位置记忆和当前上下文推断：左边停转写等待，右边停 AI inference。

另一个问题是主动出口的语义不清。停录后客户端等待服务端 finalize，最长可能卡到 30 秒超时；当前 UI 在左侧提供了红色方块，点击后会强行中断当前 WebSocket/finalize 等待，并给用户重试同一段音频的机会。这条恢复路径是对的，问题在于它看起来和右侧“中断 agent/session”的红色 stop 几乎一样。上一版设计文档如果只显示“正在转写”而没有主动退出等待的出口，就会退化成更差的体验；F3 不能丢掉当前已有的主动出口，而要把它重新命名、重新定位、重新解释。

目标是：用户任何时刻都能回答三个问题，而且不用多想。

第一，我现在是在录音、等转写、审阅文本，还是 agent 在跑。

第二，我按这个按钮会停什么。

第三，如果转写卡住，我能不能马上退出等待，并且保住刚才那段音频。

---

## 三、控制模型

采用“两条持久轨道 + agent 中断移出 composer”的结构。

### 1. Capture 轨道：左侧，控制语音

左侧轨道只管语音：开始录音、结束录音、等待转写、取消等待、重试刚才那段。mic 本身始终在左侧底部槽位，不能被临时按钮顶走。

录音中，点击 mic 是“停录并开始转写”。这里不使用 `stop.fill`，推荐用录音态 mic 高亮本身表达“再次点击结束录音”，或者在需要显式按钮时用 `mic.slash` / `xmark` 这类语音语义图标。

转写等待中，左侧 mic 位置显示等待态，mic 上方保留当前已有的主动出口，但重新命名和换形态。这个按钮的语义是：**停止等待服务端 finalize，保留已录音频，进入可重试状态**。它不是中断 agent，也不是丢弃整段录音。文案必须让这件事可见。

取消后，左侧临时按钮变成 retry（`arrow.clockwise`），语义是“重试刚才那段”。这对应当前 `retryPreservedSpeechAudio()` 的真实行为：用 bulk API 重转同一段已保存音频。

### 2. Send 轨道：右侧，控制发送

右侧轨道只管发送。`arrow.up` 保持在右侧底部槽位。即使 agent 正在跑，send 也保留，因为服务端支持 busy 时将消息入队，且 Steer 场景里用户常常要在 agent 运行期间追加下一条方向指令。

右侧 composer 不再放 agent stop。这样右侧只剩“发送/排队发送”，不再承担“中断 agent”。

### 3. Agent 中断：移出 composer，控制运行

agent 中断控件只在 `state.isBusy` 时出现，位置放在对话流顶部或顶部 bar，带文字标签，例如“中断 agent”。它调用同一个 `abortSession()`，但在物理位置、文案和视觉语义上都和语音控制分开。

这一步是消除语义重载的核心。agent 中断是对正在运行的远端任务下达破坏性控制；语音取消是对本地转写等待做恢复控制。它们不能共用裸图标，也不应该挤在 composer 里让用户凭上下文猜。

---

## 四、最终用户体验

### idle（空闲）

```
┌─────────────────────────────────────────────┐
│ 🎙  [ Ask anything…                    ]  ⬆  │
└─────────────────────────────────────────────┘
```

mic 静默灰，输入框可打字，右侧 send 在固定槽位。点 mic 开始录音。

### listening（采集中）

```
┌─────────────────────────────────────────────┐
│ 🔴  [ 正在听…                          ]  ⬆  │
└─────────────────────────────────────────────┘
```

mic 高亮，输入框提示“正在听”。再次点击 mic = 停录并开始转写。这一步是正常完成采集，不是 abort。不要把它画成和 agent 中断一样的 `stop.fill`。

### transcribing（等待转写，可主动退出等待）

```
    [ 取消转写 ]                         
┌─────────────────────────────────────────────┐
│ ⏳  [ 正在转写…                        ]  ⬆  │
└─────────────────────────────────────────────┘
```

停录后进入 finalize 等待，显示“正在转写”。这个阶段可能和 agent-running 同时发生：用户正在等语音转写，同时上一条 agent 仍在跑。左侧临时按钮沿用当前已有能力，但改成更明确的语义：建议文案为“停止等待”或“取消转写”，配 `xmark` / `mic.slash` / 小型 stop 变体均可，但不要复用 agent 的裸 `stop.fill`。点击后调用现有保留音频的 abort 路径，停止等待服务端，并进入 preserved-audio 状态。

这里的关键是心理模型：用户不是在销毁刚才的录音，而是在结束一次卡住的服务端等待。按钮附近或输入框内要有短文案说明“音频会保留，可重试”。

临时实现截图（用于本 PR 审核，merge 前可删除）：

![F3 transcribing + agent running](design_images/f3_transcribing_agent_running.png)

### stalled / preserved-audio（已退出等待，可重试）

```
    [ 重试这段 ]                         
┌─────────────────────────────────────────────┐
│ ↻  [ 转写已停止，刚才的音频已保留       ]  ⬆  │
└─────────────────────────────────────────────┘
```

用户主动取消等待，或系统到达 30 秒 finalize 超时后，都进入这个状态。文案要稳定、低压力，不要像 crash error。推荐表达：“转写已停止，刚才的音频已保留”“点左侧重试这段”。retry 调用 `retryPreservedSpeechAudio()`，重转同一段音频。

如果需要一个更短的小屏文案，用：“音频已保留，可重试”。

临时实现截图（用于本 PR 审核，merge 前可删除）：

![F3 retry preserved audio](design_images/f3_retry_preserved_audio.png)

### transcript-ready（文本就绪，可编辑）

```
┌─────────────────────────────────────────────┐
│ 🎙  [ 重构认证中间件，先看 token 刷新   ]  ⬆  │
└─────────────────────────────────────────────┘
```

转写结果落进可编辑输入框，mic 回静默。用户扫一眼、手改、发送。这是 PRD 里的 Steer 输入闭环：口述指令、审阅转写、发给 agent。

### agent-running（agent 在跑，composer 仍可输入）

```
   ┌───────────────────────────────┐
   │  ⏹ 中断 agent                 │   ← 对话流顶部或顶部 bar，带文字标签
   └───────────────────────────────┘
   ……（对话流）……
┌─────────────────────────────────────────────┐
│ 🎙  [ 可以继续口述下一条指令…         ]  ⬆  │
└─────────────────────────────────────────────┘
```

agent 在跑时，composer 不切到“运行模式”，也不隐藏 mic/send。用户仍然可以口述下一条方向指令，发送后由服务端队列处理。中断 agent 的控件离开 composer，避免和语音控制混淆。

---

## 五、要改的东西

每条写清现状、改法和文件落点。

**1. 停录/转写控制脱离 agent stop。**

现状：转写中左栏出现红色 `stop.fill`，按下调 `abortSpeechRecognition()`（`ChatTabView.swift:476-488`）。

改成：capture 轨道使用语音语义图标或带文字的取消按钮，表达“取消转写 / 停止等待”。它只影响语音转写，且保留已录音频。不再使用和 agent 中断相同的裸 `stop.fill`。

文件：`ChatTabView.swift` 的 composer 左栏。

**2. transcribing 阶段保留主动出口，但改清语义。**

现状：停录后进入 finalize 等待，左侧已有红色方块作为主动出口；点击后会中断当前 WebSocket/finalize 等待，保留音频并给 retry 机会。问题是它和右侧 agent 中断图标高度相似，用户只能靠位置区分；而且 agent busy 与转写等待可以自然并行，因此两个 stop 可以同屏出现。

改成：转写等待期显示“正在转写”，并保留这个主动出口，但把它表达为“停止等待/取消转写”。点击后仍走现有 abort-preserving-audio 路径，停止等待服务端，保留音频，进入 retry 状态。F3 不改变这条恢复能力，只消除它和 agent 中断的图标重载。

文件：`ChatTabView+VoiceInput.swift` 的事件消费与状态设置；`ChatTabView.swift` 的 composer 阶段展示。

**3. preserved-audio 状态显式展示 retry。**

现状：`preservedSpeechAudio` 和 `retryPreservedSpeechAudio()` 已存在，但 UI 语义容易被理解成重新说或普通错误恢复。

改成：取消等待或超时后，composer 明确显示“音频已保留，可重试”；左侧临时按钮显示 `arrow.clockwise`，文案为“重试这段”。retry 是重转同一段，不是续录，也不是要求用户重说。

文件：`ChatTabView+VoiceInput.swift`；`ChatTabView.swift`。

**4. 中断 agent 移出 composer。**

现状：agent 跑时 composer 右栏出现红色 `stop.fill`，按下调 `state.abortSession()`（`ChatTabView.swift:558-572`）。

改成：撤掉 composer 右栏这个 stop；在对话流顶部或顶部 bar 放一个只在 `state.isBusy` 时出现、带“中断 agent”文字标签的控件，调同一个 `abortSession()`。

文件：`ChatTabView.swift` 的 composer 右栏（删）和对话流顶部/toolbar（加）。

**5. send 轨道保持稳定。**

现状：`arrow.up` 是发送按钮。

改成：保留在右侧底部槽位。agent busy 时也保留，因为 `prompt_async` 支持 busy 入队，且 Steer 场景需要边看 agent 跑边追加下一条指令。

文件：`ChatTabView.swift`。

**6. 三态视觉可区分，但不引入新视觉语言。**

用户要能看出自己处在采集语音、等待/恢复转写、审阅文本、agent 运行哪一类状态。使用现有 Quiet Tech：mic/send 固定槽位，临时语音按钮在 mic 上方，agent 中断在对话流或顶部；主色仍是 `#3B82F6`，AI 工作态可用 gold，红色仅用于中断/停止类动作，圆角 `DesignCorners.medium`（12pt）。

---

## 六、明确不改的（防误伤）

这些已符合 PRD 和当前产品方向，不要顺手重做：

- **转写文本可编辑**：语音和手打共用 `inputText` 缓冲，finalize 合并转写结果，发送前可手改。
- **IME 提交规则**：中日文输入法 composing 时回车放行，让其正常 commit（`ChatComposerTextView.swift:11-15`）。
- **硬件回车 = 换行**：无 marked text 时裸回车插入换行，发送靠右侧按钮。
- **发送链路**：`sendCurrentInput()` → `sendMessage()` → `promptAsync()`（`POST /session/{id}/prompt_async`）。
- **busy 入队行为**：agent 运行中仍可发送，服务端负责排队处理；iOS 端不需要本地队列。
- **model picker**：在顶部 toolbar、per-session、切换不打断转写。它不在拥挤的 composer 区，不属于 F3。

---

## 七、范围外

**录音时实时显示 partial transcript（边说边显示、标低置信度词）不在这次范围。** 当前架构刻意屏蔽录音过程中的 `.partialTranscript` event；用户录音时看不到 live transcript。停录后的 finalize 阶段，`commitAndStop` 的 partial callback 可能会逐步把文本写进 `inputText`。要做真正的边说边显示，需要改 VoiceFlowKit 集成层、放开录音中的 partial 展示，是独立工程决定，工作量最大。

**真正的 pause/resume/append 不在这次范围。** 当前实现没有续录同一段的模型。F3 的 retry 是对已保存音频重转，不是续录。UI 文案必须如实表达这一点。

**push notification / Live Activity 不在这次范围。** PRD 已把人机异步空转列为高优先级工程增强，但 F3 只处理 App 前台 composer 控制模型。

---

## 八、待维护者拍板

这些点需要维护者或 hi-fi 设计定稿：

- **agent 中断放对话流顶部还是顶部 bar**：推荐对话流顶部，因为它贴近运行状态；顶部 bar 也可行。核心是不能放回 composer。
- **取消转写按钮的图标和文案**：推荐带文字优先，小屏可折叠成图标；候选文案“取消转写”“停止等待”。图标候选 `xmark` / `mic.slash` / 小型 stop 变体，但不得和 agent 中断的裸 `stop.fill` 混同。
- **转写等待多久后强化 stalled 文案**：可以立即显示“正在转写”，若超过 N 秒再补“可停止等待并重试”；也可以一直显示这个主动出口。基于当前实现已经有该出口、且该用户长段口述常态，推荐一直保留。
- **超时和用户主动取消是否共用同一 preserved-audio 状态**：推荐共用。用户只关心音频是否还在、能否重试，不需要理解服务端 finalize 失败细节。

工作量判断：消除重载（换语音控制 + 中断移出 composer）是纯客户端中等改动，集中在 `ChatTabView.swift`。转写等待出口本身已经存在，主要是改 UI 语义和 preserved-audio 状态展示；若需要调整事件状态展示，会碰 `ChatTabView+VoiceInput.swift`，小到中等。partial 实时显示范围外，单独排。

---

## 附录 · 关键事实速查

实现时核对用，均经源码核实。

- **ASR 引擎**：服务端 OpenAI realtime API（`gpt-realtime` 模型），WebSocket 推 PCM16/24kHz 音频。非 Apple SFSpeechRecognizer，非端上 Whisper。（`VoiceFlowConfig.swift:17-20`、`RealtimeTranscriptionClient.swift:85-86`）
- **stall 成因**：停录后客户端发 commit、等服务端回 `session_stopped`（idle）收尾；30 秒内没回则 `waitForFinalizeResult()` 超时杀会话。长段落加多秒静默时服务端出字慢，卡在这个超时上。（`RealtimeTranscriptionClient.swift:337-338`、`427-436`）
- **“暂停/重试”的真相**：没有 pause/resume/append。“暂停”是 `abortSpeechRecognition()` 停麦不 finalize、存音频到 `preservedSpeechAudio`；“重试”是 `retryPreservedSpeechAudio()` 把同一段音频走 bulk 非流式 API 重转。是重转，不是续录。（`ChatTabView+VoiceInput.swift:233-277`）
- **两个 `stop.fill` 按钮**：停转写等待（`ChatTabView.swift:476-488`，`isTranscribing` 时，调 `abortSpeechRecognition()`）；中断 agent（`ChatTabView.swift:558-572`，`state.isBusy` 时，调 `abortSession()` → `POST /session/{id}/abort`）。它们不是严格互斥：agent busy 时可以继续录音，停录后 `isTranscribing` 与 `state.isBusy` 可同时为真，两个红色 stop 可同屏出现。
- **状态变量**：capture 侧 `isStartingRecording` / `isRecording` / `isTranscribing` / `preservedSpeechAudio`（`ChatTabView.swift:52-71`）；run 侧 `isBusy` 由 `isBusySession(currentSessionStatus)` 推导（`AppState.swift:624-625`、`AppState+SSE.swift:57-78`）。
- **PRD 对语音输入的既定规格**：录音或转写卡住时，在 mic 轨道显示辅助 stop，调用 abort-preserving-audio；随后该按钮变为 retry，调用 preserved-audio bulk 重转。当前代码把临时 stop/retry 放在 mic 上方，符合 `docs/design.md` 的稳定槽位原则。F3 把这个规格提升为清晰的 composer 控制模型，而不是隐藏恢复路径。
