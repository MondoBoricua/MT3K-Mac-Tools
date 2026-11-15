# Changelog

## Unreleased

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
