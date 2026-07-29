# Rules interpretations

`Docs/RULES.md` is the authored rulebook. A handful of situations needed a
judgement call to be implementable. Each one below is a deliberate decision, not
an accident — and each is a small, isolated change if you want it to work
differently.

| # | Situation | Decision | Where |
|---|---|---|---|
| 1 | Can the tally go negative from a mid-range tally (e.g. 8 → −2 with a 10)? | **No.** The rulebook says a 10 sends the tally negative "at the very start" and "any time the tally returns to exactly 0", so negatives are entered only from exactly 0 (or pushed further from an already-negative tally). | `Rules.negativeEntryRequiresZero` — flip to `false` to allow it from anywhere. |
| 2 | At a tally of 100, can a 0-value card (Jack, 4) be played? | **No.** It would leave the tally at 100, still above the ceiling, and would re-arm the forced-negative slot forever. The forced-negative card must actually bring the tally down. | `Rules.resolve` — the `newTally > ceiling` guard. |
| 3 | Does a Queen impersonating an 8 follow the suit lock by its *printed* suit or the suit it names? | **Printed suit.** A Queen is a real card of a real suit; naming a suit is an ability, not a disguise. So the Queen of Hearts can be played under a Hearts lock while impersonating anything. | `Rules.resolve` — the suit-lock guard reads `card.suit`. |
| 4 | Can a hand Snackoo be declared with three Queens *in hand*? | **No.** Queens have their own exit (the poison pile). Three-of-a-kind Snackoo covers ranks A–K excluding Queens; three *poisoned* Queens is the separate Snackoo. | `Rules.snackooRanksInHand` |
| 5 | How low can the poisoned-queen hand cap go? | **Floor of 3**, per the rulebook's "capped at 3". | `GameEngine.poison(queen:seat:)` |
| 6 | Player owes two plays, has no legal card, and no well card left. | **Eliminated.** They may not skip while repaying a debt (rulebook assumption #2), and with no well there is no other out. Surfaced in the UI as an explicit "stranded" state rather than a silent loss. | `TurnOptions.isStranded`, `GameEngine.concedeStranded` |
| 7 | Does the 9 → Ace → 100 window survive a Snackoo (a free, off-turn action)? | **Yes.** Snackoo doesn't touch the tally and isn't "a card played", so `pendingNineSuit` is untouched by it. | `GameEngine.declareSnackoo` |
| 8 | Reshuffling when the draw pile empties. | The **active top discard stays on the table**; everything beneath it is reshuffled into a new draw pile. If there's only one card in the discard pile there's nothing to recycle. | `GameEngine.reshuffleDiscard` |

## Inherited from the original prototype

These matched the JS engine and were kept:

- A **4 is a no-op for direction with two active players** — reversing between
  two seats doesn't change who is next.
- **The 100 window is strictly one card wide.** If any other card is played
  after the 9, the 99 simply stands.
- **Snackoo discards go to the discard pile** like any other discard, without
  touching the tally.
