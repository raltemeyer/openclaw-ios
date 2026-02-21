# OpenClaw iOS V1.1 RUNBOOK

## Scope shipped
- Agent management in Settings: show/hide agents in bottom tab bar
- Per-profile settings model: each profile has gateway URL/token + visible agents + tab order
- Tab order editing for visible agents (Edit mode drag/reorder)
- Backward-compatible migration from legacy single-profile settings
- System tab for active sessions/agents (best-effort multi-endpoint probing)
- Per-agent controls in chat: reset session, stop run, set model
- Attachments in chat (Photos + files) with limits + allowlist UX
- Streaming reliability upgrades (reconnect/backoff, stop, non-stream retry fallback, surfaced errors)
- Settings control panel improvements (gateway profiles, diagnostics, tailscale-first guidance)
- Recovery helpers using SSH command templates (copy/paste, no embedded shell)
- Remote ops extra: copyable diagnostics report from System tab
- Gateway token moved from UserDefaults to Keychain with migration fallback

## Security posture (kept)
- No internet exposure changes
- No embedded shell or arbitrary command execution in app
- Tailscale-first wording retained; loopback/tailscale deployment assumed

## Endpoint compatibility
The app is defensive and tries multiple endpoints because gateway variants differ.

### Read endpoints probed
- `GET /status`
- `GET /health`
- `GET /v1/models`
- `GET /sessions`
- `GET /v1/sessions`
- `GET /agents`
- `GET /v1/agents`

### Chat endpoint chain
- Primary: `POST /v1/chat/completions`
- Fallback: `POST /chat/completions`

### Control endpoint fallback chains
- Reset session: `POST /sessions/reset` → `/v1/sessions/reset` → `/agents/reset`
- Stop run: `POST /sessions/stop` → `/v1/sessions/stop` → `/agents/stop`
- Set model: `POST /agents/model` → `/v1/agents/model` → `/sessions/model`

If all fail, UI presents fallback guidance to recovery SSH templates.

## Attachment behavior and limits
- Max attachments/message: 5
- Max per attachment: 10 MB
- Max total attachment payload: 20 MB
- Allowed file types: text/json/csv/xml/pdf (+ images from photo picker)
- Images: encoded as OpenAI-style `image_url` data URL
- Text-like files: first ~12KB injected as text content part
- Binary/non-text files: metadata note only (no binary upload path in this version)

## Streaming behavior
- Automatic reconnect attempts: up to 3
- Backoff: 2s, 4s (capped)
- If stream still fails, app attempts non-stream completion once
- Stream states shown in UI (connecting/reconnecting/active/failed)

## Usage notes (Agent Management)
1. Open **Settings → OpenClaw Instance** and choose/create a profile.
2. In **Agent Management**, use toggles to control which agents appear in bottom tabs.
3. Tap **Edit** (top-right), then drag visible agents to reorder tab order.
4. Hidden agents remain listed and can be re-enabled at any time.

Profile behavior:
- URL/token are scoped per profile.
- Agent visibility + order are scoped per profile.
- Switching profiles swaps all of the above immediately.

## Build + Test status on this host
Attempted full simulator build using `xcodebuild`, but host is currently pointed at Command Line Tools only:
- error: `xcodebuild requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance`

### To run on ryans-mac-studio (full Xcode)
1. Ensure full Xcode is installed
2. Set developer directory (if needed):
   - `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. Build:
   - `xcodebuild -project OpenClawApp.xcodeproj -scheme OpenClawApp -destination 'platform=iOS Simulator,name=iPhone 16' build`
4. Smoke test in simulator:
   - Configure URL/token
   - Chat each agent
   - Attach one image + one text/pdf file
   - Cancel stream and verify retry/fallback flow
   - Open System tab and copy diagnostics report

## Known limitations / deferred
- No multipart binary upload endpoint yet (pending stabilized gateway contract)
- Session/agent/action payloads still best-effort decoded (not fully typed API schema)
- No per-agent persisted model preference yet
- No run-resume by run-id (retries are request-level)
