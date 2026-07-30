# Multiplayer — design and plan

Target: **1.1**. Branch: `feature/multiplayer`. 1.0 is tagged `v1.0`.

---

## The constraint that shapes the plan

**GameKit cannot be tested without an active Apple Developer account.** Game
Center needs an entitlement, which needs a provisioning profile, which needs a
team. So any GameKit code written today is code we cannot run.

That's not a reason to wait, because **most of the work isn't GameKit.** The
hard parts of networked multiplayer here are:

1. Encoding a move as data
2. Making sure a player's device never receives cards it isn't allowed to see
3. Guaranteeing every device ends up in the same state
4. Supporting more than one human player at all

None of those need a network, and all of them are testable today. GameKit is
the last and thinnest layer.

So the plan is ordered by testability, which happens to also be the correct
engineering order.

---

## Which multiplayer model

| Model | Verdict |
|---|---|
| **Custom server (the original prototype)** | ✗ Rejected in 1.0 and still rejected. Needs deploying and paying for forever, and an app whose main mode depends on a server that might go away is a liability. |
| **GameKit turn-based (`GKTurnBasedMatch`)** | ✓ **Recommended.** Apple hosts the match state, matchmaking, and invitations. No server, no login to build, no privacy disclosure beyond Game Center itself. Designed exactly for a game where players take discrete turns. Survives the app being backgrounded or killed. |
| **GameKit real-time (`GKMatch`)** | ~ Possible later. Better "sat together" feel, but you must handle disconnects, reconnection, and host migration yourself, and a dropped player stalls everyone. A card game does not need sub-second latency. |
| **Local pass-and-play** | ✓ **Ship first.** No account, no network, no matchmaking. Genuinely fun for a game like this, and it forces the multi-human abstraction that network play needs anyway. |

**Decision: pass-and-play first, then GameKit turn-based.** Real-time stays on
the table for a later version; the transport abstraction below means choosing it
later costs an adapter, not a rewrite.

---

## Architecture

### The problem with `GameState` today

`GameState` contains *everything*: every player's hand, every well card, the
whole draw pile in order. In solo play that's fine — the only other minds at the
table are AI running in the same process.

Send that struct to another device and you have handed an opponent the entire
game. Not "they could cheat if they tried" — the information is simply there in
the payload, and anyone with a proxy can read it.

So multiplayer needs two representations:

```
GameState          the truth. Lives on exactly one authority.
PlayerView         what a specific player is allowed to know.
```

`PlayerView` carries your own hand in full, and for everyone else only what
you'd see across a real table: how many cards they hold, how many well cards
remain, how many queens are poisoned, whether they owe a play. Hidden cards
appear as counts, never as cards.

### Flow

```
        player taps a card
               │
               ▼
        PlayerAction            ← codable, tiny, no hidden info
               │
               ▼  (transport)
        the authority
               │
        GameEngine.apply(action)
               │
               ▼
        [GameEvent]  ─────────► redacted per recipient
               │
               ▼
        each player's PlayerView
```

`PlayerAction` is deliberately a *request*, not a fact. A client saying "I play
the 9 of hearts" is asking. The authority validates it through the same
`Rules.resolve` every local play goes through, and a client that asks for
something illegal is simply refused. There is no separate multiplayer rules
path — that is exactly how card games ship with duplication bugs.

### Who is the authority

For turn-based GameKit, the authority is **whoever's turn it is**. Apple hands
the match data to the current player, they apply their own move, and pass the
updated state on. This is standard for `GKTurnBasedMatch` and avoids needing a
host that might quit.

That's safe here because a player can only ever act on their own turn, and every
action is re-validated by the *next* player's device against the same rules.
A tampered state would have to survive validation by every other participant.

The action log makes this checkable: given the same seed and the same ordered
actions, every device must arrive at an identical state. Any divergence is
detectable rather than silent.

### Determinism

Already mostly true — 1.0 funnels every random decision through `RandomSource`,
and the engine is deterministic given a seed. Multiplayer makes that load-bearing:

- the match carries the seed
- the match carries the ordered action log
- any device can replay the log and must reach byte-identical state

This is what `testReplayingAnActionLogReproducesStateExactly` will pin down.

---

## Plan

| # | Step | Testable now? |
|---|---|---|
| 1 | `PlayerAction` — codable move covering every legal action | ✅ **done** |
| 2 | `PlayerView` — redacted state, hidden cards become counts | ✅ **done** |
| 3 | Deterministic replay of an action log | ✅ **done** |
| 4 | `MatchTransport` protocol + in-process loopback | ✅ **done** |
| 5 | `MatchCoordinator` — drives a match from transport updates | ✅ **done** |
| 6 | `HandoffView` — the covered screen between players | ✅ **done** |
| 7 | Wire pass-and-play into the table UI and setup screen | ⏳ **next** |
| 8 | `GameKitTransport` (`GKTurnBasedMatch`) + matchmaking UI | ❌ needs the account |
| 9 | Game Center entitlement, App Store Connect config | ❌ needs the account |

### Step 7 — the one real decision left before online play

`GameTableView` currently binds to `GameViewModel`, which owns a `GameState`
directly. Pass-and-play and online both need it to bind to a **`PlayerView`**
instead, since neither is allowed to hold the full state.

Two ways to get there:

**A. Refactor `GameTableView` onto `PlayerView` (recommended).** One table
screen serves all three modes, and solo automatically gains the same anti-cheat
boundary. Cost: touching a screen that is currently tested and shipping, so it
needs the UI tests re-run against all three modes.

**B. A second table screen for multiplayer.** Lower risk to 1.0, but two screens
to keep in sync forever, and they *will* drift — that is exactly the duplication
this codebase has avoided everywhere else.

A is the right call. It's deferred to its own commit so the diff is reviewable
and 1.0's screen isn't churned inside a feature commit.

Steps 1–5 are a shippable 1.1 on their own: **pass-and-play is a real feature**,
not scaffolding. If the account is delayed, 1.1 ships without network play and
GameKit becomes 1.2 with no wasted work.

---

## Things that will bite, noted early

- **The well is random and secret.** `drawFromWell` picks one of two hidden cards
  using the engine's RNG. That must be resolved by the authority and only the
  *result* transmitted, or a client could learn its own well contents early by
  reading the payload.
- **Queens poisoning is a global, retroactive effect** — it reaches into every
  player's hand at once. The event already exists (`queensBecamePoisonous`) and
  must be applied identically everywhere, not recomputed per client.
- **Snackoo is an off-turn action.** In turn-based GameKit only the current
  player holds the match data, so an off-turn Snackoo can't be applied
  immediately. Simplest correct answer: queue it and apply on the player's own
  turn. Needs a rules note either way.
- **A player quitting mid-match** is not in the 1.0 rulebook. Proposal: treat it
  as elimination, since that's already a well-defined state the engine handles.
- **Reconnection.** Turn-based gets this free; real-time would not.
