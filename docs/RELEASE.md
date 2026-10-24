# Release — baika

## TestFlight and the App Store

Go through the App Store Connect API key. **Never** a password, never the
Xcode GUI, never an app-specific password.

```
~/ops/bin/testflight release --project Baika.xcodeproj --scheme Baika \
    --bundle-id com.zaitsew.baika
```

Credentials live once, in `~/.appstoreconnect/`: `config.env` holds the key
id, issuer id and team id (identifiers, not secrets), and
`private_keys/*.p8` is the secret, mode 600 — never print it, never copy it
into this repo. Any agent may cut a release with it; none of it requires
the account holder at the keyboard.

A new machine, or "no signing certificate found", needs

```
~/ops/bin/testflight bootstrap --bundle-id com.zaitsew.baika
```

once. If the team cannot use cloud-managed distribution certificates, the
certificate is minted through the REST API with its private key kept local,
and signing is manual. Don't run bootstrap by habit — a second run mints a
second certificate, and Apple allows few.

## App Store Connect record

| field | value |
|---|---|
| app id | 6826532153 |
| store name | Baika |
| SKU | `baika` |
| bundle id | `com.zaitsew.baika` (App ID resource GGG3WKASAT, Sign in with Apple on) |
| primary language | English (U.S.) |
| user access | Full Access |
| availability | 174 of 175 territories; China mainland (`CHN`) off |

Created 2026-10-24 in the App Store Connect website (Apple's API cannot create apps).
`scripts/store.py availability` checks the China rule and `--apply` restores it;
`scripts/store.py listing` fails when a store or TestFlight text names a model provider.

## Still open before a public release

- Hub side: `ai/narrate` needs `ELEVENLABS_API_KEY` set on the accounts project
  (without it Perform uses the backup voice).
- Store listing: no model provider named in the name, subtitle, description, keywords or
  screenshots. The privacy policy and the in-app AI consent still name Anthropic, ElevenLabs and
  OpenAI. Support and privacy URLs must be live. App Privacy: email, user id and user content,
  linked to the user, for app functionality; no tracking.
- Review information: a demo account on a plan that unlocks everything; note that stories are
  AI-generated, where Perform and Library are, and why China is excluded.
- Screenshots for the 6.9-inch iPhone class (the app is iPhone-only).

## Public beta (TestFlight)

1. Ship a build through the release command above.
2. Fill in the beta app review questionnaire in full (age rating included —
   a partial submission gets bounced) before requesting public review.
3. Wait for Apple's beta app review to clear the build for public
   TestFlight — this is separate from, and slower than, internal testing.
4. Share the public link once review clears. Internal testers never need
   this step; they see new builds immediately.

## Before every submission

Run the store-review checklist in the owner's POLICY ("Store review — pass the first
time"): China mainland excluded in availability, no model provider named in the listing,
a demo account in the review information, every declared capability reachable by a
signed-out reviewer, screenshots for every supported device class. A rejection's reason is
only on the App Store Connect App Review page; record it under "Review history" below.

## Review history

| Date | Version (build) | Verdict | Guideline · reason · fix |
|---|---|---|---|

## What never happens here

No password typed into Xcode, no app-specific password, no manual upload
through the Xcode Organizer. If the release command fails on an expired
Xcode session or similar, fix the credential path — don't fall back to the
GUI.
