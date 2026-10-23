# Baika

Ask for a story in a voice and a style ("the history of the Canary Islands, the way Zhvanetsky would tell it"). Baika writes it with Claude, performs it with an expressive ElevenLabs voice, and keeps it in your library to replay offline.

## Quick start

```
git clone https://github.com/zaitsew/baika && cd baika
brew install xcodegen
./check.sh                      # engine tests + Xcode project + simulator build
open Baika.xcodeproj            # run on an iPhone simulator
```

Sign in with a Fabrique Accounts account (Apple, email or link). The app ships its hub URL and publishable key; there is nothing to configure.

## Status

Alpha. Perform (a narrated story) and the Library work. Talk (live voice conversation) is a placeholder tab. Film (generated video) is later. See `docs/ROADMAP.md`.

## What it does

- Perform: topic (typed or dictated), 8 author styles or your own, 2, 4 or 7 minutes, Russian, English or Spanish, six narrator voices. The script streams in; narration starts after the first part is voiced.
- Playback: background audio, lock-screen controls, back and forward 15 seconds.
- Library: stories and their audio stay on the phone and play offline. Share the text, or the audio as one .m4a.

It does not clone a real person's voice. A style imitates an author's manner in the text; voices are ElevenLabs library voices.

## Layout

| path | what |
|---|---|
| `Sources/BaikaKit` | pure logic: styles, voices, prompt, sanitizer, chunker, audio cache, fallback decision |
| `Sources/BaikaAccounts` | the hub bridge: script stream, `HubAudioClient` |
| `App/` | SwiftUI app: Perform, Library, Talk placeholder, Settings |
| `docs/ARCHITECTURE.md` | how a story flows; the hub contract |
| `docs/RELEASE.md` | TestFlight steps and the store checklist |

## Checks

`./check.sh` is the gate (pre-push hook; no CI on push). `./check.sh quick` runs the package tests only. `./check.sh usage` prints usage counters.

## Licence

See `LICENSE`.
