# OpenCode iOS Client

OpenCode 的 iOS 原生客户端，用于远程连接 OpenCode 服务端、发送指令、监控 AI 工作进度、浏览代码变更。

## 功能概述

- **Chat**：发送消息、切换模型、查看 AI 回复与工具调用
- **Files**：文件树、Session 变更、代码/文档预览
- **Settings**：服务器连接、认证、主题、语音转写配置

## 环境要求

- iOS 17.0+
- Xcode 15+
- 运行中的 OpenCode Server（`opencode serve` 或 `opencode web`）

## 快速开始（局域网）

1. 在 Mac 上启动 OpenCode：`opencode serve --port 4096`
2. 打开 iOS App，进入 Settings，填写服务器地址（如 `http://192.168.x.x:4096`）
3. 点击 Test Connection 验证连接
4. 在 Chat 中创建或选择 Session，开始对话

## 远程访问

OpenCode iOS 默认为局域网使用。如需远程访问，有两种方案：

### 方案 1：HTTPS + 公网服务器（推荐）

将 OpenCode 部署在公网服务器上，使用 HTTPS 加密：

1. 服务器上运行 OpenCode，配置 TLS 和认证
2. iOS App Settings 中填写 `https://your-server.com:4096`
3. 配置 Basic Auth 用户名/密码

⚠️ **安全提示**：公网暴露必须使用 HTTPS + 强认证。

### 方案 2：SSH Tunnel（高级用户）

通过公网 VPS 建立 SSH 隧道访问家里的 OpenCode：

```
iOS App → VPS (SSH) → VPS:18080 → 家里 OpenCode:4096
```

**前提条件**：
- 一台公网 VPS
- 家里机器与 VPS 建立反向隧道

**设置步骤**：

1. **家里机器**建立反向隧道到 VPS：
   ```bash
   ssh -N -T -R 127.0.0.1:18080:127.0.0.1:4096 user@your-vps
   ```

2. **iOS App**配置 SSH Tunnel：
    - Settings → SSH Tunnel → 开启
    - 填写 VPS 地址、用户名、远程端口（18080）
    - 复制公钥，添加到 VPS 的 `~/.ssh/authorized_keys`
    - 复制 app 生成的 reverse tunnel command，在电脑端执行
    - Server Address 改为 `127.0.0.1:4096`（通过隧道访问），然后点 `Test Connection`

**注意**：SSH Tunnel 功能需要添加 Citadel 依赖，目前为预览状态。

## 项目结构

```
OpenCodeClient/
├── OpenCodeClient/          # 主程序
│   ├── Models/              # 数据模型
│   ├── Services/            # API、SSE、语音转写
│   ├── Stores/              # 状态存储
│   ├── Utils/               # 工具类
│   └── Views/               # SwiftUI 视图
├── OpenCodeClientTests/     # 单元测试
└── OpenCodeClientUITests/   # UI 测试
```

## 文档

- `docs/OpenCode_iOS_Client_PRD.md` — 产品需求
- `docs/OpenCode_iOS_Client_RFC.md` — 技术方案
- `docs/OpenCode_Web_API.md` — OpenCode API 说明

## License

与 OpenCode 保持一致。
