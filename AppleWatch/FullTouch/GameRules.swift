import Foundation

enum GameRules {
    enum TVOutcome: Equatable {
        case bonus
        case capture
        case battle
        case storm
    }

    enum BonusOutcome: Equatable {
        case distanceMinus500
        case distancePlus300
        case dPowerPlus10
        case levelUp
    }

    static func dPowerCost(level: Int) -> Int {
        max(3, 20 - max(0, level) / 5)
    }

    static func dockSlot(for bits: [Int]) -> Int {
        switch bits {
        case [1, 0, 1]: 1
        case [1, 1, 0]: 2
        case [1, 0, 0]: 3
        default: 0
        }
    }

    static func moveForScan(_ bits: [Int], fallback: Int) -> Int {
        switch bits {
        case [1, 1, 1]: 0
        case [1, 0, 1], [1, 0, 0]: 1
        case [1, 1, 0]: 2
        default: max(0, min(2, fallback))
        }
    }

    static func callCost(levelDifference: Int) -> Int {
        if levelDifference <= -10 { return 2 }
        if levelDifference <= -5 { return 3 }
        if levelDifference <= 5 { return 4 }
        if levelDifference <= 14 { return 5 }
        return 6
    }

    static func beats(_ mine: Int, _ enemy: Int) -> Bool {
        (mine == 2 && enemy == 1)
            || (mine == 1 && enemy == 0)
            || (mine == 0 && enemy == 2)
    }

    static func combatOutcome(
        playerMove: Int,
        enemyMove: Int,
        playerStat: Int,
        enemyStat: Int,
        controlLevelExceeded: Bool
    ) -> Int {
        if controlLevelExceeded { return -1 }
        if playerMove == enemyMove {
            if playerStat == enemyStat { return 0 }
            return playerStat > enemyStat ? 1 : -1
        }
        return beats(playerMove, enemyMove) ? 1 : -1
    }

    static func tvOutcome(roll: Int) -> TVOutcome {
        if roll <= 30 { return .bonus }
        if roll <= 60 { return .capture }
        if roll <= 90 { return .battle }
        return .storm
    }

    static func bonusOutcome(roll: Int) -> BonusOutcome {
        if roll <= 40 { return .distanceMinus500 }
        if roll <= 70 { return .distancePlus300 }
        if roll <= 85 { return .dPowerPlus10 }
        return .levelUp
    }
}
