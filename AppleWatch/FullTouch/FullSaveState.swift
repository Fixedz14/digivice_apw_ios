import Foundation

struct FullSaveState: Codable {
    static let currentSchema = 4

    var schemaVersion = FullSaveState.currentSchema
    var hasStarted = false
    var playerName = "TAMER"
    var newGamePlus = false
    var steps = 0
    var dPower = 99
    var battles = 0
    var wins = 0
    var currentCharacter = 0
    var level = 1
    var nextLevelUp = 5
    var nextLevelDown = 5
    var docks = [-1, -1, -1, -1]
    var currentArea = 0
    var areaCleared = Array(repeating: false, count: 13)
    var distance = 6000
    var defeated = false
    var lastEncounterWasBattle = false
    var lastBossUnlocked = false
    var characterStats = CharacterDefinition.defaults.map(CharacterStats.initial)
    var spiritsUnlocked = Array(repeating: false, count: 12)
    var spiritsObtained = Array(repeating: false, count: 12)
    var charactersUnlocked = [true, true, true, true, true, false]
    var characterParty = [true, true, true, true, true, false]
    var digimonUnlocked = [Bool]()
    var digiDigitHighScore = 0
    var digiShipHighScore = 0
    var connectWins = 0
    var tvRewards = 0
    var codesRedeemed = [String]()
    var completedRuns = 0
    var tutorialSeen = false
    var paletteIndex = 0
    var soundEnabled = true
    var hapticsEnabled = true
    var gridEnabled = true
    var notificationsEnabled = false
    var motionDay = ""
    var lastMotionTotal = 0
    var lastSaved = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, hasStarted, playerName, newGamePlus, steps, dPower
        case battles, wins, currentCharacter, level, nextLevelUp, nextLevelDown
        case docks, currentArea, areaCleared, distance, defeated, lastEncounterWasBattle
        case lastBossUnlocked, characterStats, spiritsUnlocked, spiritsObtained
        case charactersUnlocked, characterParty, digimonUnlocked, digiDigitHighScore
        case digiShipHighScore, connectWins, tvRewards, codesRedeemed, completedRuns
        case tutorialSeen, paletteIndex, soundEnabled, hapticsEnabled, gridEnabled
        case notificationsEnabled, motionDay, lastMotionTotal, lastSaved
    }

    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? schemaVersion
        hasStarted = try values.decodeIfPresent(Bool.self, forKey: .hasStarted) ?? hasStarted
        playerName = try values.decodeIfPresent(String.self, forKey: .playerName) ?? playerName
        newGamePlus = try values.decodeIfPresent(Bool.self, forKey: .newGamePlus) ?? newGamePlus
        steps = try values.decodeIfPresent(Int.self, forKey: .steps) ?? steps
        dPower = try values.decodeIfPresent(Int.self, forKey: .dPower) ?? dPower
        battles = try values.decodeIfPresent(Int.self, forKey: .battles) ?? battles
        wins = try values.decodeIfPresent(Int.self, forKey: .wins) ?? wins
        currentCharacter = try values.decodeIfPresent(Int.self, forKey: .currentCharacter) ?? currentCharacter
        level = try values.decodeIfPresent(Int.self, forKey: .level) ?? level
        nextLevelUp = try values.decodeIfPresent(Int.self, forKey: .nextLevelUp) ?? nextLevelUp
        nextLevelDown = try values.decodeIfPresent(Int.self, forKey: .nextLevelDown) ?? nextLevelDown
        docks = try values.decodeIfPresent([Int].self, forKey: .docks) ?? docks
        currentArea = try values.decodeIfPresent(Int.self, forKey: .currentArea) ?? currentArea
        areaCleared = try values.decodeIfPresent([Bool].self, forKey: .areaCleared) ?? areaCleared
        distance = try values.decodeIfPresent(Int.self, forKey: .distance) ?? distance
        defeated = try values.decodeIfPresent(Bool.self, forKey: .defeated) ?? defeated
        lastEncounterWasBattle = try values.decodeIfPresent(Bool.self, forKey: .lastEncounterWasBattle) ?? lastEncounterWasBattle
        lastBossUnlocked = try values.decodeIfPresent(Bool.self, forKey: .lastBossUnlocked) ?? lastBossUnlocked
        characterStats = try values.decodeIfPresent([CharacterStats].self, forKey: .characterStats) ?? characterStats
        spiritsUnlocked = try values.decodeIfPresent([Bool].self, forKey: .spiritsUnlocked) ?? spiritsUnlocked
        spiritsObtained = try values.decodeIfPresent([Bool].self, forKey: .spiritsObtained) ?? spiritsObtained
        charactersUnlocked = try values.decodeIfPresent([Bool].self, forKey: .charactersUnlocked) ?? charactersUnlocked
        characterParty = try values.decodeIfPresent([Bool].self, forKey: .characterParty) ?? characterParty
        digimonUnlocked = try values.decodeIfPresent([Bool].self, forKey: .digimonUnlocked) ?? digimonUnlocked
        digiDigitHighScore = try values.decodeIfPresent(Int.self, forKey: .digiDigitHighScore) ?? digiDigitHighScore
        digiShipHighScore = try values.decodeIfPresent(Int.self, forKey: .digiShipHighScore) ?? digiShipHighScore
        connectWins = try values.decodeIfPresent(Int.self, forKey: .connectWins) ?? connectWins
        tvRewards = try values.decodeIfPresent(Int.self, forKey: .tvRewards) ?? tvRewards
        codesRedeemed = try values.decodeIfPresent([String].self, forKey: .codesRedeemed) ?? codesRedeemed
        completedRuns = try values.decodeIfPresent(Int.self, forKey: .completedRuns) ?? completedRuns
        tutorialSeen = try values.decodeIfPresent(Bool.self, forKey: .tutorialSeen) ?? tutorialSeen
        paletteIndex = try values.decodeIfPresent(Int.self, forKey: .paletteIndex) ?? paletteIndex
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? soundEnabled
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? hapticsEnabled
        gridEnabled = try values.decodeIfPresent(Bool.self, forKey: .gridEnabled) ?? gridEnabled
        notificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? notificationsEnabled
        motionDay = try values.decodeIfPresent(String.self, forKey: .motionDay) ?? motionDay
        lastMotionTotal = try values.decodeIfPresent(Int.self, forKey: .lastMotionTotal) ?? lastMotionTotal
        lastSaved = try values.decodeIfPresent(Date.self, forKey: .lastSaved) ?? lastSaved
    }

    mutating func normalize(for catalog: GameCatalog) {
        schemaVersion = Self.currentSchema
        docks = Array((docks + [-1, -1, -1, -1]).prefix(4))
        areaCleared = Array((areaCleared + Array(repeating: false, count: 13)).prefix(13))
        spiritsUnlocked = Array((spiritsUnlocked + Array(repeating: false, count: 12)).prefix(12))
        spiritsObtained = Array((spiritsObtained + Array(repeating: false, count: 12)).prefix(12))
        charactersUnlocked = Array((charactersUnlocked + Array(repeating: false, count: 6)).prefix(6))
        characterParty = Array((characterParty + Array(repeating: false, count: 6)).prefix(6))
        while characterStats.count < catalog.characters.count {
            characterStats.append(.initial(from: catalog.characters[characterStats.count]))
        }
        characterStats = Array(characterStats.prefix(catalog.characters.count))
        for index in characterStats.indices {
            let definition = catalog.characters[index]
            characterStats[index].hp = max(0, min(definition.capHP, characterStats[index].hp))
            characterStats[index].spirit = max(0, min(definition.capSpirit, characterStats[index].spirit))
            characterStats[index].stamina = max(0, min(definition.capStamina, characterStats[index].stamina))
            characterStats[index].skill = max(0, min(definition.capSkill, characterStats[index].skill))
        }
        if digimonUnlocked.count < catalog.digimon.count {
            digimonUnlocked += catalog.digimon.dropFirst(digimonUnlocked.count).map(\.unlock)
        } else if digimonUnlocked.count > catalog.digimon.count {
            digimonUnlocked = Array(digimonUnlocked.prefix(catalog.digimon.count))
        }
        docks = docks.map { id in
            guard catalog.digimon.indices.contains(id),
                  catalog.digimon[id].level != -4 else { return -1 }
            return id
        }
        for index in spiritsObtained.indices where spiritsObtained[index] {
            spiritsUnlocked[index] = true
        }
        for index in characterParty.indices where !charactersUnlocked[index] {
            characterParty[index] = false
        }
        if !charactersUnlocked.contains(true), !charactersUnlocked.isEmpty {
            charactersUnlocked[0] = true
            characterParty[0] = true
        }
        currentArea = max(0, min(currentArea, max(0, catalog.areas.count - 1)))
        currentCharacter = max(0, min(currentCharacter, max(0, catalog.characters.count - 1)))
        if !charactersUnlocked[currentCharacter],
           let fallback = charactersUnlocked.firstIndex(of: true) {
            currentCharacter = fallback
        }
        level = max(1, min(level, 99))
        nextLevelUp = max(1, min(nextLevelUp, 5))
        nextLevelDown = max(1, min(nextLevelDown, 5))
        dPower = max(0, min(dPower, 99))
        steps = max(0, min(steps, 999_999))
        distance = max(0, distance)
        battles = max(0, battles)
        wins = max(0, min(wins, battles))
        completedRuns = max(0, completedRuns)
        paletteIndex = max(0, min(paletteIndex, 5))
        playerName = String(playerName.uppercased().prefix(5))
        if playerName.isEmpty { playerName = "TAMER" }
        codesRedeemed = Array(Set(codesRedeemed.map { $0.uppercased() })).sorted()
    }
}

enum EncounterKind: String, Codable {
    case battle
    case digiStorm
}

enum FullGameScreen: Hashable {
    case boot
    case characterSelect
    case tutorial
    case home
    case stats
    case mainMenu
    case map
    case status
    case spirits
    case camp
    case connect
    case extraMenu
    case database
    case codeScanner
    case games
    case digiDigit
    case digiShip
    case digiStorm
    case tv
    case battle
    case capture
    case connectBattle
    case connectSend
    case ending
    case settings
}

struct BattleSession: Equatable {
    enum Phase: Equatable {
        case alert
        case command
        case scanning
        case chooseSpirit
        case chooseAttack
        case resolving
        case capture
        case result
    }

    enum Result: Equatable {
        case none
        case win
        case lose
        case escaped
    }

    var enemyID: Int
    var enemyHP: Int
    var activeDigimonID: Int?
    var activeHP: Int
    var activeMaxHP: Int
    var copiedDocks: [Int]
    var copiedSpirits: [Bool]
    var callPower = 8
    var evolvedThisTurn = false
    var prepaidAttack = false
    var mineMove = 0
    var enemyMove = 0
    var energyBonus = 0
    var crunchBonus = 0
    var abilityBonus = 0
    var phase: Phase = .alert
    var result: Result = .none
    var message = ""
    var isBoss = false
    var isFinalBoss = false
    var capturedID: Int?
    var round = 0
    /// 1 = original level-up event, -1 = original level-down event.
    var levelChange = 0
    var lostSpiritID: Int?
}

struct DigiStormSession: Equatable {
    enum Outcome: Equatable {
        case active
        case safe
        case partyLost([Int])
        case teleported(Int)
        case partyRecovered([Int])
    }

    var taps = 0
    var target = 40
    var outcome: Outcome = .active
    var deadline = Date().addingTimeInterval(8.2)
    var lostParty = [Int]()
}

struct MiniGameSession: Equatable {
    enum Kind: Equatable {
        case digiDigit
        case digiShip
    }

    var kind: Kind
    var score = 0
    var lives = 3
    var round = 1
    var targetMove = Int.random(in: 0...2)
    var finished = false
    var message = ""
    var usedDigimonID: Int?
}
