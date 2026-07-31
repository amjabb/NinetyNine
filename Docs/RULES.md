# 99 — Official Rules

## Overview

99 is a trick-less shedding game for 2–6 players played with a single standard 52-card deck (no jokers). Players take turns adding cards to a running **tally**, which must never exceed 99 (with one narrow exception). A player who cannot legally play, and has no way to save themselves, is **eliminated**. The last player remaining wins.

## Setup

1. **Deck:** one 52-card deck, no jokers.
2. **Dealer:** chosen at random for the very first game. In any later game (rematch), the player who was **eliminated first** in the previous game deals next.
3. **Hand size:** the dealer picks a hand size between **5 and 12**, but it's capped by player count so the deck doesn't run out mid-deal (each player also needs a 2-card well, and no reserve buffer is required — the dealer can use every card in the deck if they choose):

   | Players | Max hand size |
   |---|---|
   | 2 | 12 |
   | 3 | 12 |
   | 4 | 11 |
   | 5 | 8 |
   | 6 | 6 |

4. **Dealing:** starting to the dealer's left, deal one card at a time, clockwise, until every player has the chosen hand size. Then deal each player a **Well** — two more cards, dealt face-down and left unseen. Whatever remains becomes the face-down **draw pile**. There is no starting discard card — the tally begins at 0, and the first card played establishes the discard pile.
5. **First turn:** the player to the dealer's right goes first, then play proceeds clockwise.

## Basic Turn

On your turn you must play one legal card from your hand face-up onto the discard pile (playing a legal card is **mandatory** if you have one — you may not voluntarily dip into your Well while a legal hand card is available). Add the card's value to the tally per the chart below. After playing, draw back up to your current hand-size cap from the draw pile. If the draw pile is empty, shuffle the discard pile (except the top/active card) into a new draw pile.

A card is only legal to play if it would keep the tally at or below 99 (barring the 9→Ace exception below) and it obeys any active suit-lock (from an 8).

### Playing several of a rank at once

If you hold two or more cards of the same rank you may play them all as one turn — a **run**. It still costs one play, and you draw back up to your cap afterwards.

- The cards land **one after another**, and each is judged against the running tally as it goes. Three 5s from a tally of 90 is illegal, because the third one would reach 100 — the run is refused as a whole, not truncated.
- Effects compound the way they would if the cards were played separately. **Two 4s reverse twice and so cancel each other out**; three reverse three times, which is a net flip. The suit-lock is a state rather than a toggle, so a run of 8s simply locks to the one suit you name.
- A declaration covers the whole run: all the Aces in it are 1, or all are 11.
- **Queens can't be run together** — each one has to name what it's impersonating, so they're played individually.

## Card Values & Special Effects

| Card | Value | Effect |
|---|---|---|
| Ace | 1 or 11 (player's choice) | — |
| 2–7 | Face value | — |
| 4 | 0 | **Reverses** turn order (no effect with only 2 players) |
| 8 | 8 | **Suit-lock:** name a suit. Every player after you must play a card of that suit until the lock is broken (see below) |
| 9 | Sets tally to exactly **99**, regardless of the prior tally | Unplayable while the tally is negative |
| 10 | -10 | Unplayable immediately after a 9→Ace 100 (see below), since it's already negative by default |
| Jack | 0 | — |
| Queen | Wild — copies both the value *and* any special ability of any card you declare it as | See **Poisonous Queens** below |
| King | 10 | Becomes -10 only in the one forced-negative slot right after a 9→Ace 100 |

### The Suit-Lock (8)

- Playing an 8 sets the tally +8 and requires every subsequent player to play a card of the named suit.
- Naming a suit is **optional**: you may play an 8 and decline to lock anything, in which case the lock simply lifts.
- Only a card of the locked suit is a legal play during the lock (an 8 of a *different* suit is **not** a legal play while a lock is active).
- A **Queen is wild for suit as well as rank**, so a lock never blocks one. A Queen played while a lock is up may be declared an 8 and used to change the suit to anything — or to no suit at all.
- If the legal card you play happens to be an 8 (which, to be legal, must itself be of the currently-locked suit), you may rename the suit going forward.
- The lock stays in effect, passing suit to suit, until a player can't follow it and **skips** their turn — at that point the lock lifts and any suit is legal again. It also lifts when a player is **eliminated** while it's up.

### Zero and Negative Play

- At the very start of the game, and **any time the tally returns to exactly 0** during play, the player whose turn it is may play a 10 to send the tally negative.
- While the tally is negative: only 10s may push it further negative; a 9 is unplayable; and no card may jump the tally directly from negative to positive — a card must land **exactly on 0** first. Once the tally is exactly 0 again, it's treated like a fresh "first hand" and a 10 may be played to go negative again, or normal ascending play resumes.

### The 100 Exception

- The only way the tally can ever exceed 99: after a 9 sets the tally to 99, if the very next card played is the **Ace of the same suit as that 9**, played as a **1**, the tally advances to exactly **100**. (This can be played by whoever's turn is next, not necessarily the same player who played the 9 — but it must be the immediate next card played, or the 99 stands as normal.)
- Once at 100, the **next single card played** has its value forced negative (e.g., a King becomes -10 instead of +10; a Jack stays 0; a Queen can impersonate any card, value and ability included, e.g. impersonating an 8 to go 100 → 92 and lock a suit). A 10 cannot be played in this slot, since it's already negative by default. After that one forced-negative card, normal rules resume.

## Poisonous Queens

- The moment any player **draws** a queen from the draw pile, queens become poisonous for the rest of the game. Every other player currently holding a queen in hand must immediately move it into their own face-down **poison pile** (in front of them, out of hand).
- From then on, whenever a player draws a queen, it goes straight to their poison pile instead of their hand, and their maximum hand size permanently drops by one — every queen costs a card, all the way down (5 → 4 → 3 → 2). Three queens down means a hand of two. The floor is 1, so a player can never be left unable to hold a card at all. This reduction is personal — it doesn't affect other players.
- If a player's poison pile reaches **three** queens, they may declare **"Snackoo!"** (see below) to clear it.

## Snackoo

If you have three of a kind in hand (e.g., three Jacks), or three queens in your poison pile, you may declare **"Snackoo!"** at any time — even outside your own turn, as a free action that doesn't cost you a turn. Discard the three matching cards (no effect on the tally) and immediately draw three replacement cards from the draw pile.

## The Well

Each player has two Well cards, set aside at the deal and never seen until needed.

- You may only go to your Well when you have **no legal card** to play from your hand.
- When stuck, you choose: go to your Well, or simply skip your turn (the well is optional, even when stuck).
- Going to the Well draws **one of your two Well cards at random** (you don't choose which).
  - If it's legal to play: you play it, and draw **two bonus cards** from the draw pile as a reward. Your other, unused Well card stays hidden for later.
  - If it's not legal to play: you are **eliminated from the game immediately**.
- Each player only has two Well cards for the whole game. Once both have been successfully used, you have no Well left — if you get stuck again with no legal hand card, you may still skip once, but with no Well and no playable card, you're very likely eliminated on your next stuck turn.

## Skipping a Turn

If you skip (by choice when allowed, or because you have no other option), you owe **two cards** on your next turn instead of one — both plays subject to all normal legality rules.

## Elimination & Winning

A player is eliminated when a drawn Well card isn't playable. When a player is eliminated, their remaining hand, any unused Well card, and poison pile are shuffled into the draw pile, and turn order continues clockwise skipping their seat. The tally carries on unaffected by an elimination. The last player remaining wins, and deals... no — **the player eliminated first** deals the next game.

---

## Assumptions I made to fill remaining gaps (flag anything you want changed)

- **Snackoo and the discard pile:** the three discarded cards go to the discard pile like any other discard (they just don't change the tally).
- **Repeat skips:** you can't skip on a turn where you already owe extra cards from a prior skip — you must attempt to play (or go to the Well) until that debt is cleared, to avoid infinite skip loops.
- **9 → Ace → 100 timing:** must be the very next card played after the 9 (by anyone whose turn it is next); if any other card is played first, the tally simply stays at 99 and normal rules apply.
- **Reverse (4) with 2 players:** no-op, since reversing direction with two players doesn't change whose turn is next.
- **Well card that would eliminate you but completes a trio:** you're offered the Snackoo first. An unplayable well card is normally the end, so being shown the way out before being told you're out is the only reading that isn't a rules trap.
- **Runs and the discard pile:** every card in a run lands on the pile in the order it was played; the last one is the active card.

Let me know if any of these should work differently — otherwise I'll treat this as final and move on to scoping the app (multiplayer rooms, AI opponent, Facebook login/friends).
