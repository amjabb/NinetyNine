# Ninety-Nine

A native iOS card game. Every card you play adds to a shared tally; take it over
99 and you're out. Last player standing wins.

Built from [the 99 rulebook](Docs/RULES.md) and a React Native prototype, rewritten
as a native SwiftUI game.

---

## Run it

```bash
open NinetyNine.xcodeproj
```

Requires Xcode 16+ and iOS 18. Pick any iPhone simulator and press Run.

From the command line:

```bash
xcodebuild test -project NinetyNine.xcodeproj -scheme NinetyNine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Scripts

| Command | What it does |
|---|---|
| `Scripts/screenshots.sh` | Drives the real app and captures App Store screenshots to `Artifacts/screenshots/` |
| `Scripts/archive.sh` | Builds a Release archive (unsigned; pass `--export <TEAM_ID>` for a signed `.ipa`) |
| `swift Tools/make-icon.swift <dir>` | Regenerates the app icon from the design system |

## Tests

```
120 unit tests   engine rules, AI self-play, presentation maths,
                 redaction boundary, action replay determinism
 13 UI flows     real taps through every screen, a full solo game to
                 completion, and a full pass-and-play game through the hand-off
```

Both game modes are verified on iPhone and on a 13" iPad Pro.

The UI tests are not decoration — they found four real bugs that screenshots
alone missed, including a hand fan that overflowed the screen and an
accessibility label that made the hand unusable with VoiceOver. See the commit
history.

## Docs

| | |
|---|---|
| [ARCHITECTURE.md](Docs/ARCHITECTURE.md) | How it's put together and why |
| [DECISIONS.md](Docs/DECISIONS.md) | Scope calls — including why multiplayer was dropped |
| [INTERPRETATIONS.md](Docs/INTERPRETATIONS.md) | The eight places the rulebook needed a judgement call |
| [APP_STORE.md](Docs/APP_STORE.md) | Submission checklist, store copy, and the steps that need your Apple account |
| [RULES.md](Docs/RULES.md) | The original rulebook |

## What's in it

- **Three opponents with distinct personalities** — Casual, Sharp, and Ruthless
  differ in what they value, not in how much they cheat. None of them can see
  your hand.
- **Every card drawn in code.** Real pip layouts on the classic seven-row grid,
  engraved court cards, a guilloche card back. No image assets at all — the
  whole app is 2.9 MB.
- **Procedural audio.** Card flicks, the gong of a nine landing, a tally tick
  that rises in pitch as you approach 99. Synthesised at launch, not sampled.
- **Authored haptics.** A Core Haptics pattern per event rather than three stock
  impact strengths.
- **It teaches itself.** Unplayable cards are dimmed; tap one and it tells you
  exactly why. Every choice shows the tally it would produce.
- **Nothing leaves the device.** No accounts, no analytics, no network code —
  the binary doesn't even link a networking framework.

## Support

Found a bug, or have a question about the game?
**[Open an issue](../../issues)** — that's the fastest way to reach me, and it's
the official support channel for the app.

When reporting a bug it helps enormously to include your device and iOS version,
what you expected to happen, and what happened instead.

## Privacy

Ninety-Nine collects nothing and transmits nothing. There is no account, no
analytics, and no networking code — the compiled binary doesn't even link a
networking framework. Settings and stats live on your device and are deleted
with the app.

Full policy: [PRIVACY.md](PRIVACY.md).

## Licence

Source-available, **not** open source — see [LICENSE](LICENSE). You're welcome to
read it, learn from it, and build it locally. You may not redistribute it or
publish a build of it.

The rules of the card game itself aren't covered by that: game rules aren't
copyrightable, and you're welcome to implement them yourself.

## Status

Feature-complete and archive-ready. Submission needs an Apple Developer account —
see [APP_STORE.md](Docs/APP_STORE.md).
