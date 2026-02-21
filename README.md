# OpenClaw iOS App

Native SwiftUI app for OpenClaw remote management.

## Overnight V1 Highlights

- Multi-agent chat (Hopper, Henry, Mr. DAG, Scout)
- System tab: best-effort active sessions/agent visibility
- Agent controls: reset session, stop run, model change attempts with graceful fallback
- Attachments in chat: photo picker + file picker (with gateway-capability-aware behavior)
- Streaming reliability: explicit stream state, cancel, retry (non-stream fallback), surfaced errors
- Settings/control panel: gateway profiles, tailscale-first guidance, diagnostics
- Recovery helpers: safe SSH command templates (no embedded shell)

## Requirements

- iOS 17+
- Xcode 16+
- OpenClaw gateway running (default port 18789)

## Setup

1. Open `OpenClawApp.xcodeproj` in Xcode
2. Select simulator/device and build
3. Configure in Settings:
   - Gateway URL (`http://<tailscale-or-lan-ip>:18789`)
   - Auth token from `~/.openclaw/openclaw.json` (`gateway.auth.token`)

## Core endpoint usage

### Chat
- `POST /v1/chat/completions`

### System probe (best effort)
- `GET /sessions`, `GET /v1/sessions`, `GET /agents`, `GET /v1/agents`
- Connectivity probes: `GET /status`, `GET /health`, `GET /v1/models`

### Control actions (fallback chain)
- Reset: `POST /sessions/reset` → `/v1/sessions/reset` → `/agents/reset`
- Stop run: `POST /sessions/stop` → `/v1/sessions/stop` → `/agents/stop`
- Set model: `POST /agents/model` → `/v1/agents/model` → `/sessions/model`

See `RUNBOOK.md` for detailed operational notes, validation steps, and deferred work.
