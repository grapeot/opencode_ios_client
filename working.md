# 工作记录 - OpenCode iOS 客户端

## 2026-03-13

- 回滚了上一版 root-only session 列表交互：iPhone 和 iPad 的 session 列表重新按完整树状层级展示 child/subagent sessions，避免 stop 等会话上下文在列表里“消失”。
- 新增 `docs/testing_strategy_and_behavior_guard_plan.md`，把当前测试体系、behavior guard 分层策略，以及 session 列表这类交互回归该怎么防讲清楚了。

## 2026-03-12

- Files Tab 和 Tool Call 输出中的图像文件现在显示真实的图像预览，而不是 base64 文本。
- 图像查看器优化：默认适应屏幕、双指缩放/拖拽、双击切换缩放、分享菜单支持保存到相册。
- 重写 README.md，面向开源用户，添加 TestFlight 安装入口。
- 聊天自动滚动逻辑优化：仅当用户在底部时跟随新内容；向上滚动时暂停跟随。
- 更新 PRD 和 RFC，与当前应用功能对齐：问题卡片、图像预览、模型列表、安装方式、聊天行为。
- 为 AppState 补了一轮更扎实的测试，先把会话加载、创建、删除、发消息失败回滚等关键流程兜住。
- 给 APIClient 和 SSEClient 加了注入入口，后续拆 AppState 和网络层时可以直接用 mock 做回归验证。
- 完成了 SSH 隧道这一轮的最小安全修复，收掉递归闭包/并发捕获这类 P0 风险点。
- 同步刷新了代码审查文档，标记这轮已经完成的测试加固和 SSH 修复进展。
- 新增一组 SSE 行为测试，直接覆盖 `session.updated`、`message.updated`、`message.part.updated`、`session.status` 这些关键事件对状态的影响。
- 开始真正拆 `AppState`：先把消息流式状态继续往 `MessageStore` 下沉一小步，降低后续 store split 的风险。
- 重新跑通 iOS 客户端完整测试，确认这轮 SSE 测试和小范围下沉没有引入回归。
- 继续补了两条 SSE 契约测试，把当前 session 的 `message.updated` reload 行为和非当前 session 的 `message.part.updated` 忽略逻辑都锁住。
- `message.part.updated` 这条链路继续下沉：现在由 `MessageStore` 自己解析并决定 append、finalize 还是 ignore，`AppState` 只保留刷新和 reload 的编排。
- 左侧 session 列表现在默认不再展示 child/subagent sessions，避免它们把主会话列表挤满。
- session 列表滚到底后会自动继续拉更多数据；即使前面 100 条里混进了很多 child sessions，也能把后面的主会话继续补出来。

## 2026-03-11

- 修复语音转录：空草稿不再出现前导空格。
- 稳定聊天自动滚动：流式输出时避免滚动到空白区域。

## 2026-03-07

- 实现 Question 功能：服务器发起的 `question` 提示渲染为交互卡片，会话可继续。
