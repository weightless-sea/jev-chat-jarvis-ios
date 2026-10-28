# jev-chat-jarvis (iOS · Keyboard)

![Swift](https://img.shields.io/badge/Swift-5+-F05138.svg)
![Platform](https://img.shields.io/badge/platform-iOS%2016+-lightgrey.svg)
![Version](https://img.shields.io/badge/version-0.2.0-orange.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)

[中文](README.md) | English

You receive a message in a chat app → the **intent**, **risk**, and **reply suggestions** appear right on the keyboard inside that app. Tap once and the reply lands in the input field.

No app switching, no background capture — **one custom keyboard that works in every chat app**, in any input field. Too lazy to copy? Turn on **Live Mode** (optional): a broadcast extension reads the screen with on-device OCR and the keyboard offers a one-tap "Read screen" analysis — no long-pressing, no clipboard.

<p align="center">
  <img src="docs/demo.gif" alt="Live demo: long-press to copy a message → the keyboard shows intent/risk/suggestions → tap to insert" width="320">&nbsp;&nbsp;
  <img src="docs/setup.gif" alt="App setup demo: keyboard status checks, three-step enablement, built-in tone library" width="320">
</p>

The app and keyboard support **Chinese and English**. Switch languages on the **Home** tab of Jev Jarvis; the choice is shared with the keyboard through the App Group and takes effect on its next render.

## Usage

### 1. Install on your iPhone

1. Open `JevJarvis.xcodeproj` on a Mac (Xcode 15+; this repo is verified with Xcode 27)
2. Select the **JevJarvis** target → Signing & Capabilities → choose your Apple ID as the Team (a free personal account works; add it in Xcode → Settings → Accounts)
3. Plug in your iPhone, select it as the run destination, and press `Cmd+R`. On first run, trust the developer certificate on the phone: Settings → General → VPN & Device Management
4. Both targets (**JevJarvis** and **JevKeyboard**) must use the **same Team**, otherwise the App Group sharing breaks

> Signatures from a free personal account expire after 7 days; just `Cmd+R` again to renew.

### 2. Enable the keyboard (on the iPhone)

1. Settings → General → Keyboard → Keyboards → **Add New Keyboard** → pick **Jev Keyboard**
2. Back in the keyboard list, tap **Jev Keyboard** → turn on **Allow Full Access** (required for network + clipboard)
3. Open the Jev Jarvis app → **Models** tab: pick a preset, enter your API key, tap **Test connection**
4. Run one message on the **Try it** tab — if it passes, everything works

### 3. Use it in a chat app

1. Long-press the incoming message → **Copy**
2. Focus the input field, switch to Jev (globe key) → tap **Analyze Clipboard**
3. The keyboard shows: intent + risk 0-9 + suggested actions + 2 candidates per tone (first safe, second bolder)
4. Tap the candidate you like → the text goes straight into the input field → **sending is always manual** (this project never auto-sends)

There is also an **Analyze input text** button for drafts you are unsure about (reads `documentContextBeforeInput`).

### 4. Live Mode (copy-free, optional)

Don't want to long-press-copy every message? On the app's **Live** tab tap the system broadcast button → pick **Jev Live** → Start Broadcast:

1. The broadcast upload extension (`JevLive`) samples one frame every 2 seconds and runs **on-device Vision OCR** (accurate tier, Chinese), splits bubbles into "them / me" by horizontal position, and strips timestamps and bottom-bar UI. **Conversation gating included**: recognition only produces content when both sides' bubbles are visible (a real chat); switch to Settings/Photos and nothing is recognized (iOS exposes no "current foreground app" API, so a per-app allow-list is impossible — this is the strongest approximation)
2. The snapshot goes into the App Group: the Live tab reconstructs the conversation in real time, and the idle keyboard lights up a "Read screen: '…their latest message…'" button plus an "Earlier" list — the extension watches while you scroll through chat history, so older messages can be picked too. Tap once for candidates, no clipboard involved
3. OCR happens entirely on-device; only when you trigger an analysis does the recognized text go to the model endpoint you configured. iOS shows the purple recording indicator the whole time; stop from Control Center

See [`docs/LIVE_MODE.md`](docs/LIVE_MODE.md) for details and device test steps. Note: the broadcast sheet is system UI — it **only responds to a real user tap on a real device** (it never appears in the Simulator).

## Configuration

Everything is configured inside the app; changes save immediately and the keyboard picks them up without a restart:

- **Generation layer (required)**: choose an OpenAI-compatible (`/chat/completions`) or Anthropic-compatible (`/v1/messages`) service and enter your own API key and model. This project provides **no** generation service or relay. URLs work with or without `/v1`, up to the action segment; extra JSON fields are supported. **Avoid reasoning models** — thinking consumes the whole budget and yields 0 candidates (the error message will name the model).
- **Judge layer (core)**: TypeSafe Jev (systemone endpoint). One call returns an 8-class intent distribution + a 0-9 risk distribution, and ranks the candidates. Presets for TypeSafe direct, OpenRouter, and Vercel AI Gateway are built in; gateway URL, model, and key are all configurable. Without a key the pipeline automatically degrades to blind drafting (candidates only) — a runtime fallback, not a setting.
- **Tones**: up to two active slots on iOS, twelve built-in tones, plus custom ones (descriptions work best as "what the tone is + what to avoid"). One request per tone, two candidates each, requests run concurrently.

### Privacy boundary

- Chat content is sent **only** to the model endpoint **you** configured, at the moment you tap Analyze; no self-hosted server, no storage, no logs
- The API key lives in the private App Group container, readable only by the app and the keyboard
- The keyboard does not monitor or upload keystrokes; Full Access can be revoked or the keyboard removed in system settings at any time

## Regression checks

The `Shared/` directory is the single source of truth shared by the app and the keyboard: intent set, risk scale, action advice, tone library, drafting prompts, candidate cleaning, and URL-joining rules exist only there, so both sides always behave the same.

Run the regression checks on a Mac (no iPhone needed):

```bash
swiftc -o /tmp/jevcheck tools/PromptCheck/main.swift Shared/*.swift && /tmp/jevcheck
```

Unsigned build check (no certificate needed):

```bash
xcodegen generate
xcodebuild -project JevJarvis.xcodeproj -target JevJarvis -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

UI regression (launch smoke, tab traversal, keyboard enablement) and App Store screenshot capture live in `UITests/` and run via the `JevJarvis` scheme with an iPhone simulator selected.

## Project structure

```
├── project.yml            # xcodegen project definition (run `xcodegen generate` after edits)
├── AGENTS.md              # repository guidelines (style / commits / security)
├── Shared/                # single source of truth shared by app + keyboard (Foundation only, no UI)
│   ├── JevModel.swift     # config model + App Group storage
│   ├── JevLocalization.swift # Chinese/English copy and intent/risk/action localization
│   ├── JevPrompts.swift   # intents/risk scale/tones/prompts/candidate cleaning
│   ├── JevHTTP.swift      # budgeted POST (429/5xx backoff retry)
│   ├── JevJudge.swift     # TypeSafe systemone: judging + ranking
│   ├── JevDraft.swift     # OpenAI/Anthropic drafting
│   └── JevPipeline.swift  # judge → concurrent per-tone drafting → ranking
├── App/Sources/           # SwiftUI: Home (keyboard status) / Models / Tones / Live / Try it
├── App/Assets.xcassets/   # AppIcon (edit via tools/MakeAppIcon, never the PNGs)
├── Keyboard/Sources/      # UIKit keyboard extension (system controls only, <60MB memory)
├── Broadcast/Sources/     # ReplayKit broadcast upload extension (screen → local OCR, sized for the 50MB cap)
├── Shared/JevLive.swift   # Live-mode shared layer: snapshot model / App Group store / OCR engine / chat parser
├── UITests/               # XCUITest: launch/tab/keyboard regression + store screenshot capture + live device flow
├── marketing/app-store-upload/  # App Store screenshots (source captures + npm script)
└── tools/
    ├── PromptCheck/       # regression checks
    ├── live_ocr_smoke.swift  # live OCR pipeline smoke test (runs on Mac, no iPhone needed)
    └── MakeAppIcon/       # renders the AppIcon: swiftc -O -o /tmp/makeappicon tools/MakeAppIcon/main.swift && /tmp/makeappicon App/Assets.xcassets/AppIcon.appiconset
```

## Known limitations

- **Copied messages carry no context**: the clipboard usually holds just that one line. If your chat app supports copying quoted text, the quote rides along; for automatic context use Live Mode
- Fixed keyboard height of 320pt; the candidate list scrolls when long; landscape is not adapted
- The App Group requires both targets signed with the same Team; free personal accounts usually work, occasionally a paid account is needed
- Secure inputs (password fields) force the system keyboard (system behavior, not a bug)
- Keyboards signed with a free account expire after 7 days and need a reinstall
- Live Mode: the broadcast sheet only responds to a real user tap on a real device (never in the Simulator); left/right attribution is a horizontal-position heuristic (quote blocks and group chats can mis-assign); recognition runs every 2 seconds, not a word-by-word live caption

## Roadmap

1. **Automatic sensing**: Live Mode (ReplayKit broadcast + on-device OCR) has landed with the keyboard exit; next up: auto-candidates for new messages while the keyboard is open (with a toggle, to avoid burning tokens) and group-chat sender disambiguation
2. Full QWERTY inside the keyboard (type without switching)
3. Group-chat adaptation (`@` prefix), knowledge base (contact profiles / standing notes)
4. Scheduled re-signing / TestFlight distribution — the full workflow with a borrowed developer account is in [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md)

## License

Copyright © 2026 eatmoreduck, Xlff, and jev-chat contributors. Code is open-sourced under the [MIT](LICENSE) license; see also [NOTICE](NOTICE).

- **Commercial use allowed**: individuals and companies may use, modify, and redistribute without payment or prior authorization
- **Attribution required**: keep `LICENSE` and `NOTICE` when distributing, and state the source
- **Do not** use the names 「秒回」「Jev 聊天助手」「jev-chat」「jev-jarvis-ios」 to imply endorsement by the original authors
- **Legitimate use only**: this project assists your own sincere everyday communication. It must not be used for anything unlawful — including but not limited to fraud (romance/investment scams, elder fraud), impersonation, harassment, or spam marketing
- **Disclaimer**: provided "as is"; the authors are not involved in, aware of, or responsible for any specific usage. It only processes chats on your own device that you are entitled to see, and candidates are only inserted into the input field — **never sent automatically**
- Full risk disclosure: [Usage statement & risk notice](https://github.com/jev-chat/jev-chat-jarvis-ios/issues/2)

## Manual keyboard configuration for sideloaded builds

If the app connection test succeeds but a re-signed keyboard is unconfigured, enable Full Access, open **Models → Copy Config to Keyboard**, then tap **Import Config** in the Jev keyboard within two minutes. Allow Paste if prompted. Do not paste configuration into a chat field. After import, copy the chat message again and analyze it.

The keyboard saves its own copy of generation/judge credentials, tones and language without App Group. Repeat the transfer after changes in the app. Keyboard tone edits affect only its local copy. **Clear Local Config** deletes that copy and restores App Group reads. Without App Group, the main app cannot report keyboard status.

The transfer includes API keys, is not encrypted, uses a custom non-text clipboard type, stays on this device and expires after two minutes. Successful import clears it. Do not share configuration. The signing tool must still retain the keyboard extension, and Full Access is still required.
