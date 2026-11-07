# Store listing draft — Baika

Draft for the next submission. Nothing is submitted: the seller-account submission hold is in
force (POLICY section 14). App Store Connect record: "Baika", id 6826532153 (`docs/RELEASE.md`).
Last build the owner tested: 0.1.0 (3). English only; the repo keeps Russian strings for the app UI,
not for the listing.

TODO(ru): write the Russian listing by hand, not by translation.

Rules applied (`~/.agents/policy/stores.md` section B): no model provider in any field; no device or
Apple product names where Shortcuts is described; China mainland excluded in availability.

## Name (30 max)

Baika

## Subtitle (30 max)

Stories told in a voice you pick

## Promotional text (170 max)

Ask for a story on any topic, in the manner of a classic author or your own style. Baika writes it, reads it aloud, and keeps it in your library to replay offline.

## Description (4000 max)

Ask for a story. Baika writes it and tells it to you.

Pick a topic, type it or dictate it. Choose a style: the dry irony of a Soviet satirist, a documentary narrator, a bedtime story, or describe your own. Choose 2, 4 or 7 minutes, a language (Russian, English or Spanish) and one of six narrator voices. The text streams in, and narration starts as soon as the first part is voiced.

PLAY IT YOUR WAY
- Background audio and lock-screen controls
- Back and forward 15 seconds
- Pause a story and carry on later

YOUR LIBRARY
- Every story and its audio stay on your phone
- Replay offline, with no connection
- Share the text, or the audio as one file

SHORTCUTS
- Tell a story: give a topic and a style
- Replay your last story
- Continue the story: the next part, in the same style, language and voice
Use them from Shortcuts, Spotlight or the Action button.

TALK
Talk about a story out loud and steer it as it goes.

HONEST ABOUT AI
Stories are written and voiced by AI, and may be wrong or odd. A style imitates a manner of writing in the text. It does not clone anyone's voice. You are asked for consent before the first story is sent for writing and narration.

Sign in with Apple, email or a link.

## Keywords (100 max, App Store only)

story,audio,narrator,tales,bedtime,listen,storyteller,voice,read aloud,fiction,shortcuts,offline

(97 characters. Author names are left out on purpose: real names in metadata invite an IP query.)

## What's New (next version)

Since build 1, the changes a tester would notice:
- Shortcuts: tell a story, replay your last story, or continue it, with a topic and style you choose.
- Continue picks up a paused story, or writes the next part in the same style, language and voice.
- A saved custom style that is empty now falls back to the default style instead of failing.

## Screenshots to retake

Newest committed screenshots: `docs/screenshots/perform.png`, `sign-in.png` (3431f87, 2026-10-23).
No screen UI changed since: the intents added no screen of their own (`git log 28fd61c..` over `App/`
shows only intents and a fallback fix).
- Library and a story page with playback: not in the repo, take them.
- Talk: not in the repo, take it once Talk is checked on a device.
- Shortcuts action with the topic and style parameters: take it in the Shortcuts app.
- All shots at the 6.9-inch iPhone size (the app is iPhone-only).
