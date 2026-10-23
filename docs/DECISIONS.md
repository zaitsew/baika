# Decisions

An ADR log. One entry per decision that would otherwise be re-litigated —
not every choice, just the ones somebody will ask "wait, why did we do it
this way" about later.

## 2026-01-01 — example: this is the format

**Context.** What made a decision necessary — the fork in the road, in a
sentence or two.

**Decision.** What was chosen.

**Why.** The reasoning, short. Not a transcript of the debate — the part
worth remembering.

**Status.** Accepted | Superseded by <link> | Reverted on <date>, because <why>.

## 2026-10-23 — Opus writes the script, narration is chunked

**Context.** Perform needs a story text and a voice. Quality of the text is the product;
ElevenLabs takes at most 3,000 characters a request.

**Decision.** The script uses `claude-opus-5-5` with a fall back to `claude-sonnet-5-5` before
the first byte. Narration runs in chunks of at most 2,500 characters, the first about 900, one
chunk prefetched ahead of playback, each with 300 characters of context on both sides.

**Why.** A short first chunk starts the voice early. One chunk of lookahead hides latency and
does not pay for audio a person never plays. The context keeps intonation continuous across cuts.

**Status.** Accepted.

## 2026-10-23 — Voices are library voices, styles are text manners

**Decision.** Six ElevenLabs premade voices. Styles imitate an author's devices in the text, in
our own words; they never copy a text and never name a real person's voice.

**Why.** ElevenLabs forbids cloning a voice without consent, and the stores reject
impersonation.

**Status.** Accepted.

## 2026-10-23 — Own sign-in screen

**Decision.** The sign-in screen is drawn in Baika's theme over `AccountsClient` (Apple, email
and password, email link). The kit's `SignInView` is not used.

**Why.** The kit's screen is English only and uses system colours; Baika is Russian first and
dark. Google sign-in is left out until the hub's OAuth redirect is set for `baika://`.

**Status.** Accepted.
