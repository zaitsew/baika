# baika

Ask for a story in a voice and a style ("tell me the history of the Canary Islands the way Zhvanetsky would"). Baika writes it, performs it with an expressive voice, and lets you talk back.

## Quick start

```
git clone <this repo>
cd baika
cp .env.example .env   # fill in whatever it lists
./check.sh             # tells you what's still missing
```

## Status

Alpha, sprint 1 in progress: Talk (live voice conversation) and Perform (a narrated story). Film (generated video) is sprint 2.

## What it does / doesn't

- Does: writes a story in the requested style, narrates it with an expressive voice, and holds a live voice conversation about it.
- Doesn't: clone a real person's voice. A style is imitated in the text; voices are original designs.

## Setup (env)

See `.env.example` for the full list. `./check.sh` prints which of these are
still unset, so it doubles as living documentation — keep the example file
current instead of duplicating the list here.

## Routines

| routine | cadence | what it produces |
|---|---|---|
| (none yet — copy `routines/example.yml`) | | |

## Licence

See `LICENSE`.
