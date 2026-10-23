# Architecture

## Modules

| module | depends on | holds |
|---|---|---|
| `BaikaKit` | Foundation only | styles, voices, prompt, sanitizer, chunker, audio cache, fallback decision, AI consent, and Talk's pure half (Realtime events, PCM16, transcript, persona, session body, clock, mute gate). All unit-tested. |
| `BaikaAccounts` | BaikaKit, FabriqueAccounts (>= 0.1.7) | `BaikaHub` (URL, key, product), `HubScriptBackend` (script stream), `HubAudioClient` (narration), `HubRealtimeClient` (Talk's client secret). |
| `App/` | both | SwiftUI, SwiftData `Story`, `NarrationPlayer`, `PerformModel`, `TalkSession`, `TalkAudio`. |

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

## How a conversation flows (Talk)

1. Tap Talk: stop the story player, ask for the microphone, start `TalkAudio` (`.playAndRecord`,
   `.voiceChat`, speaker by default, voice processing for echo). Audio that cannot start costs
   no session.
2. `POST {hub}/functions/v1/ai/realtime` with `{product: "baika", minutes: 10, session: {...}}`
   returns OpenAI's `{value, expires_at, session}`. The persona (`TalkPersona`, in the chosen
   style and story language) is the session's `instructions`; the voice is `cedar`; server VAD
   with `interrupt_response` and 600 ms of silence; reasoning effort low. The secret opens a
   session for two minutes, so it is minted right before the socket.
3. WebSocket to `wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1`, bearer = the secret.
   The hub is not on the socket. The microphone goes up as 100 ms frames of 24 kHz PCM16.
4. On `speech_started` the queued audio is dropped and `conversation.item.truncate` tells the
   server how much of the answer was heard.
5. Mute keeps the session and the clock alive: one second of zeroed frames goes up so the server
   ends the turn, then nothing.
6. At ten minutes the session ends and Continue mints a new one, whose instructions carry the last
   1,500 characters of the transcript. Leaving the tab or the app ends a session.
7. "Perform this" puts the person's lines (newest 600 characters) and the style in the Perform
   form and switches tabs; the person reads the topic and taps Tell.

## Hub contract (assumptions to confirm on the hub)

- Bearer: the signed-in person's Supabase access token, read from
  `accounts.supabase.auth.session.accessToken` at call time (the SDK refreshes it).
- `POST {hub}/functions/v1/ai/narrate`: `{product, input (<= 3000), voice_id, model: "eleven_v3",
  language_code, previous_text, next_text}` returns `audio/mpeg`.
- HTTP 503 `{"error":"provider_unconfigured"}` switches the rest of the story to
  `POST /ai/tts` `{product, input, voice: "marin", instructions, format: "mp3"}` and the stage
  shows "Narrated with the backup voice". Any other error is shown, not hidden.
- `POST /ai/realtime` `{product, minutes (<= 30), session: {type: "realtime", model:
  "gpt-realtime-2.1", instructions, audio, ...}}` returns `{value, expires_at, session}`
  unchanged from OpenAI. 402 is the monthly budget, shown with the same text as Perform.
- Every request body carries `product: "baika"`; `anon` key in `apikey`.

## Voices

Six ElevenLabs premade voices, ids read from the public voices list on 2026-10-23 (George,
Brian, Bill, Daniel, Lily, Alice). They are English-native and speak Russian and Spanish with an
accent on `eleven_v3`. A voice is chosen by ear on a device, not here.

## Concurrency

Swift 6 strict concurrency. UI models are `@MainActor @Observable`; the engine types are
`Sendable` values. The hub clients are protocols (`NarrationBackend`, `ScriptBackend`) so tests
run without a network.
