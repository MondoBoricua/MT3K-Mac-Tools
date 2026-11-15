# Changelog

## 1.2 — 2026-11-15

### New
- **Search all of Homebrew.** The catalog search also finds casks and formulae outside the curated list and installs them with the same queue, log and Terminal hand-off.
- **New version notice.** The sidebar tells you when a newer release is out (one anonymous check per day; switch it off in Settings). The app never downloads or installs anything by itself.
- **Confirm before deleting.** Cache, log, DerivedData and Trash cleanups show what will be freed and ask first.
- Presets list their apps on hover.

### Performance
- The Apps pane no longer rebuilds its 172 rows and checks the disk for each one on every refresh: idle CPU with the pane open dropped from about 6 % to about 1.5 %.

### Fixes
- The install queue skips command-line tools Homebrew already has instead of running `brew install` again.
- Flow: "Translate" with the OpenAI provider uses the model its translation endpoint accepts.
- Install output kept in memory during long installs is capped.

### Maintenance
- `tools/audit_catalog.py` and a weekly workflow check that every catalog entry still exists and is not deprecated.

## 1.1.1 — 2026-11-15

### Fixes
- Stats and the menu bar popover show the real battery cycle count (it read 0 on recent macOS) and no longer say "charging" while the charge is paused at the limit.

## 1.1 — 2026-11-15

### Catalog
- Removed entries Homebrew disabled or discontinued: Arc, ChatGPT Atlas, OWASP ZAP, Messenger, Codex Desktop and the Gemini CLI formula.
- Windsurf is now Devin Desktop; the three Affinity 2 apps are replaced by the single Affinity app; Kimi CLI is now Kimi Code; the Pencil CLI moved to `@pen.dev/cli`; Python is 3.14.
- Fixed installed-app detection for Burp Suite and Krita.
- Little Snitch and LuLu install in-app instead of handing off to Terminal.
- Suggested Ollama models point at tags that exist in the registry.

### Performance
- The menu bar no longer keeps a full refresh running after its popover closes, and refreshes never stack.
- One shared sampler feeds the menu bar and the Stats pane; CPU, memory, swap, load, uptime, thermal state and memory pressure are read natively instead of launching processes.
- The Homebrew update badge checks at most every 15 minutes, or right after an install or upgrade.
- The System pane no longer launches every check at once; folder sizes load afterwards in the background.

### Battery Guard
- The privileged helper is the single owner of the charge limit; the app keeps its settings in sync with it, including after a helper reinstall.
- Limit and resume sliders apply without pressing "Apply".

### Flow
- The OpenAI provider defaults to `gpt-transcribe` (the previous default is being retired by OpenAI).
- Local transcription uses WhisperKit 1.1.
- The local model is no longer downloaded at launch while Flow is switched off.

### Fixes
- The Stats pane now reports the real thermal state on Apple Silicon.
- Homebrew detection can no longer hang on large output.
- The sidebar shows the actual app version.

## 1.0 — 2026-07-04

Initial open-source release.
