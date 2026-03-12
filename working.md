# Working Notes - OpenCode iOS Client

## 2026-03-12

- Added real image previews for Files and tool-call outputs instead of showing raw base64 text.
- Polished the image viewer: fit-to-screen by default, pinch/drag, double-tap zoom, and Photos save support from the share sheet.
- Rewrote `README.md` for open-source users and added the TestFlight install path.
- Updated chat auto-scroll so it only follows new content when the user is already at the bottom; scrolling up pauses follow mode.
- Refreshed the PRD and RFC to match the current app: question cards, image previews, current model presets, install path, and chat behavior.

## 2026-03-11

- Fixed speech transcription so empty drafts no longer get a leading space.
- Stabilized chat auto-scroll during streaming to avoid overshooting into blank space.

## 2026-03-07

- Implemented the Question feature so server-initiated `question` prompts render as interactive cards and the session can continue.
