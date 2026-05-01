# OpenCode iOS Client

A native iOS, iPadOS, and visionOS client for [OpenCode](https://github.com/opencode-ai/opencode). Connect to your OpenCode server from your iPhone, iPad, or Apple Vision Pro to chat with AI agents, monitor tool calls in real time, and browse code changes on the go.

## Install via TestFlight

Don't want to build from source? Join the TestFlight beta:

**https://testflight.apple.com/join/2cWrmPVq**

No Apple Developer account needed. Just tap the link on your iOS device.

## Features

- **Chat**: send messages, switch models, view AI replies with streaming, inspect tool calls and reasoning
- **Files**: file tree browser, session diffs, markdown preview, image preview with zoom/pan, code view with line numbers
- **Settings**: server connection, Basic Auth, SSH tunnel, theme, voice transcription

### Apple Vision Pro support

The `OpenCodeClientVision` target is a native visionOS build that reuses the existing iPad-style three-column `NavigationSplitView` layout: sidebar, file preview, and chat. It deliberately avoids the iPhone tab-based layout.

Current visionOS baseline limitations:

- SSH tunnel settings are hidden and SSH tunneling is not available. Connect directly to a LAN or HTTPS OpenCode server instead.
- Markdown content uses native `AttributedString` rendering on visionOS while the MarkdownUI dependency remains iOS/iPadOS-only. Workspace image handling still uses the full MarkdownUI renderer on iOS and iPadOS.

### Hardware keyboard behavior on iPad

- `Enter`: insert a newline
- Send: use the circular arrow button on the right side of the composer
- Chinese/Japanese IME composition is allowed to commit marked text normally

## Requirements

- iOS 17.0+ or visionOS 26.0+ for the native Vision target
- A running OpenCode server (`opencode serve` or `opencode web`)
- Xcode 16+ (only if building from source)

## Quick Start

1. Start OpenCode on your Mac: `opencode serve --port 4096`
2. Open the iOS app, go to Settings, enter the server address (e.g. `http://192.168.x.x:4096`)
3. Tap Test Connection
4. Switch to Chat, create or select a session, and start talking

## Remote Access

The app is designed for LAN use by default. Two options for remote access:

**HTTPS + public server (recommended)**: deploy OpenCode on a public server with TLS. Point the iOS app to `https://your-server.com:4096` and configure Basic Auth credentials.

**SSH Tunnel**: the app has a built-in SSH tunnel (powered by Citadel). Set up a reverse tunnel from your home machine to a VPS, then configure the tunnel in Settings > SSH Tunnel. See `docs/` for detailed steps.

## Building from Source

```bash
git clone https://github.com/grapeot/OpenCodeClient.git
cd OpenCodeClient/OpenCodeClient
open OpenCodeClient.xcodeproj
```

Select the `OpenCodeClient` scheme, pick a simulator or device, and hit Run. Swift Package dependencies resolve automatically on first build.

For the native visionOS target, build `OpenCodeClientVision`:

```bash
xcodebuild -project "OpenCodeClient.xcodeproj" \
  -target "OpenCodeClientVision" \
  -configuration Debug \
  -sdk xrsimulator \
  CODE_SIGNING_ALLOWED=NO build
```

## License

MIT
