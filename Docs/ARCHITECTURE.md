# Architecture

## The one rule

**The engine knows the rules. The view model knows the timing. The views know
neither.**

Everything else follows from that. `Engine/` has no `import SwiftUI` and no
`import UIKit`; `Views/` never re-derives whether a card is legal.

```
NinetyNine/
├── Engine/            pure Swift, no UI framework, fully tested
│   ├── Card.swift             Suit, Rank, Card, Deck
│   ├── SeededRandom.swift     mulberry32 — every random decision goes through it
│   ├── GameState.swift        the serialisable state + read-only queries
│   ├── Rules.swift            legality and effect calculation (no mutation)
│   ├── GameEngine.swift       the referee: every legal state transition
│   ├── GameEvent.swift        what just happened, in order
│   └── AIPlayer.swift         heuristic opponents
├── Design/            the visual language
│   ├── Palette.swift          felt, brass, semantic colours, the tally ramp
│   ├── Typography.swift       three voices: display, numeric, body
│   ├── Motion.swift           named curves + the Reduce Motion funnel
│   ├── SuitShape.swift        vector suit outlines + standard pip layouts
│   ├── CardView.swift         card faces, court panels, guilloche back, flip
│   ├── TableBackground.swift  lit felt, procedural fibre noise, parallax
│   └── TallyGauge.swift       the centrepiece
├── Audio/
│   ├── Haptics.swift          authored Core Haptics patterns per event
│   └── SoundEngine.swift      procedurally synthesised sound effects
├── Persistence/
│   ├── Settings.swift         UserDefaults-backed preferences
│   └── Records.swift          lifetime stats + achievements
└── Views/
    ├── RootView.swift         routing (deliberately not NavigationStack)
    ├── Game/                  the table and everything on it
    ├── Home/                  title + setup
    ├── Rules/                 the rulebook
    ├── Records/               stats and achievements
    └── Settings/
```

## Why the engine returns events

`engine.play(...)` is synchronous and instant — it returns the *entire*
consequence of a play as an ordered `[GameEvent]`:

```swift
[.cardPlayed(...), .tallyChanged(from: 71, to: 79), .suitLocked(.hearts, by: "ai0"),
 .drewCards(count: 1, by: "ai0"), .turnAdvanced(to: "human", owesTwo: false)]
```

The table needs those consequences spread over time: the card flies, *then* the
tally ticks, *then* the lock snaps shut, *then* the next player starts thinking.
`GameViewModel.absorb(_:)` walks the timeline and paces it.

The alternative — diffing two `GameState` snapshots in the view to guess what
changed — is how card games end up with animations that fire twice or not at
all. With an event list there is nothing to infer.

It also means the engine is trivially reusable: a server, a watch app, or a
replay viewer would consume the same events.

## Why `Rules.resolve` is the only rules implementation

Both the *validator* and the *applier* call it:

```swift
switch Rules.resolve(card: card, declaration: declaration, in: state) {
case .success(let effect): /* apply exactly this */
case .failure(let reason): throw GameError.illegal(reason)
}
```

A card therefore cannot be *played* in a way it could not be *validated*. The UI
also calls it — `Rules.legalDeclarations(for:in:)` is what dims unplayable cards
and populates the declaration sheet — so the shading on the table is not an
approximation of the rules, it *is* the rules.

`IllegalReason` is a typed enum where every case carries a plain-language
explanation, which is why tapping a dead card can say *"The suit is locked to
Hearts"* rather than *"invalid move"*.

## Determinism

Every random decision — the shuffle, which well card is drawn, the reshuffle —
goes through an injected `RandomSource`. Seed it and a game replays exactly.
That's what makes the self-play tests meaningful: `testAIGamesAlwaysTerminateWithAWinner`
runs complete games across five fixed seeds and asserts each ends with exactly
one winner.

The one deliberate exception is `AIPlayer`'s `casual` tier, which adds system
randomness to its scoring so the easiest opponent isn't perfectly repeatable.

## Testing strategy

| Layer | How it's tested |
|---|---|
| Rules | Direct assertions on hand-built board states — reaching "tally is 99 and the last card was the 9 of hearts" through a real deal would be slow and fragile |
| Engine | Dealing, turn flow, elimination, and full AI self-play games that must terminate |
| AI | Must always produce a legal move; games must never deadlock |
| Presentation maths | `Standings`, `FanLayout`, `PipLayout`, `Palette` — the things that are easy to get backwards, extracted from views so they can be tested |
| Screens & interaction | XCUITest driving real taps through every screen, including a full game played to completion |

`FanLayout` and `Standings` exist as separate types **because** of bugs found in
the simulator: the fan overflowed the screen and the loss screen called last
place "Runner-up". Both are now pinned by tests that would have caught them.

## Notable decisions

**No `NavigationStack`.** The default push transition and system back chevron
are the most recognisable "stock iOS app" tells. Routing is a plain enum in
`RootView` with authored transitions.

**No asset files.** Every card, suit, pip, ornament, and sound is generated at
runtime from vectors or DSP. The shipped app is 2.9 MB, there is no licensing or
attribution debt, and a colour change propagates everywhere at once.

**Procedural audio.** A card flick genuinely *is* band-passed noise with a fast
decay; a chip click is a damped sine. Files would just be recordings of these
formulas — and parameters in code let the tally tick be pitched by how close the
tally is to 99, which a fixed file cannot do.

**Accessibility is a feature, not a checkbox.** Cards report their own name and
whether they're playable. The gauge reports the tally, the headroom, the lock,
and the direction of play. `MotionBudget` is a single funnel through which every
animation passes, so honouring Reduce Motion cannot be forgotten in one view.

## Known limitations

- **iPad** builds and runs, but the layout is tuned for phone proportions.
- **No multiplayer.** The original prototype had a socket.io server and Facebook
  login; both were dropped. See `Docs/DECISIONS.md`.
- **English only**, though the project is configured for string catalogs.
