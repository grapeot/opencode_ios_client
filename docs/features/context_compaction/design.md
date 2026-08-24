# OpenCode iOS Manual Context Compaction Design

Status: proposal only, no implementation

## Bottom Line

`/compact` is a client-side command, not a prompt sent to the model. The Web client recognizes it in the composer, invokes a session compaction API, and never submits the literal text as a user message.

The iOS client currently has no equivalent command layer. `sendMessage` forwards all composer text to `/session/:id/prompt_async`, so typing `/compact` sends those characters to the model. This is expected from the current implementation, not a server bug.

The recommended product shape is one session action with two entry points:

1. A visible `Compact Context` action in the session overflow menu and context-usage UI.
2. A `/compact` slash-command shortcut in the composer for keyboard users.

Both entry points must call the same typed client action. Neither should create a normal user message.

## Current Mechanism

### Web Client

The Web client registers a built-in command with:

- command ID: `session.compact`
- slash trigger: `compact`
- action: call `client.session.summarize(...)`

When the slash picker selects a built-in command, the composer clears the command text and calls the command registry. Custom slash commands follow a different path and remain editable prompt text.

Relevant source:

- `opencode-official/packages/app/src/pages/session/use-session-commands.tsx`
- `opencode-official/packages/app/src/components/prompt-input.tsx`

This explains the observed Tab behavior. Tab selects a local autocomplete item; selection dispatches `session.compact`. It is not a model-side interpretation of `/compact`.

### Current iOS Client

The iOS path is currently:

```text
composer text
  -> AppState.sendMessage(...)
  -> APIClient.promptAsync(...)
  -> POST /session/:id/prompt_async
  -> normal user message
```

There is no built-in command registry or pre-send interception. `Part.type` can decode unknown part types as strings, but iOS has no dedicated compaction state or completion presentation.

Relevant source:

- `OpenCodeClient/OpenCodeClient/AppState+Messages.swift`
- `OpenCodeClient/OpenCodeClient/Services/APIClient.swift`
- `OpenCodeClient/OpenCodeClient/Models/Message.swift`

## Backend Contract

OpenCode currently has two API generations that should not be conflated.

### Legacy API Used By The Current Web Client

```http
POST /session/:sessionID/summarize
Content-Type: application/json

{
  "providerID": "openai",
  "modelID": "gpt-5.6-sol",
  "auto": false
}
```

The handler:

1. Cleans up an active revert state.
2. Finds the active agent from recent history.
3. Appends a synthetic user message containing a `compaction` part.
4. Runs the normal session loop with the selected model.
5. Generates a structured summary of older history, optionally incorporating the previous summary.
6. Continues future turns from the compacted representation.

The operation consumes a model call. It is not a local string truncation algorithm.

### V2 API Direction

The V2 public design exposes:

```http
POST /api/session/:sessionID/compact
Content-Type: application/json

{}
```

Current V2 documentation describes this as asynchronous admission: the server accepts a compaction input, runs it at a safe session boundary, and reports progress/completion through session events. An optional request ID supports idempotent retry.

The local July 14 checkout is transitional: the route exists, but its core implementation still returns `OperationUnavailableError`. Therefore the iOS client should not switch to V2 based only on route shape. It should use the legacy contract for the currently deployed server and migrate only after a capability check or coordinated server upgrade.

### What Compaction Changes

Compaction changes the model-visible representation of session history. It does not delete the original durable messages from storage.

Conceptually:

```text
Durable session history
  = original messages remain available to clients and export

Next model context
  = system context
  + generated checkpoint/summary of older history
  + retained recent turns
  + messages created after compaction
```

The summary is lossy. Exact old details can disappear from future model context even though the original messages still exist in the session database.

Automatic compaction is a separate trigger over the same underlying concern. Current legacy configuration uses `compaction.auto`, `compaction.prune`, and `compaction.reserved`; V2 is moving toward model-aware headroom and retained-tail settings. Manual compaction should work independently of whether automatic compaction is enabled.

## Recommended UX

### Primary Entry Point

Add `Compact Context` to the session `...` menu near `Interrupt Agent`, rename, and other session-level actions.

Display a concise explanation in the action row or first-use sheet:

> Summarize older conversation to free context space. Full history remains visible, but the agent may lose exact older details.

This is more discoverable than requiring users to know a terminal-style command.

### Context Usage Entry Point

Make the existing context ring open a small detail sheet:

```text
Context used                 78%
Older turns can be summarized to free space.

[Compact Context]
```

The action may become visually prominent above a product-defined threshold, but the user should be allowed to compact earlier. Do not auto-trigger manual compaction merely because the sheet opens.

### Slash Command Entry Point

When the composer begins with `/`, show a native command picker. Include:

```text
/compact       Compact context
/summarize     Alias for /compact
```

Selecting either command should invoke the typed action immediately or replace the composer with an action chip requiring Send. Immediate invocation matches Web behavior and is the smaller design.

Safe parsing rules:

- Intercept only a recognized built-in command selected from the picker, or an exact trimmed `/compact` or `/summarize` submitted without attachments.
- Do not interpret `/compact please`, embedded `/compact`, or an attachment plus `/compact` as compaction.
- If text starts with a reserved built-in command but has invalid syntax, show a local syntax error rather than silently sending it to the model.
- Preserve any pre-existing draft that was present before opening the slash picker.

### Progress And Completion

The UI state should be session-scoped:

```text
idle -> requesting -> compacting -> completed
                          |
                          -> failed
```

Recommended presentation:

- While requesting/compacting: context ring shows subtle progress and the menu action reads `Compacting Context...`.
- On completion: insert or reveal a quiet timeline divider, `Context compacted`, then refresh context usage.
- On failure: show a retryable error without changing or discarding the composer draft.
- Do not show a cancel button unless the backend gains a compaction-specific cancellation contract.

For legacy `summarize`, the HTTP result can indicate completion, while SSE message and part updates refresh history. For V2, HTTP acceptance is not completion; the client must wait for the compaction event or a settled session state.

### Busy Session Behavior

For the legacy MVP, disable manual compaction while the session is busy. This avoids racing the existing prompt loop and gives the user a predictable contract.

After V2 safe-boundary admission is deployed, allow the action while busy and label it `Compact after current step`. The server, not iOS, should serialize it against prompts and coalesce duplicate requests.

### Confirmation Policy

Do not require a confirmation dialog every time. The action is lossy for future model attention, but it does not delete durable history, and the official clients already expose it as a direct command.

A one-time educational sheet or clear action subtitle is enough. Repeated modal confirmation would make the context ring shortcut unnecessarily heavy.

## Client Architecture

Keep command parsing separate from API transport:

```text
Composer / Session Menu / Context Sheet
                 |
                 v
       AppState.compactCurrentSession()
                 |
                 v
       SessionCompactionClient
          |              |
          v              v
 legacy summarize     V2 compact
```

`AppState.compactCurrentSession()` should own eligibility, session-scoped progress, errors, completion refresh, and duplicate-tap suppression. UI surfaces should only invoke it.

The transport adapter should make the API generation explicit. Avoid a fallback that blindly calls V2 and then legacy on every error, because a timeout can leave the first request admitted and produce duplicate model calls. Capability selection should come from server version/capability metadata or a stable host-profile setting.

## Delivery Slices

### Slice 1: Current Server MVP

- Add legacy `summarize` API request.
- Add one AppState compaction action and state.
- Add `Compact Context` to the session menu.
- Intercept exact `/compact` and `/summarize` locally.
- Disable while busy or when the session has no user messages.
- Refresh messages and context usage after success.
- Add unit tests proving the command text never reaches `prompt_async`.

This requires no server change and is a small-to-medium iOS feature. The main risk is state/UX correctness, not backend complexity.

### Slice 2: Discoverability

- Add the context-ring detail sheet.
- Add slash-command autocomplete instead of exact-send interception alone.
- Add a dedicated timeline marker and localized strings.

### Slice 3: V2 Migration

- Select V2 through an explicit capability contract.
- Submit an idempotent compact request.
- Track admitted, running, completed, and failed events.
- Permit queueing behind a busy turn.
- Remove legacy transport only after all supported hosts expose the V2 behavior.

## Acceptance Criteria

1. Selecting `/compact` never creates a normal user text message.
2. Menu, context ring, and slash command invoke one shared AppState action.
3. A failed request leaves the session and composer draft intact.
4. Duplicate taps cannot start duplicate compaction model calls.
5. Completion refreshes messages and context usage.
6. Durable pre-compaction history remains visible after completion.
7. The UI states that old details may be summarized lossily.
8. Legacy and V2 completion semantics are tested separately.
9. The client does not retry through a second API generation after an ambiguous timeout.

## Recommendation

Build Slice 1 first when implementation is authorized. It fixes the surprising iOS behavior and adds a discoverable session action without changing the server. Treat the V2 endpoint as a later protocol migration, not as a prerequisite for the feature.
