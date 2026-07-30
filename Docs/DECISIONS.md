# Decisions

Choices made converting the Expo/React Native prototype into a shipping iOS
game, and why. Anything here is reversible — this exists so you can disagree
with a specific call rather than the whole result.

---

## 1. Native SwiftUI, not the React Native app

**The prototype** was Expo + React Native with a Node/socket.io server.

**Shipped:** a native Swift app; the JS rules engine was ported to Swift.

The brief asked for something that doesn't feel like boring iOS defaults, and
the things that make a card game feel good — 120Hz spring physics on a dragged
card, custom Core Haptics patterns, procedurally synthesised audio, vector cards
that stay crisp from a 9pt mini-fan to a 260pt hero reveal — are either
unavailable or fighting the framework through React Native.

The port was also the cheapest part of the job: the rules engine was already
pure, dependency-free logic, so translating it was mechanical, and it gained a
real test suite in the process.

---

## 2. No multiplayer, no Facebook login

**The prototype** had socket.io rooms, a friends list, and Facebook auth.

**Shipped:** solo play against AI only.

This is the biggest reduction in scope, and it was a deliberate call:

- The multiplayer server would need to be **deployed and paid for indefinitely**.
  Shipping an app whose main mode points at a server that doesn't exist is a
  guaranteed App Store rejection under guideline 2.1.
- **Facebook Login triggers guideline 4.8**: any app offering a third-party
  login must also offer an equivalent privacy-preserving option (Sign in with
  Apple). That's real work for a feature with no backend behind it.
- Login and analytics SDKs would turn a "we collect nothing" privacy manifest
  into a data-collection disclosure.

The result is an app that is genuinely finished and genuinely private, rather
than a larger app that can't be submitted. The engine is deliberately pure and
event-driven, so adding an authoritative server later is additive work — the
same engine can run as the referee.

**If you want multiplayer, the honest sequencing is:** ship 1.0 solo, then add
Game Center for turn-based multiplayer (no server to run, no login to build, no
privacy disclosure) in 1.1.

---

## 3. Rules interpretations

Eight places where the written rulebook needed a judgement call are documented
separately in [`INTERPRETATIONS.md`](INTERPRETATIONS.md), each with the file to
change if you disagree.

The one worth flagging here: **the tally can only go negative from exactly 0**.
The rulebook says a 10 sends the tally negative "at the very start" and "any time
the tally returns to exactly 0", which reads as a restriction. The original JS
engine didn't enforce it and allowed 8 → −2. It's a single constant
(`Rules.negativeEntryRequiresZero`) if you want the looser reading.

---

## 4. Difficulty as personality, not as handicap

The three tiers differ in **what they value**, not in how much they cheat. All
three see exactly what a human sees — no peeking at hands or wells.

- **Casual** — noisy scoring, so it misses the best line. Fires Snackoo
  whenever it can because that's fun. Takes bad well gambles.
- **Sharp** — one-ply lookahead so it avoids stranding itself, and real
  odds maths on the well-versus-skip decision.
- **Ruthless** — weights the suit lock heavily when long in a suit, hoards
  brakes, values the 9→Ace→100 combo, and accepts worse well odds when the board
  is tight because skipping only defers the problem.

A difficulty slider that just adds noise to a single heuristic produces three
versions of the same opponent. This produces three opponents.

---

## 5. What the tally gauge is for

The tally is the whole game, so it's the largest thing on screen and carries
five signals at once: the number, headroom to 99, the colour ramp from green
through brass and amber to red, the suit lock, and the direction of play.

The colour ramp exists because a player shouldn't have to read and subtract to
know they're in trouble. The audio tick is pitched by the same value, so the
danger is audible before it's read.

---

## 6. Screenshots are generated from the shipping build

`ScreenshotTests` drives the real app into each state and captures it. Store
images therefore cannot show something the app doesn't do, and they regenerate
after any visual change with one command.
