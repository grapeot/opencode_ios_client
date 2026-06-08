# F3 · 语音 composer 控制模型改动规格

本文是 F3 的改动规格,独立读懂。一句话:**当前 composer 里有两个长得一模一样的红色"停止"按钮,一个停语音转写、一个中断 agent,用户分不清按的是哪个。这次把它们彻底分开,并把长段口述卡住时的恢复体验做明确。**

文末附"关键事实"速查,供实现时核对(ASR 引擎、stall 成因、控件清单)。

---

## 一、要解决的问题

维护者的主要输入方式是语音:口述指令、扫一眼转写、发送。composer 是全 app 最高频的控制面,但它现在把两套互不相关的控制挤在一起,且有一处语义重载:

- **采集语音**这套:录音、停录、长段卡住后的恢复。
- **跑 agent**这套:发送、中断正在跑的 agent。

问题的核心:停录和中断 agent 都用一个红色 `stop.fill` 按钮,同字形、同颜色,只是分处 composer 左右两栏、靠状态互斥不同屏。用户看到一个红 stop,得从"现在是在转写还是 agent 在跑"这个看不见的状态去推断它停什么。窄屏或紧张操作时很容易按错。

目标:用户任何时刻都不必纠结自己按的是哪个"停";且长段口述卡住(这对该用户是常态)时,恢复路径明确、低风险,不像出错。

---

## 二、最终用户体验

composer 分成语义清晰的两条轨道,加上一个独立的 agent 中断控件。五个状态下用户看到和能做的:

### idle(空闲)

```
┌─────────────────────────────────────────────┐
│ 🎙  [ Ask anything…                    ]  ⬆  │
└─────────────────────────────────────────────┘
```
mic 静默灰、输入框、send。点 mic 开始录音,打字也行。

### listening(采集中)

```
┌─────────────────────────────────────────────┐
│ 🔴  [ 正在听…                          ]  ⬆  │
└─────────────────────────────────────────────┘
```
mic 变红 + 红圈底,输入框提示"正在听"。再点 mic = 停录并开始转写。这一步的"停"只停录音,字形不是 `stop.fill`(用 `mic.slash` 或 `xmark` 一类明确属于语音语义的图标)。

### transcribing / stalled(转写中,可能卡住)

```
┌─────────────────────────────────────────────┐
│ ⏳  [ 正在转写…                        ]  ⬆  │
└─────────────────────────────────────────────┘
   若卡住:
┌─────────────────────────────────────────────┐
│ ↻  [ 转写卡住了,点左侧重试这段         ]  ⬆  │
└─────────────────────────────────────────────┘
```
停录后进入转写等待,显示"正在转写",给进度感,不要静默。若卡住(见关键事实里的 30 秒超时),给一句平静提示和重试按钮(`arrow.clockwise`),文案说明它重转的是刚才那段、音频没丢。这是"重试同一段",不是"重新说一遍"。

### transcript-ready(文本就绪,可编辑)

```
┌─────────────────────────────────────────────┐
│ 🎙  [ 重构认证中间件,先看 token 刷新   ]  ⬆  │
└─────────────────────────────────────────────┘
```
转写结果落进可编辑输入框,mic 回静默。用户手改后发送。这就是普通的编辑加发送界面。

### agent-running(agent 在跑)

```
   ┌───────────────────────────────┐
   │  ⏹ 中断 agent                 │   ← 对话流顶部,带文字标签
   └───────────────────────────────┘
   ……(对话流)……
┌─────────────────────────────────────────────┐
│ 🎙  [ 可以继续口述下一条指令…         ]  ⬆  │
└─────────────────────────────────────────────┘
```
中断 agent 的控件移出 composer,放对话流顶部,带"中断"文字标签、明确指向 agent。composer 本身保持可输入,因为 agent 在跑时用户正要口述下一条指令做 steer。两个"停"在物理位置和文字上彻底分开,不可能再混淆。

---

## 三、要改的东西

逐条列改动。每条:现状 → 改成什么 → 碰哪个文件。

**1. 停录按钮换字形,脱离 `stop.fill`。**
现状:转写中左栏出现红色 `stop.fill`,按下调 `abortSpeechRecognition()`(`ChatTabView.swift:476-488`)。
改成:换成语音语义的图标(`mic.slash` 或 `xmark`,hi-fi 时定),不再用 `stop.fill`。它属于 capture 轨道,只停转写。
文件:`ChatTabView.swift` 的 composer 左栏。

**2. 中断 agent 移出 composer。**
现状:agent 跑时 composer 右栏(send 上方)出现红色 `stop.fill`,按下调 `state.abortSession()`(`ChatTabView.swift:558-572`)。这是和停录撞车的另一半。
改成:撤掉 composer 右栏这个红 stop;在对话流顶部(或顶部 bar)放一个只在 `state.isBusy` 时出现、带"中断"文字标签的控件,调同一个 `abortSession()`。位置和语义都和停录分开。
文件:`ChatTabView.swift` 的 composer 右栏(删)+ 对话流顶部(加)。

**3. send 轨道保持现状。**
圆形 `arrow.up` 发送键不动。它已经是 capture 之外独立的一栏。

**4. stall 阶段暴露给 composer。**
现状:停录后进入 finalize 等待,UI 没有阶段反馈,卡住时是静默(见关键事实:30 秒 finalize 超时)。
改成:转写等待期显示"正在转写"并给进度感;卡住时给平静提示 + 重试按钮(现有 `arrow.clockwise`)配文案,说明重转同一段、音频没丢。
文件:`ChatTabView+VoiceInput.swift` 的事件消费 + 阶段展示。

**5. 三态视觉可区分。**
任一时刻用户能看出自己在"采集语音 / 审阅文本 / agent 在跑":采集中 mic 区高亮 + 输入框"正在听";审阅文本时 mic 静默、普通编辑界面;agent 跑时对话流顶部有中断控件、composer 仍可输入。用现有 Quiet Tech 系统,主色 `#3B82F6`,红色只留给中断/停止类破坏性动作,圆角 `DesignCorners.medium`(12pt),不引入新视觉。

---

## 四、明确不改的(防误伤)

这些已正确实现,不要碰:

- **转写文本可编辑**:语音和手打共用 `inputText` 缓冲,finalize 合并转写结果,发送前可手改。
- **IME 提交规则**:中日文输入法 composing 时回车放行让其正常 commit(`ChatComposerTextView.swift:11-15`)。
- **硬件回车 = 换行**:无 marked text 时裸回车插入换行,发送靠右侧圆形按钮。
- **发送链路**:`sendCurrentInput()` → `sendMessage()` → `promptAsync()`(`POST /session/{id}/prompt_async`)。
- **model picker**:在顶部 toolbar、per-session、切换不打断转写。它不在拥挤的 composer 区,不动。

---

## 五、范围外

**录音时实时显示 partial transcript(边说边显示、标低置信度词)不在这次范围。** 当前架构刻意屏蔽了录音过程中的 partial,只在停录后的 finalize 才出字。要做真正的边说边显示,得改 VoiceFlowKit 集成层、放开 partial 屏蔽,是个独立工程决定,单独排,工作量最大。这次先解决重载和 stall。

---

## 六、待维护者拍板

改动方向里有几处倾向已定但需确认:

- **结构走"两条轨道 + 中断移出 composer"**,而不是"composer 在采集模式和运行模式之间整体切换"。原因:agent 跑时用户要同时口述下一条,整体切模式会把 mic 收起来、挡住 steer。这个判断需要认可或推翻。
- **中断 agent 放对话流顶部还是顶部 bar**,位置待定,核心是不能和停录共用字形或紧邻。
- **停录的图标选 `mic.slash` 还是 `xmark`**,hi-fi 时定。
- **stall 反馈做多细**(要不要倒计时、要不要区分网络慢和服务端慢),待定。

工作量:消除重载(换字形 + 中断移出)是纯客户端、中等改动,集中在 `ChatTabView.swift`。stall 暴露碰 `ChatTabView+VoiceInput.swift`,小到中等。partial 实时显示(范围外)动 VoiceFlowKit,最大。

---

## 附录 · 关键事实速查

实现时核对用,均经源码核实。

- **ASR 引擎**:服务端 OpenAI realtime API(`gpt-realtime` 模型),WebSocket 推 PCM16/24kHz 音频。非 Apple SFSpeechRecognizer,非端上 Whisper。(`VoiceFlowConfig.swift:17-20`、`RealtimeTranscriptionClient.swift:85-86`)
- **stall 成因**:停录后客户端发 commit、等服务端回 `session_stopped`(idle)收尾;30 秒内没回则 `waitForFinalizeResult()` 超时杀会话。长段落加多秒静默时服务端出字慢,卡在这个超时上。(`RealtimeTranscriptionClient.swift:337-338`、`427-436`)
- **"暂停/重试"的真相**:没有 pause/resume/append。"暂停"是 `abortSpeechRecognition()` 停麦不 finalize、存音频到 `preservedSpeechAudio`;"重试"是 `retryPreservedSpeechAudio()` 把同一段音频走 bulk 非流式 API 重转。是重转,不是续录。(`ChatTabView+VoiceInput.swift:233-277`)
- **两个 `stop.fill` 按钮**:停录(`ChatTabView.swift:476-488`,`isTranscribing` 时,调 `abortSpeechRecognition()`);中断 agent(`ChatTabView.swift:558-572`,`state.isBusy` 时,调 `abortSession()` → `POST /session/{id}/abort`)。靠状态互斥不同屏,但 `isBusy` 是 SSE 驱动,延迟时理论上有同屏窗口,无显式互斥保证。
- **状态变量**:capture 侧 `isStartingRecording` / `isRecording` / `isTranscribing` / `preservedSpeechAudio`(`ChatTabView.swift:52-71`);run 侧 `isBusy` 由 `isBusySession(currentSessionStatus)` 推导(`AppState.swift:624-625`、`AppState+SSE.swift:57-78`)。
