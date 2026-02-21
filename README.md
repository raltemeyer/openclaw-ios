# OpenClaw iOS App

Native SwiftUI app for OpenClaw remote management.

## V1.1 Hardening Highlights

- Multi-agent chat (Hopper, Henry, Mr. DAG, Scout)
- **Agent visibility customization:** Settings → Agent Management lets you show/hide agents in bottom tabs
- **Editable tab order:** reorder visible agent tabs in Settings (Edit mode)
- **Profile-aware preferences:** each OpenClaw profile stores its own gateway URL/token + visible agents + tab order
- **Token security hardening:** gateway token moved to Keychain with automatic UserDefaults migration
- **Streaming resiliency:** reconnect/backoff attempts + non-stream fallback + clearer status states
- **Attachments hardened:** explicit type allowlist, per-file + total size limits, clear UX feedback
- **Endpoint compatibility:** chat fallback chain (`/v1/chat/completions` then `/chat/completions`) and defensive probing
- System tab polish with per-session quick actions (reset/stop)
- **New remote-ops feature:** one-tap diagnostics report copy for incident escalation
- Recovery helpers: safe SSH command templates (no embedded shell)

## Requirements

- iOS 17+
- Xcode 16+
- OpenClaw gateway running (default port 18789)

## Setup

1. Open `OpenClawApp.xcodeproj` in Xcode
2. Select simulator/device and build
3. Configure in Settings:
   - (Optional) create/select an **OpenClaw Instance** profile (e.g., Ryan, Wife)
   - Gateway URL (`http://<tailscale-or-lan-ip>:18789`)
   - Auth token from `~/.openclaw/openclaw.json` (`gateway.auth.token`)
4. In **Settings → Agent Management**:
   - Toggle agents on/off for tab visibility
   - Reorder visible tabs using Edit mode drag handles

## Core endpoint usage

### Chat
- `POST /v1/chat/completions`
- Fallback: `POST /chat/completions`

### System probe (best effort)
- `GET /sessions`, `GET /v1/sessions`, `GET /agents`, `GET /v1/agents`
- Connectivity probes: `GET /status`, `GET /health`, `GET /v1/models`

### Control actions (fallback chain)
- Reset: `POST /sessions/reset` → `/v1/sessions/reset` → `/agents/reset`
- Stop run: `POST /sessions/stop` → `/v1/sessions/stop` → `/agents/stop`
- Set model: `POST /agents/model` → `/v1/agents/model` → `/sessions/model`

See `RUNBOOK.md` for validation and known limitations.
