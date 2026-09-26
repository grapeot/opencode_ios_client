# V1 / V2 server compatibility

Status: spec, ready to implement. The app code is not changed yet.

Measured on tag `v2.0.18`, `serve` at `127.0.0.1:4198`, Basic auth user `opencode`. Clone: `tmp/opencode_v2`. Do not use port 4096.

The target is every V1 behavior the iOS app has today. Same screens, same models. V1 hosts stay on the current requests. V2 hosts use the mappings below. Do not guess a body that is not written here. Do not hide a control because the old route is gone.

## Detection

`apiGeneration` on `HostProfile` is `auto`, `v1`, or `v2`. Missing field decodes as `auto`. The stored value is bound to the host URL. Changing the URL clears it.

Probe `GET /global/health`, then `GET /api/info`, using the full body up to 8 KB. The body must parse. A `{` prefix is not enough.

- V1 only when health is 200 JSON, `version` is a string, and `healthy` is true. `healthy: false` is V1 and not connected.
- HTML, or 500 with an empty body, is not V1. Packaged servers return HTML 200 for unknown paths. This source `serve` returned empty 500.
- V2 when `/api/info` is 200 JSON with a string `version`. `/api/health` is 404. Do not probe it.
- 401 and 403 are authentication failures. Timeouts are transport failures. Neither continues into the other probe.
- Anything else is `unrecognized`, reported with both statuses.

`isConnected` becomes true only after the session list for that generation succeeds. `serverVersion` is the `version` string from the winning probe.

New files: `ServerGeneration.swift` for the probe, `V2Mapper.swift` for the maps below. `makeRequest` stays. Each `APIClient` method branches on the stored generation. V1 bodies and status checks do not change.

## Session and message maps

Do not add a second session or message type.

Session, from `data` on get, create, fork, and each list element:

| UI field | V2 source |
|---|---|
| `id` | `id`. Missing throws for get, create, and fork. A list element missing it is skipped. |
| `slug` | `id` |
| `projectID` | `projectID` |
| `directory` | `location.directory`. Missing throws for get, create, and fork. |
| `parentID` | `parentID`, or nil |
| `title` | `title`, or `"Untitled"` |
| `version` | `"2"` |
| `time.created` / `time.updated` | those integers. Missing throws for get, create, and fork. |
| `time.archived` | the local archive map below, not the server field |
| `share`, `summary` | nil |
| `revert` | `revert` when it has `messageID`, else nil |

`POST /api/session` body is `{}` or `{"title": title}`. Do not send the V1 `directory` query. Do not send `x-opencode-directory`. The displayed directory is `location.directory`.

List is `GET /api/session?limit=`. Unwrap `data`. Ignore `cursor`.

Title update is `PATCH /api/session/:id` `{"title": title}`. Require 204 and an empty body. Then GET and map. Do not decode the patch body.

Delete is `DELETE /api/session/:id`. Require 204.

Fork is `POST /api/session/:id/fork`. Body is `{}`, or `{"before": messageID}` when the caller passed a message id. The field name is `before`, not `messageID`. Require 200. Map `data` with the session map.

Revert is `POST /api/session/:id/revert/stage` `{"messageID": messageID}`. Require 200. Then GET the session and return that `Session`. Clearing a staged revert is `DELETE /api/session/:id/revert`, require 204, then GET. Do not decode the stage body as `Session`. The stage body is `{data:{messageID, files}}`.

Message, from each element of `GET /api/session/:id/message?limit=50` `data`. `sessionID` is the id that was queried.

| V2 `type` | UI |
|---|---|
| `user` | `role` `"user"`. Text from `text`, else `payload.text`. Files from `files` or `payload.files`: each item with string `data` and string `mime` becomes a file part whose `url` is `data:{mime};base64,{data}` and whose `filename` is `name`. No text and no file: skip. |
| `assistant` | `role` `"assistant"`. Text parts from `content` entries with `type` `"text"`. Tool parts from `content` entries with `type` `"tool"`: `type` `"tool"`, `tool` is `name`, `state` is `state`. Reasoning entries are not visible text. No text and no tool: skip. Copy `tokens` when present. |
| anything else, including `idle` | skip |

Copy `id` and `time.created`. Skip the item if either is missing. Each text part has `type` `"text"`, `messageID` equal to the message id, `sessionID` equal to the queried session, and `id` equal to `messageID + "-" + index`. `time.completed` is copied when present.

Other `Message` fields:

| Field | Rule |
|---|---|
| `parentID` | For an assistant item, the id of the nearest preceding user item in the same list. Otherwise nil. V2 messages have no `parentID`. |
| `providerID`, `modelID` | From assistant `model.providerID` and `model.id`. Otherwise nil. |
| `model` | `ModelInfo` from those two strings when both exist. Otherwise nil. |
| `error` | Assistant `error` becomes `MessageError` with `name` = `error.type` and `data` = `{"message": error.message}`. Otherwise nil. |
| `finish` | Assistant `finish`, or nil. |
| `tokens` | `input`, `output`, `reasoning`, `cache.read`, `cache.write` from assistant `tokens`. `total` is their sum. Missing tokens is nil. |
| `cost` | Assistant `cost` when it is a number. Otherwise nil. |
| `structured` | Nil from the server. `promptStructured` sets it after local JSON decode. |
| tool `callID` | Assistant tool `id`. |
| tool `state` | The `state` object, unchanged. |

A malformed envelope throws. `{"data":[]}` is an empty transcript. Skipping every element is also empty, not an error. V1 message decoding stays on its current path.

## Every current method

| Method | V2 call | Status | Map |
|---|---|---|---|
| `health` | probe above | see Detection | |
| `sessions` | `GET /api/session?limit=` | 200 | session map, then overlay local archive |
| `session` | `GET /api/session/:id` | 200 | session map |
| `createSession` | `POST /api/session` | 200 | session map |
| `updateSession` | PATCH title, then GET | 204 then 200 | session map |
| `updateSessionArchived` | no request | | local archive map |
| `deleteSession` | `DELETE /api/session/:id` | 204 | |
| `forkSession` | `POST .../fork` | 200 | session map |
| `revertSession` | `POST .../revert/stage`, then GET | 200 then 200 | session map |
| `messages` | `GET .../message`, plus `limit` only when the caller passed one | 200 | message map |
| `promptAsync` | switch agent and model, then `POST .../prompt` | 204, 204, 200 | do not store the admission as an assistant message. Then reload messages. |
| `promptStructured` | switch agent and model, then text prompt, then poll | 200 | parse the assistant text locally |
| `abort` | `POST .../interrupt` `{}` | 200 | ignore `interrupted` |
| `sessionStatus` | no poll | | last `session.status` event, missing means idle |
| `pendingPermissions` | `GET /api/session/:id/permission` | 200 | permission map |
| `respondPermission` | `POST .../permission/:id/reply` `{"decision": once\|always\|reject}` | 204 | |
| `pendingQuestions` | `GET /api/session/:id/form` | 200 | form map |
| `replyQuestion` | `POST .../form/:id/reply` | 204 | |
| `rejectQuestion` | `DELETE .../form/:id` | 204 | |
| `providers` | `GET /api/model`, `GET /api/provider`, and `GET /api/model/default` | 200 | model map |
| `providerRegistry` | same two calls | 200 | connected ids are provider `id`s whose `activation` is not `"disabled"`. If the provider list is empty, use the provider ids present on the model list. |
| `agents` | `GET /api/agent` | 200 | agent map |
| `sessionDiff` | `GET /api/session/:id/diff` | 200 | diff map |
| `sessionTodos` | no request | | todo walk |
| `fileList` | `GET /api/fs/list?path=` | 200 | file node map |
| `fileContent` | `GET /api/fs/read/` plus the relative path | 200 | raw bytes |
| `findFile` | `GET /api/fs/find?query=&limit=` | 200 | `data[].path` |
| `fileStatus` | `GET /api/vcs/status` | 200 | status map |
| `projects` | `GET /api/project` | 200 | project map. The body is a bare array. |
| `projectCurrent` | `GET /api/location` | 200 | the project whose `id` equals `project.id`. If the list has no match, build one from `project.id` and `project.directory`. |

`sessions(directory:)`, `createSession(directory:)`, `fileList(directory:)`, and `fileContent(directory:)` ignore `directory`. Do not send it, and do not send `x-opencode-directory`. `revertSession(partID:)` ignores `partID`. Stage the whole message. `promptAsync` ignores `directory`. If `messageID` is non-empty, the prompt body includes `"id": messageID`. 2.0.18 echoed that id.

`updateSessionArchived` returns the mapped session after the local overlay. It does not call the network.

`selectSession` on V2 loads messages, permissions, and forms, then runs the todo walk for that session id. It does not call `/session/status`, `/todo`, or `/question`. `refreshSessions` updates busy state from the last `session.status` event.

### Send

Before `promptAsync` or `promptStructured`, if the selected agent is non-empty, `POST /api/session/:id/agent` `{"agent": agent}` and require 204. If a model is selected, `POST /api/session/:id/model` `{"model":{"id": modelID, "providerID": providerID}}` and require 204. Do not put agent or model in the prompt body.

Text prompt body is `{"text": trimmed}`. Require 200. A `parts` body is 400. Do not send it.

Image prompt adds `files`. Each attachment is `{"uri": dataURL, "name": filename}`. `dataURL` is the existing `ComposerImageAttachment.dataURL`, which already looks like `data:image/png;base64,...`. Do not send `mime`, `data`, or `source`. That shape is the internal file object, and 2.0.18 rejected it. The `uri` shape returned 200 and echoed the image bytes. A `file://` URI is only for a path the server can read. The phone does not have that path. Use the data URI.

An extra `format` field is ignored. 2.0.18 returned 200 and did not constrain the model. Do not send it.

### Archive

`PATCH` drops `time.archived`. The gate proved a follow-up GET still has no `archived`. Store `HostProfile.archivedSessionIDs`, `[String: Int]`, optional, missing decodes as empty. Archive writes the session id to the current epoch milliseconds. Restore removes the key. Overlay that value onto `time.archived` after the session map. Send does not restore on the server first.

### Questions

There is no `/question` route. A pending form is a question card.

`GET /api/session/:id/form` returns `{data: [Form]}`. Each form becomes one `QuestionRequest`:

| UI | V2 |
|---|---|
| `id` | `id` |
| `sessionID` | `sessionID` |
| `tool` | nil |
| `questions` | one `QuestionInfo` per field, in order |

Field to question:

| Field `type` | `header` | `question` | `options` | `multiple` | `custom` |
|---|---|---|---|---|---|
| `string` with `options` | `key` | `title`, or `key` | `label` and `description` or `""`. Option `id` stays the label. The submitted value is `value`, not `label`. | false | `custom`, or false |
| `multiselect` | `key` | `title`, or `key` | same | true | `custom`, or false |
| `string` without options | `key` | `title`, or `key` | empty | false | true |
| `number`, `integer`, `boolean` | `key` | `title`, or `key` | empty | false | true |
| `external` | skip | | | | |

`replyQuestion` and `rejectQuestion` receive only a request id. Keep an in-memory table on `APIClient`, filled by `pendingQuestions` and by `form.created`. Key is the form id. Value is the session id, the fields in order, and for each option the label and the value. If two options in one field share a label, keep the first and drop the later one. If the id is not in the table, throw `APIError.httpError(statusCode: 404, data: Data())`.

Reply converts `[[String]]` through that table to `{answer: {key: value}}`. A selected label uses the stored value. A string that matches no label is a custom value and is sent as that string. A multiselect is an array of values. A number or integer that does not parse throws `APIError.httpError(statusCode: 400, data: Data())`. A boolean is `true` only for `"true"`. `POST /api/session/:sessionID/form/:formID/reply`. Require 204. Reject is `DELETE` that form. Require 204.

### Permissions

`GET /api/session/:id/permission` returns `{data: [Request]}`.

| UI | V2 |
|---|---|
| `id` | `id` |
| `sessionID` | `sessionID` |
| `permission` | `action` |
| `patterns` | `resources` |
| `always` | `save` |
| `metadata.filepath` | string `metadata.filepath`, else nil |
| `tool.messageID` | `source.messageID` when `source.type` is `"tool"` |
| `tool.callID` | `source.id` in that same case |

Reply body is `{"decision":"once"}`, `"always"`, or `"reject"`. Not `response`. Require 204.

### Files, diff, models, projects

File list and find unwrap `data` of `{path, type}`. `name` is the last path component. `absolute` is nil. `ignored` is nil. Find returns those paths as `[String]`.

File read returns raw bytes, not JSON. UTF-8 that decodes is `FileContent` type `text` with that string. Anything else is type `binary` and `content` nil.

File status unwraps `data` of `{file, additions, deletions, status}`. `FileStatusEntry.path` is `file`. `status` is copied. `added`, `deleted`, and `modified` are the only values. There is no `untracked`.

Diff unwraps `data` of `{file, patch, additions, deletions, status}`. `FileDiff.file` is `file`. `before` is `""`. `after` is `patch`. Copy additions, deletions, and status.

`GET /api/model` and `GET /api/provider` are `{location, data}`. `data` may be empty. Group models by `providerID`. `ConfigProvider.id` is that id. `name` is the provider `name`, or the id. `ProviderModel.id` is model `id`. `name` is model `name`. `providerID` is model `providerID`. `limit.context` and `limit.output` come from `limit`. `capabilities.toolCall` is `capabilities.tools`. `attachment` is true when `capabilities.input` contains `"image"`. `family` is `family`. `providers()` also calls `GET /api/model/default`. `ProvidersResponse.default` uses `data.providerID` and `data.id` when `data` is an object with both strings. Null or missing `data` means nil. A provider with no `activation` is connected. `activation` `"disabled"` is not. A model whose provider is missing from the provider list still appears, under a provider whose id and name are that `providerID`.

Agent unwraps `data`. `AgentInfo.name` is `name` when non-empty, else `id`. Copy `description`, `mode`, and `hidden`. `native` is nil.

`GET /api/project` is a bare array of `{id, canonical, vcs, name, icon, time, sandboxes}`. `Project.worktree` is `canonical`. `vcs` is `vcs`. `icon.color` is `icon.color`. `time.created` and `time.updated` are copied. `sandboxes` is empty. `displayName` already uses the last path component, so `name` is not required.

Current project is `GET /api/location`. Match `project.id` in the list. If missing, `Project(id: project.id, worktree: project.directory, vcs: nil, icon: nil, time: nil, sandboxes: [])`.

### Todos

`GET .../todo` is 404. The 2.0.18 server removed the `todowrite` tool, so a stock server has no todo array. The screen stays. `sessionTodos(sessionID:)` loads that session's messages with the message map, including when it is not the current session. Walk assistant messages from last to first. The first tool part whose `state.input.todos` is an array wins. Map each element with the existing `TodoItem` decoder. If no part has that array, store an empty list for that session. That clears a stale list. Do not call `/todo`. Do not remove the control.

### Structured send

There is no format field the server honors. `promptStructured` still returns `MessageWithParts`. Car Mode reads `response.info.structured` as `CarResponseEnvelope` and requires `time.completed != nil`, `version == 1`, and non-empty `speech`. It throws `CarModeError.invalidResponse` otherwise. There is no text parser today. This method builds that object.

1. Switch agent and model as in Send.
2. Build one text: the existing system string, a blank line, the user text, a blank line, then `Reply with only JSON matching this schema:` and the encoded `StructuredOutputFormat`.
3. Body is `{"text": that}`. If `messageID` is non-nil, also set `"id"` to that value. A fresh id returned 200 with `data.id` equal to it. Remember that admitted user id. A 409 on that id means it was already admitted. Do not fail. GET messages and continue the poll if that user id is present. If it is absent, throw `CarModeError.invalidResponse`.
4. Poll `GET .../message` with the caller's limit, or no limit query when the caller passed nil, every 1 second, for at most 60 seconds. Stop early when the open SSE socket reports `session.status` `idle` or `retry` for this session.
5. Map the list. Select the assistant whose `parentID` is the admitted user id. If several match, use the last one. Ignore assistants that belong to an older user message.
6. Take that assistant's last text part. Decode it with `JSONDecoder` as `CarResponseEnvelope`. Set `Message.structured` to that value. If `time.completed` is nil and the session is idle, set `time.completed` to `time.created` so the existing completed check passes. Return that `MessageWithParts`.
7. If 60 seconds pass, or the text does not decode, or `version` is not 1, or `speech` is empty, throw `CarModeError.invalidResponse`.

The continuation path in `AppState+ClientCapabilities` looks for `parentID == continuationMessageID`. Sending that id as the prompt `id`, then setting assistant `parentID` to the preceding user id, is what makes that check succeed.

Do not call `/session/:id/message`. Do not send `format`.

## SSE

`ContentView` starts SSE on connect. On V2 the socket is `GET /api/event`, with the same Basic auth and `Accept: text/event-stream`. Frames are `data: {json}\n\n`. Ignore lines that start with `:`. The measured first frame is `data: {"id":"...","type":"server.connected","data":{}}`.

The JSON has `id`, `type`, and `data`. Durable events also have `created` and may have `location`. Do not read `payload.properties`. Translate `data` into the dictionaries the existing handlers already accept, then call those handlers.

| V2 `type` | Existing handler | Translation |
|---|---|---|
| `server.connected` | `server.connected` | empty properties |
| `session.status` | `session.status` | `data` already has `sessionID` and `status`. `status.type` is `idle`, `busy`, or `retry`. Retry also has `attempt`, `message`, and `next`. |
| `session.idle` | `session.status` | `{sessionID, status:{type:"idle"}}` |
| `session.created`, `session.renamed`, `session.metadata.updated` | `session.updated` | GET the session and upsert. Do not decode the event as `Session`. This is the V2 substitute for `session.updated`. |
| `session.deleted` | `session.deleted` | `data.sessionID` |
| `session.text.started` | step start, then `message.part.updated` | `ordinal` is `data.ordinal`. Part id is `data.assistantMessageID + "-text-" + String(ordinal)`. The same ordinal always yields the same id, including after reconnect. Call `recordStepStart(assistantMessageID, sessionID:)` first. Then part `{type:"text", id: that id, messageID: assistantMessageID, sessionID}`. |
| `session.text.delta` | `message.part.delta` | Same part id from `data.ordinal`. Properties `{sessionID, messageID: assistantMessageID, partID, field:"text", delta: data.delta}`. |
| `session.text.ended` | direct reload | Do not call the part-updated finalizer. Call `loadMessages()` and `loadSessionDiff()`. |
| `session.reasoning.delta` | none | do not call `recordVisibleToken` |
| `session.reasoning.ended` | none | `loadMessages()` |
| `session.message.content.updated` | direct reload | `loadMessages()`. Step start already happened on `session.text.started`. |
| `permission.asked` | `permission.asked` | apply the permission map, then the existing parser |
| `permission.replied` | `permission.replied` | `permissionID` is `data.requestID`. The existing remover accepts `permissionID` or `id`. |
| `form.created` | `question.asked` | map `data.form` with the form map, store it in the reply table, and append |
| `form.replied`, `form.cancelled` | `question.rejected` | Both only remove the card. Pass `{id: data.id}` to `QuestionController.applyResolvedEvent`. `question.replied` uses that same remover. There is no second rejected behavior. |
| `session.execution.failed` | `session.error` | properties `error` is `{name: data.error.type, data: {message: data.error.message}}`, plus `sessionID`. The existing handler decodes that as `Message.MessageError`. |

There is no `todo.updated`. Recompute todos after every message reload. There is no `message.updated` and no `message.part.delta` on this socket. Do not wait for those names.

`sessionStatus()` does not poll. A session missing from the last status event is idle. `/api/session/active` is not the replacement.

## Test gate

```bash
V2_BASE=http://127.0.0.1:4198 V2_PASSWORD=... python3 scripts/v2_contract_check.py
```

Exit 0 only when every case passes. This script starts no server and does not touch port 4096. It locks the requests and envelopes. It does not run a model, so it does not prove a live token, a real permission ask, or a Car Mode JSON parse. Those three are unit tests against the saved bodies below.

The script locks wire status and envelopes. It does not decode Swift models. Saved-body unit tests do that, and they are written with the mapper, not in this spec. The script covers detection on the live server, session create/list/get/patch/delete, text prompt, a client-supplied message id echoed back, image data URI, ignored `format`, rejected `parts`, message reload, interrupt, absent todo, absent status map, file list with `path`, find with `limit` and `data[].path`, file read bytes, agents, providers, models, `GET /api/model/default`, location, projects, vcs, diff, form list, session permission list, missing form reply and cancel as 404, missing permission reply as 404, archive PATCH 204 with the field still absent, fork, revert stage 200, revert clear 204 or 404 after interrupt, agent switch, model switch, and an SSE frame parsed as `type` `server.connected` with `data` `{}`.

`providers()` also calls `GET /api/model/default`. The body is `{location, data}`. `data` is a model object or null. `ProvidersResponse.default` uses `data.providerID` and `data.id` when both are strings. Otherwise nil. A provider with missing `activation` is connected. `activation` `"disabled"` is not. A model whose provider is absent from the provider list still appears, under a provider whose id and name are that `providerID`.

## Unit tests

Saved bodies, no server. One test per row. A row is not done until its test passes.

- V1 health JSON with `healthy: true` is V1. `healthy: false` is not connected. HTML and empty 500 are not V1. `/api/info` with `version` is V2. 401 does not continue.
- Session `{"id":"ses_1","projectID":"prj_1","location":{"directory":"/repo"},"time":{"created":1,"updated":2}}` maps to `Session` with `slug` `ses_1`, `directory` `/repo`, `title` `Untitled`, `version` `2`.
- Message `{"data":[]}` is empty. A user item `{"id":"msg_1","type":"user","text":"hi","time":{"created":1}}` becomes one text part. An assistant item with `content:[{"type":"text","text":"ok"}]` becomes one text part. An `idle` item is skipped.
- V2 prompt encode for text is `{"text":"hi"}`. V2 prompt encode for one image is `{"text":"hi","files":[{"uri":"data:image/png;base64,aGVsbG8=","name":"a.png"}]}`. V1 encode still has `parts`.
- Prompt status 204 throws on V2. Interrupt `{"interrupted":false}` at 200 succeeds. Title patch is not decoded.
- Archive overlay: server session without `time.archived`, local map `{"ses_1": 5}`, mapped session is archived. Restore removes the key.
- Permission `{"id":"per_1","sessionID":"ses_1","action":"read","resources":["*.env"],"source":{"type":"tool","messageID":"msg_1","id":"call_1"}}` maps to `permission` `read`, `patterns` `["*.env"]`, `tool.callID` `call_1`. Reply encode is `{"decision":"once"}`.
- Form `{"id":"frm_1","sessionID":"ses_1","title":"Pick","fields":[{"key":"color","type":"string","options":[{"value":"red","label":"Red"}]}]}` maps to one question whose header is `color` and whose selected label `Red` replies as `{"answer":{"color":"red"}}`.
- Model `{"id":"gpt-5","providerID":"openai","name":"GPT","capabilities":{"tools":true,"input":["text","image"],"output":["text"]},"limit":{"context":8,"output":2}}` becomes a provider model with `toolCall` true and attachment true.
- Project `{"id":"prj_1","canonical":"/repo","time":{"created":1,"updated":2,"active":3},"sandboxes":[]}` has `worktree` `/repo`.
- Diff `{"file":"a.swift","patch":"+let x","additions":1,"deletions":0,"status":"added"}` has `after` `+let x` and `before` `""`.
- File status `{"file":"a.swift","additions":1,"deletions":0,"status":"modified"}` has `path` `a.swift`.
- Todo walk input is an assistant message `{"id":"msg_a","type":"assistant","time":{"created":1},"agent":"build","model":{"id":"m","providerID":"p"},"content":[{"type":"tool","id":"call_1","name":"other","state":{"status":"completed","input":{"todos":[{"content":"a","status":"pending","priority":"high","id":"t1"}]},"content":[{"type":"text","text":"ok"}]}}]}`. The walk yields one `TodoItem` with id `t1`. A later assistant with no such array does not replace it, because the walk stops at the first match from the end. A list with no such part stores `[]`.
- SSE `data` `{"sessionID":"ses_1","assistantMessageID":"msg_1","ordinal":0,"delta":"hi"}` on `session.text.delta` becomes part id `msg_1-text-0` and field `text`. `ordinal` is that integer field, not an invented counter.
- Structured fixture text is `{"version":1,"status":"completed","speech":"Done","confirmation":null,"clientActions":[]}`. Decode it as `CarResponseEnvelope`, set `Message.structured`, and set `time.completed` when the server omitted it and the session is idle. Text `not json` throws `CarModeError.invalidResponse`.

## What not to do

Do not ship a proxy. Do not fork the app. Do not send `parts`, `mime`, `source`, or `format` to V2. Do not decode a 204 body. Do not call `/session/status`, `/todo`, `/question`, or `/api/project/current` on a V2 host. Do not drop archive, todos, questions, images, or Car Mode because the old route is gone.
