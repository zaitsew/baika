# App Intents and Shortcuts

Baika is an iPhone-only app with generated audio. No AI directory (Claude connectors, ChatGPT
plugins, Gemini Connected Apps) takes a listing for that, so its AI integration is App Intents:
Siri, Shortcuts, Spotlight and the Action button can start it. Roadmap:
`zaitsew/ops` → `startup/ai-integrations/ROADMAP.md`.

| intent | phrase (Siri) | what it does |
|---|---|---|
| `TellStoryIntent` | "Tell me a story with Baika" | Siri asks "What should the story be about?"; the Shortcuts action also takes a style ("Dovlatov", "в стиле Жванецкого", "a noir detective"). Opens Perform and starts writing and narrating. |
| `ReplayLastStoryIntent` | "Replay my last story in Baika" | Opens the newest story and plays it from the start, from files on the phone. |
| `ContinueStoryIntent` | "Continue the story in Baika" | A paused story plays on. Otherwise the next part of the newest story is written in its style, language and voice, and narrated. |

Code: `App/Intents/BaikaIntents.swift` (intents and phrases), `App/Library/AppModel+Intents.swift`
(what each does), `StyleCatalog.choice(forSpoken:)` and `StoryContinuation` in BaikaKit (tested).
Russian phrases and dialogs: `AppShortcuts.xcstrings`, `Localizable.xcstrings`.

## How a request travels

An intent runs in the app process with `supportedModes = .foreground`, so the app opens first.
It sets `AppModel.shared.pendingStory` (or `requestedStoryID`) and `requestedTab`. The views
follow: `PerformView` takes the pending story and tells it, `LibraryView` opens the story page.
A request waits while the person is signed out and expires after ten minutes.

## Rules these intents keep

- **Consent is not skipped.** The first story from an intent shows the AI consent sheet (5.1.2(i)).
  Signed out, the sign-in screen shows first.
- **No new network call.** Intents use the same hub calls as Perform. The privacy policy is unchanged.
- **Free text is bounded.** Topic 600 characters, style 120 with brackets and newlines removed,
  as in the form. The earlier story is passed to the model as text to continue, not instructions.
- **Busy stage:** a request that arrives while a story is being told is dropped; the dialog still
  speaks, because the intent cannot see the stage.

## Not done

- A phrase cannot hold free text, so "tell me a story about X in the style of Y" in one sentence
  works only where the action takes parameters (Shortcuts, Apple Intelligence actions).
- Intents need the phone unlocked: they open the app. Hands-free background playback would need a
  separate audio path and a device test.
- The Shortcuts parameter summary is English only.
- Not exercised on a device. `swift test` covers style matching and the continuation prompt.
