# OpenClaw iOS App

Native SwiftUI app for your OpenClaw agent hub.

## Features

- **Multi-agent chat** — Hopper, Henry, Mr. DAG, Scout in separate tabs
- **SSE streaming** — live token-by-token responses
- **Local + remote** — LAN via Mac IP, or remote via Tailscale
- **Persistent history** — conversations saved to device storage
- **Connection status** — live indicator per chat

## Requirements

- iOS 17+
- Xcode 16+
- OpenClaw gateway running (port 18789)

## Setup

1. Open `OpenClawApp.xcodeproj` in Xcode
2. Select a simulator or connected device
3. Build & run (⌘R)
4. In the Settings tab, enter:
   - **Gateway URL**: `http://<your-mac-ip>:18789`
   - **Auth Token**: from `~/.openclaw/openclaw.json` → `gateway.auth.token`

### Finding your Mac's IP

```bash
ipconfig getifaddr en0
```

### Remote access (Tailscale)

The gateway's `allowTailscale: true` config means your Tailscale IP works automatically. Find it in the Tailscale app on your Mac.

## Architecture

```
Sources/
├── OpenClawApp.swift          # @main entry point
├── ContentView.swift          # Tab container + setup flow
├── Models/
│   ├── Agent.swift            # Agent definitions (Hopper, Henry, Mr. DAG, Scout)
│   └── Message.swift          # Message + Conversation models
├── Services/
│   ├── GatewayService.swift   # SSE streaming via /v1/chat/completions
│   ├── ConversationStore.swift # Local persistence
│   └── SettingsStore.swift    # UserDefaults-backed settings
└── Views/
    ├── ChatView.swift          # Main chat interface
    ├── MessageBubble.swift     # Message rendering
    └── SettingsView.swift      # Gateway config + agent list
```

## Regenerating the Xcode project

If you add/move Swift files, regenerate with:

```bash
brew install xcodegen  # one-time
cd ~/Developer/OpenClawApp
xcodegen generate
```

## Gateway API

Uses the OpenAI-compatible endpoint (enabled in `openclaw.json`):
```
POST /v1/chat/completions
Authorization: Bearer <token>
x-openclaw-agent-id: main|henry|mrdag|scout
```
