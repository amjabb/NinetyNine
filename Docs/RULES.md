# 99 — Official Rules

## Overview

99 is a trick-less shedding game for 2–6 players played with a single standard 52-card deck (no jokers). Players take turns adding cards to a running **tally**, which must never exceed 99 (with one narrow exception). A player who cannot legally play, and has no way to save themselves, is **eliminated**. The last player remaining wins.

## Setup

1. **Deck:** one 52-card deck, no jokers.
2. **Dealer:** chosen at random for the very first game. In any later game (rematch), the player who was **eliminated first** in the previous game deals next.
3. **Cards to deal:** the dealer picks how many cards to deal — from **3** up to a cap set by player count, so the deck can't run out mid-deal. Two of whatever is dealt become each player's **well**, so the number is not a hand size: deal 7 and you open holding 5 and play down to 3, deal 5 and you start at 3 straight away.

   | Players | Max cards to deal |
   |---|---|
   | 2 | 12 |
   | 3 | 12 |
   | 4 | 12 |
   | 5 | 10 |
   | 6 | 8 |

   The number also decides how much *choice* everyone gets over their well. At the minimum of 3 you bank two of three — no decision at all. At 9 you genuinely pick. A tight deal is therefore not only a small hand, it's a denial of a decision.

4. **Dealing:** starting to the dealer's left, deal one card at a time, clockwise, until every player has the chosen number. Every card goes to the hand — nothing is set aside by the dealer. Whatever remains becomes the face-down **draw pile**. There is no starting discard card; the tally begins at 0 and the first card played establishes the discard pile.

4a. **Building your well:** before anybody plays, each player in turn (starting to the dealer's left) chooses **two cards from their own hand** and buries them face down as their well. They don't see those cards again until they're stuck. What you bank is what you give up holding — and the cards that make the best well (a Queen is never blocked; a Jack can't bust you) are exactly the cards you'd want in hand.

5. **First turn:** the player to the dealer's right goes first, then play proceeds clockwise.

## Basic Turn

At the start of your turn your hand is topped up to **three** if it's below that. Three is the sustaining hand: whatever you were dealt, you play down to three and hold there. Then you must play one legal card from your hand face-up onto the discard pile (playing a legal card is **mandatory** if you have one — you may not voluntarily dip into your Well while a legal hand card is available). Add the card's value to the tally per the chart below. After playing, draw back up to your current hand-size cap from the draw pile. If the draw pile is empty, shuffle the discard pile (except the top/active card) into a new draw pile.

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
- **Follow the suit, or answer the card.** A lock is beaten either by playing the locked suit, or by playing a card of the **same rank as the one face up**, whatever suit it is — and in that case the lock moves to the suit you just played. A six on a six escapes a hearts lock and locks yours instead.
- **An 8 names its own suit** rather than inheriting yours, since choosing a suit is what an 8 is for. It may also decline and lock nothing.
- **A Queen** is wild for suit as well as rank, so a lock never blocks one. Declared an 8, she seizes the lock and sends it anywhere — or nowhere. Having done so she counts as an 8 on the pile, so the next player may answer her with an 8.
- If the legal card you play happens to be an 8 (which, to be legal, must itself be of the currently-locked suit), you may rename the suit going forward.
- The lock stays in effect, passing suit to suit, until a player can't follow it and **skips** their turn — at that point the lock lifts and any suit is legal again. It also lifts when a player is **eliminated** while it's up.

### Zero and Negative Play

- **A 10 may drop the tally below zero from wherever it stands.** You don't have to be sitting on 0 to dive.
- Climbing back out is the hard part: while the tally is negative, no card may jump it straight to a positive number — something has to land **exactly on 0** first. Only 10s push it further negative, and a 9 is unplayable down there.
- The asymmetry is deliberate. Going down is cheap and coming back is not, so the negatives are a place you choose to go and then have to work your way out of.

### The 100 Exception

- The only way the tally can ever exceed 99: after a 9 sets the tally to 99, if the very next card played is the **Ace of the same suit as that 9**, played as a **1**, the tally advances to exactly **100**. (This can be played by whoever's turn is next, not necessarily the same player who played the 9 — but it must be the immediate next card played, or the 99 stands as normal.)
- Once at 100, the **next single card played** has its value forced negative (e.g., a King becomes -10 instead of +10; a Jack stays 0; a Queen can impersonate any card, value and ability included, e.g. impersonating an 8 to go 100 → 92 and lock a suit). A 10 cannot be played in this slot, since it's already negative by default. After that one forced-negative card, normal rules resume.

## Poisonous Queens

- The moment any player **draws** a queen from the draw pile, queens become poisonous for the rest of the game. Every other player currently holding a queen in hand must immediately move it into their own face-down **poison pile** (in front of them, out of hand).
- From then on, whenever a player draws a queen, it goes straight to their poison pile instead of their hand, and their maximum hand size drops by one — every queen costs a card, all the way down (3 → 2 → 1). The floor is 1, so a player can never be left unable to hold a card at all. Against a sustaining hand of three this bites fast: one queen and you hold two, two and you hold one for the rest of the game unless you clear them. This reduction is personal — it doesn't affect other players.
- **Clearing three queens with a Snackoo gives that capacity back.** Otherwise the reward would be incoherent: three cards drawn into a hand that can't hold them.
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
