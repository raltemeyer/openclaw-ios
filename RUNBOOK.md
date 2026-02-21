# OpenClaw iOS V1 RUNBOOK

## Scope shipped overnight
- System tab for active sessions/agents (best-effort multi-endpoint probing)
- Per-agent controls in chat: reset session, stop run, set model
- Attachments in chat (Photos + files)
- Streaming reliability improvements (state tracking, stop, non-stream retry, surfaced errors)
- Settings control panel improvements (gateway profiles, diagnostics, tailscale-first guidance)
- Recovery helpers using SSH command templates (copy/paste, no embedded shell)

## Gateway assumptions (v1)
The app is defensive and tries multiple endpoints because gateway variants differ.

### Read endpoints probed
- `GET /status`
- `GET /health`
- `GET /v1/models`
- `GET /sessions`
- `GET /v1/sessions`
- `GET /agents`
- `GET /v1/agents`

### Chat endpoint
- `POST /v1/chat/completions`

### Control endpoints attempted (fallback list)
- Reset session: `POST /sessions/reset` → `/v1/sessions/reset` → `/agents/reset`
- Stop run: `POST /sessions/stop` → `/v1/sessions/stop` → `/agents/stop`
- Set model: `POST /agents/model` → `/v1/agents/model` → `/sessions/model`

If all fail, UI presents: use Recovery SSH template path.

## Attachment behavior
- Images: encoded as OpenAI-style content part (`image_url` data URL)
- Text-like files: first ~12KB injected as text content part
- Binary files: included as metadata note only

### Known endpoint constraint
Some gateways reject rich `content` arrays or image/file input. In that case user sees a visible error and can retry non-stream mode.

## Diagnostics & recovery
- Gateway profiles: `custom`, `lan`, `tailscale`
- Recovery section provides SSH commands only (no remote shell in app):
  - `openclaw gateway status`
  - `openclaw gateway restart`
  - tail gateway log

## Security constraints upheld
- No internet exposure changes
- No embedded shell or arbitrary command execution in app
- Tailscale-first wording kept; loopback/tailscale posture retained

## Validation checklist for Ryan (morning)
1. Open app Settings, select Tailscale profile, set real URL/token
2. Tap **Test Connection**
3. Send message in each agent tab
4. Attach one photo + one text file and send
5. Induce stream cancel and retry
6. Open System tab and confirm endpoint probe notes/sessions
7. Try reset/stop/model actions and confirm either success or graceful fallback message

## Deferred items (explicit)
- True binary file upload endpoint (multipart) once gateway contract stabilizes
- Strongly typed server schema for sessions/agents/actions
- Keychain storage for token (currently UserDefaults MVP)
- Per-agent persisted model override state
- Deeper stream reconnection/backoff policy + resumable run IDs
