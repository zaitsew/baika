# Architecture

## Modules

| module | depends on | holds |
|---|---|---|
| `BaikaKit` | Foundation only | styles, voices, prompt, sanitizer, chunker, audio cache, fallback decision, AI consent. All unit-tested. |
| `BaikaAccounts` | BaikaKit, FabriqueAccounts (>= 0.1.7) | `BaikaHub` (URL, key, product), `HubScriptBackend` (script stream), `HubAudioClient` (narration). |
| `App/` | both | SwiftUI, SwiftData `Story`, `NarrationPlayer`, `PerformModel`. |

## How a story flows

1. `PerformModel.tell` builds a `StoryRequest` and streams the script through `ScriptWriter`
   (hub `ai.stream`, model `claude-opus-5-5`; on a model or cap error before the first byte,
   `claude-sonnet-5-5`). The first line is the title.
2. `StoryStream` sanitizes the text as it arrives. The screen shows the readable text; the
   narration keeps the ElevenLabs audio tags.
3. The finished script is saved as a `Story` and cut by `NarrationChunker` into chunks of at
   most 2,500 characters. The first chunk is short (about 900) so the voice starts early. Each
   chunk carries up to 300 characters of `previous_text` and `next_text`, for prosody.
4. Chunk n+1 is requested once chunk n-1 has started playing: one chunk ahead, no more.
   Each mp3 lands in `Application Support/BaikaAudio/<story id>/`.
5. `NarrationPlayer` queues the files in an `AVQueuePlayer` (`.playback` session, Now Playing,
   back and forward 15 seconds). A stored story plays from these files with no network.

## Hub contract (assumptions to confirm on the hub)

- Bearer: the signed-in person's Supabase access token, read from
  `accounts.supabase.auth.session.accessToken` at call time (the SDK refreshes it).
- `POST {hub}/functions/v1/ai/narrate`: `{product, input (<= 3000), voice_id, model: "eleven_v3",
  language_code, previous_text, next_text}` returns `audio/mpeg`.
- HTTP 503 `{"error":"provider_unconfigured"}` switches the rest of the story to
  `POST /ai/tts` `{product, input, voice: "marin", instructions, format: "mp3"}` and the stage
  shows "Narrated with the backup voice". Any other error is shown, not hidden.
- Every request body carries `product: "baika"`; `anon` key in `apikey`.

## Voices

Six ElevenLabs premade voices, ids read from the public voices list on 2026-10-23 (George,
Brian, Bill, Daniel, Lily, Alice). They are English-native and speak Russian and Spanish with an
accent on `eleven_v3`. A voice is chosen by ear on a device, not here.

## Concurrency

Swift 6 strict concurrency. UI models are `@MainActor @Observable`; the engine types are
`Sendable` values. The hub clients are protocols (`NarrationBackend`, `ScriptBackend`) so tests
run without a network.
