# opencode_ios_client local notes

## Folder structure

- `OpenCodeClient/` — the only shipped app tree (Xcode project lives here).
- `docs/` — PRD/RFC/working notes; not runtime code.
- `scripts/` — small Python helpers; use `.venv/` locally (gitignored).
- `opencode-official/` — optional upstream OpenCode server checkout for integration work (gitignored, not required to build the app).

Do not add sibling app targets or duplicate client trees at repo root. Server-side patches belong in `opencode-official/` or upstream, not in this repo.

## Build/test

- `xcodebuild build` and `xcodebuild test` must run **sequentially**, not in parallel, because this repo shares the same DerivedData/build database and concurrent runs commonly fail with `build.db: database is locked`.
- If you need both validations, run build first, wait for it to finish, then run tests.
- Keep chat input UI tests anchored on stable accessibility identifiers rather than `TextField`-specific queries, because the composer implementation may use UIKit bridges.
- In `opencode-official`, the working upstream for "latest code" is `origin/dev`, not `master`.
- In this workspace, when the user says "用最新的 code 编译", the default meaning is: fetch `origin/dev`, rebase the current local integration branch on top of it while preserving local commits, then build/test/deploy from that rebased state.
- Here, "local commits" means commits that already exist on the current branch but are not yet integrated onto the latest `origin/dev`; it does not include uncommitted working tree changes.
- Only skip the rebase step if the user explicitly says to build pure upstream code without local commits.
- If the rebase fails or hits conflicts, stop there and ask before continuing to build/test/deploy.
- Success criterion for this workflow: after the rebuild, launching OpenCode from `knowledge_working` must use the freshly built binary from this rebased state, not an older binary left on disk.
- When the user is actively using an existing OpenCode server, do not kill or restart the live process, especially anything bound to port `4096`.
- In that situation, skip destructive runtime validation against the live server; if runtime verification is still needed, use a separate temporary port/process and never touch the user's active `4096` process.
