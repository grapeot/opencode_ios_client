# Sync Streaming 调研报告

> 目标：让 iOS 客户端在流式更新、工具调用展示上接近官方 Web 客户端的行为（实时流式、完成后收起等）

## 1. 调研结论概览

| 能力 | API 支持 | 可实现的改进 |
|------|----------|---------------|
| **Text/Reasoning delta 流式** | ✅ 支持 | 解析 `message.part.updated` 的 `delta`，增量追加，实现打字机效果 |
| **Tool 完成后收起** | 不依赖 API | 纯 UI：running 时展开，completed 时默认折叠 |
| **Tool output 实时流式** | ❌ 不支持 | 当前 output 仅在 completed 时一次性发送（见 GH #5024） |
| **Tool input 流式** | ❌ 未实现 | `tool-input-delta` 在 server 端被丢弃（见 GH #9737） |

**结论**：iOS 客户端可以实现「类 Web 客户端」的 sync streaming 体验，主要包含：

1. **Text/Reasoning 流式**：使用 `delta` 增量更新，替代当前的全量 reload
2. **Tool 卡片折叠**：running 时展开显示进度，completed 时默认收起

## 2. API 能力详情

### 2.1 `message.part.updated` 与 delta

根据 OpenCode 源码与 PR：

- 事件类型：`message.part.updated`
- `properties` 可包含：
  - `part`：完整 Part 对象
  - `delta`：增量文本（用于 TextPart / ReasoningPart）
- 定位：通过 `messageID` + `partID`（或 `part.id`）定位到具体 Part

参考：GitHub #9480（Fix updatePart input narrowing for delta wrapper）确认 `{ kind: "delta", part: TextPart | ReasoningPart, delta?: string }` 结构。

### 2.2 当前 iOS 行为

```swift
// AppState.swift - handleSSEEvent
case "message.updated", "message.part.updated":
    if currentSessionID != nil {
        await loadMessages()  // 全量 reload，未使用 delta
    }
```

- 收到 `message.part.updated` 时只做全量 reload
- 未解析 `properties.delta`
- 无增量更新、无打字机效果

### 2.3 Tool output 流式

- **GitHub #5024**：用户请求 Bash 工具在运行期间流式输出 stdout，说明当前不支持
- **cefboud.com 分析**：`tool-result` 时一次性发送完整 `output`，无中间 delta

因此：**Tool 的 output 无法在 iOS 端实现实时流式**，除非 OpenCode 后续支持。

### 2.4 Tool input 流式

- **GitHub #9737**：`tool-input-delta` 在 processor 中被丢弃，`state.raw` 未填充
- 提案尚未合并，当前无法获取 partial tool arguments

## 3. 推荐实现范围

### 3.1 Phase 2.5：Sync Streaming（建议纳入）

| 项 | 描述 | 实现要点 |
|----|------|----------|
| Delta 解析 | 解析 `message.part.updated` 的 `properties.delta` | 在 `handleSSEEvent` 中区分 delta 与完整 part |
| 增量更新 | 定位 Part，将 delta 追加到 text/reasoning | 维护 `messageID+partID → 累积文本` 映射，或就地更新 `messages` 中对应 Part |
| 打字机效果 | 文本逐渐浮现 | 增量更新后 UI 自动体现 |
| Tool 折叠 | running 展开，completed 收起 | `ToolPartView` 增加展开/折叠状态，根据 `state.status` 决定默认值 |

### 3.2 不纳入（受 API 限制）

- Tool output 实时流式（terminal 输出逐行显示）
- Tool input 流式（partial args 如 file path 提前显示）

## 4. 参考资料

- [GH #5024](https://github.com/anomalyco/opencode/issues/5024) - Bash tool call deltas（用户请求）
- [GH #9480](https://github.com/anomalyco/opencode/issues/9480) - Fix updatePart input narrowing for delta wrapper
- [GH #9737](https://github.com/anomalyco/opencode/issues/9737) - Expose partial tool arguments via state.raw
- [cefboud.com - How Coding Agents Actually Work: Inside OpenCode](https://cefboud.com/posts/coding-agents-internals-opencode-deepdive/)
