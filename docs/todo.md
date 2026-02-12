# TODO

1. Chat tab 里的 AI response 支持文字选择/复制（包括 Markdown 渲染内容）。

2. 从 Chat 里点“跳转到文件”的图标后，打开的 Markdown 预览有时显示不对（空白/只显示第一行）。
   - 先排查明显 bug；如果不容易复现/定位，就补充更有用的 log，便于后续你贴回日志继续追。

3. Tool call 卡片的“理由/标题”在收起态只显示一到两行，超出用省略号；展开后显示完整内容。

4. 支持 OpenCode 的 session task list（todo）：
   - 参考 `opencode-official` 的 web client 渲染方式
   - iOS 端实现渲染与更新（含新建/更新）
   - 同步更新 RFC / PRD / WORKING.md
