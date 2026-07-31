//
//  PlayerAction.swift
//  A move, as data.
//
//  Every way a player can affect the game is one of these. They are Codable and
//  tiny — an action is a *request*, never a fact. A client saying "I play the
//  nine of hearts" is asking; the authority validates it through the same
//  `Rules.resolve` a local play goes through and refuses anything illegal.
//
//  Crucially, an action carries no hidden information. It names a card by id,
//  and only ever a card the acting player is allowed to know about. Nothing
//  here can leak another player's hand.
//

import Foundation

/// Something a player asks to do.
enum PlayerAction: Codable, Hashable, Sendable {

    /// Play a card from hand, resolved with the given declaration.
    case play(cardID: Int, declaration: Declaration)

    /// Play several cards of the same rank together. One play, one tally change.
    case playSet(cardIDs: [Int], declaration: Declaration)

    /// Bank two of the cards you were dealt as your face-down well. Happens once
    /// per player, before anyone plays.
    case chooseWell(cardIDs: [Int])

    /// Turn over one of the player's two face-down well cards. `slot` is which
    /// one they chose — both are face down, so this leaks nothing; it is simply
    /// left-or-right. The authority still owns what the card turns out to be.
    case drawFromWell(slot: Int)

    /// Play the well card that has just been revealed.
    case resolveWell(declaration: Declaration)

    /// The revealed well card is unplayable but completes a three-of-a-kind:
    /// Snackoo out of it rather than be eliminated.
    case snackooWellCard

    /// Accept elimination from an unplayable well card.
    case concedeWellCard

    /// Skip the turn, taking on a two-play debt.
    case skip

    /// Declare Snackoo. A free action.
    case snackoo(kind: SnackooKind)

    /// Concede when stranded with no legal play, no well, and a debt owed.
    case concede

    /// Leave the match. Treated as elimination — see Docs/MULTIPLAYER.md.
    case forfeit

    /// Mirrors `GameEvent.SnackooKind` but Codable and free of the event type,
    /// so the wire format doesn't depend on the presentation-facing enum.
    enum SnackooKind: Codable, Hashable, Sendable {
        case threeOfAKind(Rank)
        case threeQueens

        var asEvent: GameEvent.SnackooKind {
            switch self {
            case .threeOfAKind(let rank): return .threeOfAKind(rank)
            case .threeQueens: return .threeQueens
            }
        }

        init(_ event: GameEvent.SnackooKind) {
            switch event {
            case .threeOfAKind(let rank): self = .threeOfAKind(rank)
            case .threeQueens: self = .threeQueens
            }
        }
    }

    /// True for actions only legal on the acting player's own turn. Snackoo and
    /// forfeit are the exceptions.
    var requiresTurn: Bool {
        switch self {
        // Choosing a well has its own running order, checked by the engine —
        // it happens before anyone has a turn to be out of.
        case .snackoo, .forfeit, .chooseWell: return false
        default: return true
        }
    }
}

/// An action paired with who asked for it. This is the unit that crosses the
/// wire and the unit that gets logged.
struct SubmittedAction: Codable, Hashable, Sendable {
    var playerID: String
    var action: PlayerAction
    /// Position in the match's ordered log. Used to detect gaps and to reject
    /// replays of a stale action.
    var sequence: Int
}

// MARK: - Applying actions

extension GameEngine {

    /// The single entry point for a networked or pass-and-play move.
    ///
    /// Routes to the existing typed methods rather than reimplementing any of
    /// them — there must be exactly one rules path, or the multiplayer and solo
    /// games will drift apart the first time a rule changes.
    @discardableResult
    func apply(_ submitted: SubmittedAction) throws -> [GameEvent] {
        let playerID = submitted.playerID

        // Wells come first, always. Without this an out-of-order action from a
        // peer could start the game for one client and not the others.
        if state.isChoosingWells {
            switch submitted.action {
            case .chooseWell: break
            // Quitting has to work at any moment, including before you've
            // banked — otherwise one player leaving strands the rest.
            case .forfeit: break
            default: throw GameError.notChoosingWells
            }
        }

        if submitted.action.requiresTurn {
            guard state.currentPlayer.id == playerID else { throw GameError.notYourTurn }
        }

        switch submitted.action {
        case .play(let cardID, let declaration):
            return try play(cardID: cardID, by: playerID, declaration: declaration)

        case .playSet(let cardIDs, let declaration):
            return try playSet(cardIDs: cardIDs, by: playerID, declaration: declaration)

        case .chooseWell(let cardIDs):
            return try chooseWell(cardIDs: cardIDs, by: playerID)

        case .drawFromWell(let slot):
            return try drawFromWell(by: playerID, slot: slot)

        case .resolveWell(let declaration):
            return try resolveWell(by: playerID, declaration: declaration)

        case .snackooWellCard:
            return try snackooWellCard(by: playerID)

        case .concedeWellCard:
            return try concedeWellCard(by: playerID)

        case .skip:
            return try skip(by: playerID)

        case .snackoo(let kind):
            return try declareSnackoo(by: playerID, kind: kind.asEvent)

        case .concede:
            return try concedeStranded(by: playerID)

        case .forfeit:
            return try forfeit(by: playerID)
        }
    }

    /// Every legal action available to a player right now. Used by the UI to
    /// build affordances, and by tests to fuzz only legal moves.
    func availableActions(for playerID: String) -> [PlayerAction] {
        guard !state.isOver, let player = state.player(id: playerID), !player.isEliminated else {
            return []
        }

        var actions: [PlayerAction] = []

        // Nothing else can happen until every player has banked a well. The
        // choice itself is a multi-select in the UI rather than something worth
        // enumerating — every pair of held cards is legal — so this offers one
        // concrete, legal default rather than an empty placeholder.
        if state.isChoosingWells {
            if state.wellChooserID == playerID, player.hand.count >= Rules.wellSize {
                actions.append(.chooseWell(cardIDs: player.hand.prefix(Rules.wellSize).map(\.id)))
            }
            return actions
        }

        // Off-turn actions first — these don't depend on whose turn it is.
        if Rules.canSnackooPoison(player) {
            actions.append(.snackoo(kind: .threeQueens))
        }
        for rank in Rules.snackooRanksInHand(for: player) {
            actions.append(.snackoo(kind: .threeOfAKind(rank)))
        }

        guard state.currentPlayer.id == playerID else { return actions }

        // A revealed well card must be resolved before anything else.
        if let pending = state.pendingWell, pending.playerID == playerID {
            if pending.isPlayable {
                for declaration in Rules.legalDeclarations(for: pending.card, in: state) {
                    actions.append(.resolveWell(declaration: declaration))
                }
            } else if pending.snackooRank != nil {
                // Unplayable, but the third of its rank — offer the way out
                // before the way down.
                actions.append(.snackooWellCard)
                actions.append(.concedeWellCard)
            }
            return actions
        }

        for card in player.hand {
            for declaration in Rules.legalDeclarations(for: card, in: state) {
                actions.append(.play(cardID: card.id, declaration: declaration))
            }
        }

        let options = currentPlayerOptions
        if options.canUseWell {
            // One action per slot, so the UI can offer both cards.
            for slot in 0..<player.well.count { actions.append(.drawFromWell(slot: slot)) }
        }
        if options.canSkip { actions.append(.skip) }
        if options.isStranded { actions.append(.concede) }

        return actions
    }
}
