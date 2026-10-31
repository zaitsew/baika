# Baika roadmap

The owner's words this serves (2026-10-23, verbatim):

> I wanna have ElevenLabs + Chatgpt realtime voice conversation + maybe video
> generation - so I could ask "расскажи мне историю Канарских остравов в стиле
> Жванецкого". Now chatgpt is good in generating text, but not in voiceover and AI
> video generation.

And, from the Loco voice feedback (2026-10-15), which applies to Talk:

> It doesn't have mute button like in ChatGPT voice conversation [...] not pulsing
> big button showing that Loco is listening to me.

## Shape

One storyteller, three modes.

| mode | what you get | engine | cost per use (third-party figures) |
|---|---|---|---|
| Talk | live voice conversation: ask, interrupt, steer | GPT-Live / GPT-Realtime-2.1 via the accounts hub | $0.06–0.11 per minute |
| Perform | a 3–5 minute story in the requested style, narrated | script: Claude via hub `/ai`; voice: ElevenLabs v3 via hub `/ai/narrate` | ~$0.25 per 3-minute story |
| Film | the story as a captioned vertical video | stills with camera moves + 3–4 generated clips, assembled on device | ~$1–3 per story |

Talk hands off to Perform: "расскажи это целиком" turns the conversation topic into
a performed story.

Styles imitate an author's text, never a real person's voice. Voices are ElevenLabs
library or designed voices. ElevenLabs forbids cloning a voice without consent.

## Sprint 1 — Talk + Perform (iPhone)

- Hub: product `baika`, usage caps, and `POST /ai/narrate` (ElevenLabs). Until the
  ElevenLabs key is set, Perform falls back to hub `/ai/tts` (OpenAI voice).
- App: sign in through the accounts hub, Perform screen (topic + style + voice),
  streamed script, narrated playback with lock-screen controls, saved stories library.
- App: Talk screen ported from Loco's live voice, with a mute button, a pulsing
  listening state and icon controls. Built; never run on a device (a live session needs
  the owner's iPhone and a signed-in account).
- TestFlight internal build on the owner's iPhone.

## Sprint 2 — Film

- Scene cut of the script, one image prompt per scene, generated stills.
- 3–4 short generated clips at key moments (Veo 3.1 Lite or Kling; picked by a
  measured comparison).
- On-device assembly from Lumi's `FilmRenderer` (AVMutableComposition), burned-in
  captions, export to Photos and share sheet.

## Later

- ElevenLabs voice for Talk (ElevenLabs Agents with Claude as the model) if the
  GPT-Live voice stays the weak point.
- Story languages: Russian, English, Spanish.
- Loco link: a story about the place you are in, from the current trip.

## Not decided

- ElevenLabs paid plan. Development runs on the free tier (10,000 credits a month,
  non-commercial). A paid plan needs the owner's double yes (POLICY §11).
