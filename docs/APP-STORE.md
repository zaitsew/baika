# App Store review log — baika

Rejections and upload refusals, newest first. Each entry has the code or guideline, the
reason text verbatim, the cause and the fix. The checklist they feed is POLICY section 15.

## ITMS-90626: Invalid Siri Support (upload refusal, 2026-10-29)

- **Build:** 0.1.0 (2). Refused by e-mail from App Store Connect at 16:07; never processed.
- **Reason, verbatim:** "ITMS-90626: Invalid Siri Support - App Intent description 'Play your
  newest story again from the start. It plays from this iPhone, without a connection.' cannot
  contain 'iphone'".
- **Cause:** the description of `ReplayLastStoryIntent` named the device. Apple scans the
  App Intent metadata at upload and refuses device and product names in it. A second string, the
  dialog "Part of the audio for %@ is not on this iPhone. I opened it.", had the same fault; the
  upload check named only the first.
- **Fix:** the description is now "Play your newest story again from the start. It plays
  offline." and the dialog "Part of the audio for %@ is not downloaded yet. I opened it." The
  Russian values changed with them. `Tests/BaikaKitTests/IntentCopyTests.swift` fails when a string
  literal in `App/Intents/` contains iphone, ipad, apple watch, siri or apple as a whole word,
  ignoring case. Shipped as build 3.
- **Rule:** App Intent titles, descriptions, dialogs, parameter titles and AppShortcut phrases never
  name a device or an Apple product. Say "offline" or "downloaded", not "on this iPhone".
