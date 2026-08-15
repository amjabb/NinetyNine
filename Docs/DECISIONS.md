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

---

## 15. Auto-banked wells are random positions, not the first two

Pass-and-play can bank everyone's well without asking, because the opening lap of
the table is four hand-offs spent on a decision made with no information: the
well is chosen face down, by position.

That last part is what makes the option safe to offer at all. It isn't the app
playing for you — there is nothing to play. It is the app guessing where you
would have guessed.

It does mean the *implementation* has to guess the way a player would. Taking
slots 0 and 1 was the obvious version and is wrong: hands are dealt sorted, so
"off the top of the fan" banks everyone's two lowest cards in every game. A
player picking blind has no such bias, so neither can this. The picks are random
positions, drawn per seat.

They also go into the shared action log as ordinary `chooseWell(slots:)` actions.
Two consequences, both wanted: replay is exact, because the log records what was
picked rather than a rule for picking it; and there is no new `PlayerAction`
case, so the online payload version is untouched.

## 16. Ruthless was tuned against rules that no longer exist

`testRuthlessBeatsCasual` fell to exactly 50%, which is the test doing its job.
Two rule changes had quietly invalidated the tier's strategy:

- It paid a premium to lock a suit it was long in. But a lock is now escapable by
  any card matching the rank showing, and the escaper takes the lock with them —
  so it was buying something that had stopped existing.
- It hoarded 10s while the tally was low, waiting for the zero it needed to dive
  from. Diving now works from any tally, so the wait was pure cost.

Retuned to the rules as they are: locking is worth a little, and going negative
is worth a lot and worth doing on sight. Ruthless 58% vs Casual, Merciless 61%
vs Ruthless — the ladder is ordered again.

The general lesson is that the AI encodes the rules a second time, in a form no
compiler checks. A rule change is not done when the engine agrees with it.


---

## 17. The blind well pick wasn't blind

Section 15 justified auto-banked wells on the grounds that "there is no
information at this point for anybody to use." That was wrong when it was
written.

Hands were sorted at the deal, *before* the well was chosen. The pick is made by
position, so position was a perfect proxy for rank: slot 0 was always your lowest
card, the last slot always your highest. A player who noticed could bank their
two highest cards every single game, and the interface presented this as a blind
guess.

The sort now happens when the last well is buried — the point at which hand order
stops being a channel and starts being a convenience. The deal itself is left in
the shuffle's order, which carries nothing.

Two things worth keeping from this. The auto-well feature was *justified* by a
property the code did not have, and the justification read as reasonable for a
week. And the well-selection heuristics had quietly grown to exploit the sorted
order — the tiers "differed only in where they reach, which is flavour rather
than advantage" was true only once the leak was closed.

## 18. Measuring the AI against the wrong game

The strength harness played tiers heads-up, 60 games. Both were wrong.

**Heads-up** is the one table size where playing at the next player means almost
nothing: you hand them a pinned board and get it straight back. A tier built to
squeeze has to be measured with three at the table, which is also how the game is
actually played.

**60 games** carries a standard error of about 6.5 points. Every historical
figure quoted for these tiers — "58% vs Casual", "68% vs Ruthless" — was inside
the noise. The ladder had been tuned against sampling error for weeks. It is 400
games now, and the numbers moved.

What the better measurement immediately found: **Ruthless was the weakest tier of
the four**, below the one it was meant to outrank. It had never been compared to
Sharp — only both to Casual — so nothing had ever asked the question.

## 19. Tiers are capabilities, not constants

Ruthless differed from Sharp by tweaked numbers: a heavier lookahead, a more
hoarded Queen, a looser well gamble. Each was defensible in isolation and the
combination measured out as the weakest opponent in the game.

Constants tuned by taste don't compose into a ladder. Capabilities do. Each tier
now *adds* something and keeps everything below it: Sharp plays the board,
Ruthless keeps its outs, Merciless reads the table and its own future, Cutthroat
prices the kill. Monotonicity is a property of the structure rather than a
coincidence to be re-measured after every change.

## 20. Nobody pressed to 99 because of arithmetic

The complaint was that no opponent ever pushed the tally up to squeeze anybody.
The cause was not a missing strategy. Pinning the board is priced against the
headroom term, which is the largest number in the scorer: taking the tally to 99
costs up to 76 points of it, while a kill was valued at 120 x its probability —
about 40 points at a pinned board. The kill was worth less than the comfort, so
it was never chosen, and no amount of new heuristics would have surfaced it.

Two further things came out of measuring rather than reasoning:

- Every *rare* weapon — pressing a skip debt, hunting a void suit, pinning at 99
  — measures as neutral over 400 games. They fire a few times a game. Neutral is
  not the same as useless, but it does mean win rate can't judge them, which is
  why they have behaviour tests instead.
- A single line intended to stop the tier leaking information — accepting 12
  points worse odds rather than skip under a lock — cost it 13 points of win
  rate. It was trading a coin flip on elimination for a fraction of a read. It
  had also silently confounded an earlier experiment, which is the more expensive
  kind of bug.

**Cutthroat is not decisively stronger than Merciless.** It takes 35% against a
33% fair share, which is about one standard error. It is clearly ahead of Sharp
and Ruthless (46-48%), and it plays visibly differently. A larger gap wants a
two-ply search rather than more heuristic tuning, and that is a bigger piece of
work than this was.

---

## 21. A loss has to be visible before it is announced

Two reports, one cause. Eliminated mid-turn, the game went straight to the
result; and a stranded turn offered an "SDQ" button that had to be pressed
before anything would happen.

The first was a lifetime problem. `eliminate` sweeps the player's hand back into
the deck as part of eliminating them, so any UI that renders *after* the event
renders an empty hand — the cards that decided the game are gone by the time
there is anything to show. The hand now travels on the event itself, captured
before the sweep, exactly as the unspent well card already did. It is held on
screen for a beat before the verdict.

The second was a category error in the interface. Being stranded — no legal
card, no well, a play owed — has exactly one outcome. Presenting it as a button
made the player confirm arithmetic, and in pass-and-play made the whole table
wait while somebody conceded a game they had already lost. It resolves itself
now, after long enough to read the board. Conceding stays in the pause menu,
where it is a genuine choice.

Two things worth keeping:

**The refill is what makes the reveal necessary.** You do not keep the hand you
played from — you draw back to three — so being stranded means the cards you
were dealt *into the hole* were dead as well. That is precisely the thing a
player wants to see, and precisely what an announcement withholds.

**The transient beat had to be tested where it is deterministic.** A UI test for
a 2.3-second overlay fails on timing, not behaviour: an XCUITest query can take
longer than the window it is looking for. It is asserted at the view-model level
by polling the phase, and the UI test covers what persists — that nothing was
tapped and the seat still resolved.

## 22. A DEBUG-only seam called from non-DEBUG code

The launch-argument hook that forces a stranded position calls a `#if DEBUG`
coordinator seam, and the calling method was not itself guarded. Every test run
is a Debug build, so it compiled and passed everywhere it was exercised — and
would have failed the Release archive, which is the one build that matters and
the last one anybody makes.

Caught by building Release before tagging the version rather than after. That
check is cheap and belongs in the release routine, not in the post-mortem.

---

## 23. A button is only tappable where it draws

Reported by a player: the rulebook sections opened when you tapped the title and
not when you tapped the arrow.

A SwiftUI `Button`'s label hit-tests its *rendered content*, not its frame. The
row was an icon, a title, a `Spacer`, and a chevron — so the live area was the
icon, the words, and an 11-point glyph, with dead space in between. The chevron
is the part that looks like the control and was the hardest thing on the row to
hit; 11 points against a 44-point minimum.

`.contentShape(Rectangle())` makes the whole row one target. The tests tap at
96% across (the arrow) and 72% (the dead middle), and both were confirmed to
fail with the fix reverted — a regression test that passes on the broken code
tests nothing.

Worth a sweep whenever a row-shaped control has a `Spacer` in it: the layout
looks like one control and behaves like two small ones.

## 24. The icon drew its wordmark twice

The second 9 looked squashed. The font was fine; the icon was drawing the
numerals twice — once as filled text with a shadow, and again as a separately
built outline, displaced by a hardcoded `textSize.height * 0.22`, to clip the
brass gradient. The two copies never landed on each other.

On the first 9 the seam hid inside the stroke. On the second it fell across the
counter and filled it in, which is what read as distortion.

One path now serves both the shadow and the gradient clip, because a path cannot
be misaligned with itself. The glyphs are laid out explicitly rather than through
a typesetter whose metrics were then being guessed at, centring is on the inked
bounds rather than typographic ones, and the fill is non-zero winding so tightly
kerned numerals merge rather than punching a hole at the overlap.

Note that the bug was also supplying a bevel: two offset copies of a glyph read
as depth. Removing it left the numerals flatter and correct. If the depth is
wanted back it should be drawn deliberately.

## 25. A 0.4-second margin is not a margin

`test07` failed once in a full run and passed alone, twice. The coaching toast
lives 2.6 seconds; the test tapped once and waited up to 3 seconds for it to
appear. Under full-suite load an XCUITest query routinely takes longer than the
window it is looking for, so the toast came and went mid-query.

It taps up to three times with short waits now — each tap re-arms the toast, so
three short looks beat one long one. The same shape as the stranded-hand reveal:
anything that appears for about two seconds cannot be asserted on with a single
slow query, and the fix is more attempts rather than a longer wait.

---

## 26. Online multiplayer could never be entered, and no test could have known

Three bugs, found by playing a real match across two simulators signed into two
Game Center accounts. Every one of them lived in the handshake between GameKit
and the app — the one path with no coverage, and the reason "never run against a
real network" had been on the list for weeks.

**Nothing could open a match.** `findMatch` awaited a continuation resumed from
the matchmaker's `didFindMatch:` delegate callback. Apple deprecated that in
iOS 9 and replaced it with `GKTurnBasedEventListener`; the SDK header says so.
The system has not called it since 2015, so the continuation only ever resumed
on *cancel* or *error*. Choosing a match dismissed the sheet and returned the
player to the setup screen — every time, for invitations and for their own turn
alike.

**And nothing could receive one.** `GKLocalPlayer.local.register(self)` sat
inside `start()`, which runs only *after* a match has been obtained. No match
was ever obtained, so no listener was ever registered, so invitations arrived
nowhere. `leave()` compounded it with `unregisterAllListeners()`, which would
have killed the app's only route for incoming invitations for the rest of the
session. The listener now belongs to the session, is registered once at
authentication, and routes events to whichever transport owns that match.

**A late-joining player was a stranger to their own match.** A match created
with an automatch seat is written before anybody fills it, and at that moment
`participant.player` is nil — so the payload recorded a random UUID named
"Player". When the real player arrived their `gamePlayerID` matched nothing:
their own device drew them as an opponent called "Player", gave them no hand,
and waited for a turn from somebody who was holding the phone. Identities are
now reconciled by seat index against the live match, at join and on every
update, and the corrected payload is written back.

Two smaller things fell out of the same session. The online seat count was
reading `Settings.opponentCount` — the *solo* opponents slider — which is how a
two-player game invited six people. And the table announced "Your move" while
other players were still burying wells: wells are sequential on one device and
parallel online, so `isYourTurn` had never needed to ask whether the match had
actually started. It refused every card tapped, silently, because the rules were
right and the interface had not been told.

The general lesson is the specific one: a protocol boundary that is only ever
exercised by hand is a boundary that rots. The fake in `OnlineEntryTests` models
GameKit's semantics — a match is a document with one current participant, a turn
is a write, a seat can be filled after creation — so these failures now have
somewhere to be caught before a person finds them.

---

## 27. A match you cannot leave, and a button doing two jobs

Reported after playing 2.2: once you'd moved in an online game there was no way
back to your other games, and the online tab offered a single button for two
unrelated things.

**Leaving.** The only exit from a table was a pause-menu button marked "SDQ —
Self Disqualify". It did not actually forfeit — it routed home — but nobody is
going to press it to find out, and home is the wrong destination anyway: a
turn-based match waits, so stepping out belongs among your games. Online now
offers "Your matches", which returns to Game Center's list with the turn intact.
Forfeiting stays a separate, explicit thing.

**Setting up.** "Start a new match" and "Open one in progress" are different
actions with different preconditions, and one button could only ever name one of
them. The second is disabled until there is something to open, and says how many
are waiting rather than opening an empty list to prove it.

**The deal comes before the guests.** Choosing players, cards and the well rule
now happens on its own screen, and only then does Game Center ask who's playing.
Nobody should be asked who they want to play before they've decided what the game
is. Apple's matchmaker handles the invitations because it already does friends,
automatch and invites, and it is the screen players recognise — building a second
one would duplicate it worse.

Two things fell out of this.

Banking wells automatically is a *match-level rule* online, not a preference:
every client has to agree about whether a well is chosen or dealt, or half the
table sits on a well builder the other half never saw. So it travels in the
payload, and `currentRules` goes to 5 — matches begun under 4 are refused rather
than quietly replayed into a different game. And the auto-bank has to be
*submitted* rather than applied locally, or a well banked on one device leaves
every other client waiting on a choice they never see made.

Reaching the new-match screen deliberately does *not* require being signed in.
Choosing a deal needs nothing from Game Center, and a wall while it reconnects is
a wall for no reason — which is precisely what happened while testing this, when
the sandbox session dropped mid-session. Sign-in is enforced at "Find players",
where it actually matters.
