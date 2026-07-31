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

---

## 7. Playing a run is a long press, not a button

Two or more of a rank can go down as one turn. The obvious design — a "play all
of these" control on the hand — was rejected on the author's constraint: it
would be visible for the entire game, and the endgame is exactly when a player is
deliberately hoarding nines and jacks. A permanent affordance there is noise at
best and a misfire at worst.

So the gesture is deliberately separate from the one that plays a card. Tap
always plays exactly the card you tapped. Long press opens the builder, and only
when the pressed card actually has company — otherwise it does nothing visible,
which is better than a control that scolds you for pressing it.

The builder is a single screen rather than a count picker feeding a declaration
sheet. Two modals between a long press and a card landing is more ceremony than
the move deserves.

**Order is shown, not just membership.** Cards in a run are judged one at a time
against the running tally, so with 5s near the ceiling the order is the
difference between legal and refused. A numbered badge is the cheapest way to
make that visible.

---

## 8. Effects compound; states don't

A run of 4s reverses once per card, so two cancel out and three net a single
flip. A run of 8s locks once, to the suit named.

That asymmetry looks like an inconsistency and isn't: reversal is a *toggle*
applied per card, whereas the suit lock is a *state* the last card sets. Getting
this wrong is invisible in a two-player game (where reversal does nothing) and
quietly changes who plays next in every other game, so `resolveSet` computes
reversal as the parity of the count and there are tests pinning both halves.

---

## 9. Queens turning poisonous takes the screen

It happens once per game, changes the rules for everyone at the same instant,
and can't be undone. It used to be a banner that slid past in well under a
second — the author noticed and said so.

It is now a full-screen moment showing the actual queen that did it, with copy
that differs by viewer: whoever drew it is told plainly, and each player is told
what it costs *them* specifically. The overlay reads ahead in the event timeline
to find its own `queenPoisoned` events so the cost lands in the same breath
rather than as a second banner behind the first.

The scrim is 0.93 black rather than a tint. At 0.7 the table's banner, its
"thinking" line and its status row all read straight through the headline —
which the first screenshot showed immediately and no assertion would have.


---

## 10. The deal number stopped being a hand size

The dealer names a number; two of it becomes each player's well, so the opening
hand is `dealt - 2`. Deal 7 and you hold five. Deal 5 and you hold three, and
draw up to five on your first turn.

Calling that "hand size" was actively misleading, so it is `cardsDealt`
everywhere — including a new `@AppStorage` key, because the old one held a
number that counted only the hand and reusing it would have silently shrunk
every returning player's opening hand by two.

**The number now buys choice, not just cards.** At the minimum of three you bank
two of three — no decision at all. At nine you genuinely pick. A tight deal is a
denial of a decision, which is why Ruthless deals tight and Casual deals
generously.

---

## 11. Refill moved to the start of the turn

It used to happen only after a play. With a small deal that would have left a
player choosing from three cards on the turn they can least afford it. Topping
up at the start of a turn is a no-op in the ordinary case — a hand is already at
cap when its turn comes round — and it also picks up a cap that moved when a
queen was poisoned.

One consequence worth knowing: the opening top-up draws from the deck, so it can
turn up a queen and poison the whole table before a single card is played.

---

## 12. A lock can only be moved by an 8 played on an 8

The first version of this let any 8 ignore a lock, which made a lock almost
worthless — anyone holding an 8 could shrug it off at any point. The rule is
narrower: an 8 of any suit is legal *directly on another 8*, and that's how the
lock changes hands. Once any other card lands on top, the lock binds again.

The engine tracks whether the face-up card counts as an 8, which is not the same
as whether it *is* one: a Queen declared an 8 counts, so she can be used to seize
a lock and then hands the same opening to the next player.

---

## 13. Two bugs the declaration sheet was hiding

Both were reported as "the option isn't there", and both were worse than that.

**Declining a lock never rendered.** The sheet built its suit list by filtering
on "has a lock suit" — and declining a lock has no suit by definition, so the
engine offered the option and the UI dropped it on the floor every single time.

**A Queen played as an 8 never asked which suit.** It resolved ties by picking
the option with the lowest resulting tally, and every lock suit produces the same
tally, so it silently picked an arbitrary one. Ranks that need a follow-up answer
now get one instead of being tie-broken.

---

## 14. Online matches carry a rules version

A match log from an older build still *applies* cleanly to newer code — every
action in it is valid — it simply replays into a different game, because the deal
changed. Two players would sit looking at contradictory tables with nothing
reported.

That's undetectable from the data, so the payload states its rules version and a
mismatch is refused with an explanation rather than tolerated.
