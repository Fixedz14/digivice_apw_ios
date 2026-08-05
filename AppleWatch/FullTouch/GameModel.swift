import Foundation
import UserNotifications
import WatchKit

struct Combatant: Equatable {
    let id: Int
    let name: String
    let sprite: String
    let type: String
    let level: Int
    let maxHP: Int
    let energy: Int
    let crunch: Int
    let ability: Int
    let evolution: Int?

    func stat(for move: Int) -> Int {
        switch move {
        case 0: energy
        case 1: crunch
        default: ability
        }
    }
}

enum BattleScanPurpose: Equatable {
    case call
    case attack
    case digiPower
}

struct BonusPresentation: Equatable {
    let type: Int
    let value: Int
    let startedAt: Date
}

@MainActor
final class GameModel: ObservableObject {
    @Published private(set) var state: FullSaveState
    @Published var screen: FullGameScreen
    @Published private(set) var pendingEncounter: EncounterKind?
    @Published private(set) var battle: BattleSession?
    @Published private(set) var storm: DigiStormSession?
    @Published private(set) var miniGame: MiniGameSession?
    @Published private(set) var banner = ""
    @Published var scanBits = [Int]()
    @Published private(set) var scanPurpose: BattleScanPurpose = .call
    @Published var codeInput = ""
    @Published var battleCodeInput = ""
    @Published var databaseFilter = "all"
    @Published private(set) var endingMessage = ""
    @Published private(set) var bonusPresentation: BonusPresentation?
    @Published var connectCodeInput = ""
    @Published private(set) var connectOpponent = [Int]()
    @Published private(set) var connectRound = 0
    @Published private(set) var connectPlayerScore = 0
    @Published private(set) var connectOpponentScore = 0
    @Published private(set) var connectMessage = ""

    let catalog: GameCatalog

    private let saveKey = "DTectorWatch.FullSave.v3"
    private let backupSaveKey = "DTectorWatch.FullSave.backup.v3"
    private let pedometer = PedometerService()
    private var didStartPedometer = false

    init(catalog: GameCatalog = .load()) {
        self.catalog = catalog
        let loadedState: FullSaveState
        let defaults = UserDefaults.standard
        let primaryData = defaults.data(forKey: saveKey)
        let backupData = defaults.data(forKey: backupSaveKey)
        var restored = primaryData.flatMap {
            try? JSONDecoder().decode(FullSaveState.self, from: $0)
        }
        if restored == nil, let backupData,
           let backup = try? JSONDecoder().decode(FullSaveState.self, from: backupData) {
            restored = backup
            defaults.removeObject(forKey: saveKey)
        }
        if var decoded = restored {
            decoded.normalize(for: catalog)
            loadedState = decoded
        } else {
            var fresh = FullSaveState()
            fresh.normalize(for: catalog)
            loadedState = fresh
        }
        state = loadedState
        screen = loadedState.hasStarted
            ? (loadedState.tutorialSeen ? .home : .tutorial)
            : .boot

#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-qa-autostart"), !state.hasStarted {
            beginNewGame(characterID: 0, playerName: "QA")
        }
        if arguments.contains("-qa-autostart"), !state.tutorialSeen {
            state.tutorialSeen = true
            screen = .home
            save()
        }

        let qaPresentationRoutes: Set<String> = [
            "-qa-storm",
            "-qa-digidigit",
            "-qa-digiship",
            "-qa-tv",
            "-qa-opening",
            "-qa-ending",
            "-qa-menu",
            "-qa-extra-menu",
            "-qa-character-select",
            "-qa-home",
            "-qa-stats",
            "-qa-bonus",
            "-qa-connect",
            "-qa-lose-spirit",
            "-qa-digiship-score"
        ]
        let qaPresentationRoute = arguments.first {
            qaPresentationRoutes.contains($0)
        }

        if let qaPresentationRoute {
            if !state.hasStarted {
                beginNewGame(characterID: 0, playerName: "QA")
            }

            if state.docks.allSatisfy({ $0 < 0 }),
               let starter = catalog.digimon.first(where: {
                   $0.level == 4 && $0.isEncounterEligible
               }) {
                state.docks[0] = starter.id
                if state.digimonUnlocked.indices.contains(starter.id) {
                    state.digimonUnlocked[starter.id] = true
                }
            }

            state.defeated = false
            pendingEncounter = nil
            battle = nil
            storm = nil
            miniGame = nil
            scanBits = []
            endingMessage = ""
            bonusPresentation = nil
            banner = ""

            if qaPresentationRoute != "-qa-opening" {
                state.tutorialSeen = true
            }

            switch qaPresentationRoute {
            case "-qa-storm":
                for index in state.characterParty.indices
                    where state.charactersUnlocked[index] {
                    state.characterParty[index] = true
                }
                startDigiStorm()
                if var qaStorm = storm {
                    // A cold Watch Simulator launch can keep the app behind
                    // its launch snapshot long enough to consume the normal
                    // 8.2-second input window before visual QA begins.
                    qaStorm.deadline = Date().addingTimeInterval(60)
                    storm = qaStorm
                }
            case "-qa-digidigit":
                startMiniGame(.digiDigit)
                save()
            case "-qa-digiship":
                startMiniGame(.digiShip)
                save()
            case "-qa-tv":
                screen = .tv
                save()
            case "-qa-opening":
                state.tutorialSeen = false
                screen = .tutorial
                save()
            case "-qa-ending":
                if state.charactersUnlocked.indices.contains(5) {
                    state.charactersUnlocked[5] = true
                    state.characterParty[5] = true
                }
                for spirit in [10, 11]
                    where state.spiritsObtained.indices.contains(spirit) {
                    state.spiritsUnlocked[spirit] = true
                    state.spiritsObtained[spirit] = true
                }
                state.newGamePlus = true
                state.completedRuns = max(1, state.completedRuns)
                endingMessage = "KOICHI JOINED\nDARKNESS SPIRITS UNLOCKED"
                screen = .ending
                save()
            case "-qa-menu":
                screen = .mainMenu
                save()
            case "-qa-extra-menu":
                screen = .extraMenu
                save()
            case "-qa-character-select":
                screen = .characterSelect
                save()
            case "-qa-home":
                screen = .home
                save()
            case "-qa-stats":
                screen = .stats
                save()
            case "-qa-bonus":
                state.distance = 1_500
                screen = .home
                bonusPresentation = BonusPresentation(
                    type: 0,
                    value: state.distance,
                    startedAt: Date().addingTimeInterval(-5.4)
                )
                save()
            case "-qa-connect":
                quickLinkBattle()
                save()
            case "-qa-lose-spirit":
                startBattle(forceEnemyID: 0)
                if var qaBattle = battle {
                    qaBattle.result = .lose
                    qaBattle.phase = .result
                    qaBattle.lostSpiritID = 0
                    battle = qaBattle
                }
                save()
            case "-qa-digiship-score":
                startMiniGame(.digiShip)
                if var qaGame = miniGame {
                    qaGame.score = 12
                    qaGame.lives = 2
                    qaGame.round = 45
                    qaGame.finished = true
                    miniGame = qaGame
                }
                state.distance = 1_500
                save()
            default:
                break
            }
        } else {
            if arguments.contains("-qa-tutorial") {
                if !state.hasStarted {
                    beginNewGame(characterID: 0, playerName: "QA")
                }
                state.tutorialSeen = false
                screen = .tutorial
                save()
            }
            if arguments.contains("-qa-battle") {
                startBattle(forceEnemyID: 0)
            }
            if arguments.contains("-qa-battle-fx") {
                startBattle(forceEnemyID: 0)
                let player = combatant(for: 1)
                if var session = battle {
                    session.activeDigimonID = player.id
                    session.activeHP = player.maxHP
                    session.activeMaxHP = player.maxHP
                    session.phase = .chooseAttack
                    session.message = "ANIMATION QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-battle-scanner") {
                startBattle(forceEnemyID: 0)
                beginBattleScan(.call)
            }
            if arguments.contains("-qa-battle-call-menu") {
                startBattle(forceEnemyID: 0)
                let player = combatant(for: 1)
                if var session = battle {
                    session.activeDigimonID = player.id
                    session.activeHP = player.maxHP
                    session.activeMaxHP = player.maxHP
                    session.phase = .chooseAttack
                    session.message = "CALL MENU QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-battle-spirit-menu") {
                startBattle(forceEnemyID: 0)
                let spirit = combatant(for: 100)
                if var session = battle {
                    session.activeDigimonID = spirit.id
                    session.activeHP = spirit.maxHP
                    session.activeMaxHP = spirit.maxHP
                    session.phase = .chooseAttack
                    session.message = "SPIRIT MENU QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-battle-spirit-evolution") {
                startBattle(forceEnemyID: 0)
                let spirit = combatant(for: 100)
                if var session = battle {
                    session.activeDigimonID = spirit.id
                    session.activeHP = spirit.maxHP
                    session.activeMaxHP = spirit.maxHP
                    session.phase = .chooseAttack
                    session.message = "SPIRIT EVOLUTION QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-battle-ancient-evolution") {
                state.dPower = 79
                startBattle(forceEnemyID: 0)
                let ancient = combatant(for: 122)
                if var session = battle {
                    session.activeDigimonID = ancient.id
                    session.activeHP = ancient.maxHP
                    session.activeMaxHP = ancient.maxHP
                    session.phase = .chooseAttack
                    session.message = "ANCIENT EVOLUTION QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-battle-win-result") {
                startBattle(forceEnemyID: 0)
                let player = combatant(for: 1)
                if var session = battle {
                    session.activeDigimonID = player.id
                    session.activeHP = player.maxHP
                    session.activeMaxHP = player.maxHP
                    session.enemyHP = 0
                    session.result = .win
                    session.phase = .result
                    session.message = "VICTORY QA"
                    battle = session
                }
            }
            if arguments.contains("-qa-final") {
                state.currentArea = 12
                state.distance = 0
                startBattle(forceEnemyID: state.newGamePlus ? 128 : 120)
            }
        }
#endif
    }

    var currentArea: AreaDefinition {
        catalog.areas.first(where: { $0.id == state.currentArea })
            ?? AreaDefinition.defaults[min(state.currentArea, AreaDefinition.defaults.count - 1)]
    }

    var currentCharacter: CharacterDefinition {
        catalog.characters.first(where: { $0.id == state.currentCharacter })
            ?? CharacterDefinition.defaults[min(state.currentCharacter, CharacterDefinition.defaults.count - 1)]
    }

    var currentCharacterStats: CharacterStats {
        guard state.characterStats.indices.contains(state.currentCharacter) else {
            return .initial(from: currentCharacter)
        }
        return state.characterStats[state.currentCharacter]
    }

    var areaProgress: Double {
        guard currentArea.distance > 0 else { return 1 }
        return 1 - (Double(state.distance) / Double(currentArea.distance))
    }

    var nextStepEvent: Int {
        let remainder = state.steps % 500
        return remainder == 0 && state.steps > 0 ? 500 : 500 - remainder
    }

    var distanceToNextEvent: Int {
        min(max(0, state.distance), nextStepEvent)
    }

    var winRate: Int {
        guard state.battles > 0 else { return 0 }
        return Int((Double(state.wins) / Double(state.battles) * 100).rounded())
    }

    var dPowerCost: Int {
        GameRules.dPowerCost(level: state.level)
    }

    var enemyCombatant: Combatant? {
        guard let battle else { return nil }
        return combatant(for: battle.enemyID)
    }

    var activeCombatant: Combatant? {
        guard let id = battle?.activeDigimonID else { return nil }
        return combatant(for: id)
    }

    var unlockedDigimon: [DigimonDefinition] {
        catalog.digimon.filter { digimon in
            state.digimonUnlocked.indices.contains(digimon.id)
                && state.digimonUnlocked[digimon.id]
        }
    }

    var dockCandidates: [DigimonDefinition] {
        unlockedDigimon.filter { $0.level != -4 }
    }

    var obtainedSpirits: [SpiritDefinition] {
        catalog.spirits.filter {
            state.spiritsObtained.indices.contains($0.id) && state.spiritsObtained[$0.id]
        }
    }

    var visibleDatabase: [DigimonDefinition] {
        let values: [DigimonDefinition]
        if databaseFilter == "all" {
            values = catalog.digimon
        } else {
            values = catalog.digimon.filter { $0.type == databaseFilter }
        }
        return values.sorted {
            if $0.number == $1.number { return $0.id < $1.id }
            return $0.number < $1.number
        }
    }

    var availableAreas: [AreaDefinition] {
        catalog.areas.filter {
            $0.id < 12 || state.areaCleared.prefix(12).allSatisfy({ $0 })
        }
    }

    var outgoingLinkCode: String {
        let values = [1, min(255, state.level)] + state.docks.map { max(0, min(255, $0 + 1)) }
        let checksum = values.reduce(0, ^)
        return (values + [checksum]).map { String(format: "%02X", $0) }.joined()
    }

    func resume() {
        startPedometerIfNeeded()
        if state.notificationsEnabled {
            scheduleEncounterNotification()
        }
    }

    func startPedometerIfNeeded() {
        guard !didStartPedometer else { return }
        didStartPedometer = true
        pedometer.start { [weak self] total in
            guard let self else { return }
            self.receivePedometer(total)
        }
    }

    func beginNewGame(characterID: Int, playerName: String) {
        if state.hasStarted, state.newGamePlus, state.completedRuns > 0 {
            let chosen = max(0, min(characterID, catalog.characters.count - 1))
            guard state.charactersUnlocked.indices.contains(chosen),
                  state.charactersUnlocked[chosen] else { return }
            state.currentCharacter = chosen
            state.playerName = String(playerName.uppercased().prefix(5))
            if state.playerName.isEmpty { state.playerName = "TAMER" }
            endingMessage = ""
            screen = .home
            banner = "\(currentCharacter.name) • NEW GAME+"
            haptic(.success)
            save()
            return
        }

        let oldSettings = state
        var fresh = FullSaveState()
        fresh.paletteIndex = oldSettings.paletteIndex
        fresh.soundEnabled = oldSettings.soundEnabled
        fresh.hapticsEnabled = oldSettings.hapticsEnabled
        fresh.gridEnabled = oldSettings.gridEnabled
        fresh.notificationsEnabled = oldSettings.notificationsEnabled
        fresh.currentCharacter = max(0, min(characterID, catalog.characters.count - 1))
        fresh.playerName = String(playerName.uppercased().prefix(5))
        if fresh.playerName.isEmpty { fresh.playerName = "TAMER" }
        fresh.hasStarted = true

        let firstSpirit = fresh.currentCharacter * 2
        if fresh.spiritsUnlocked.indices.contains(firstSpirit) {
            fresh.spiritsUnlocked[firstSpirit] = true
            fresh.spiritsObtained[firstSpirit] = true
        }

        let starters = catalog.digimon.filter { $0.level == 4 && $0.isEncounterEligible }
        if let starter = starters.randomElement() {
            fresh.docks[0] = starter.id
            fresh.digimonUnlocked = catalog.digimon.map { $0.unlock }
            if fresh.digimonUnlocked.indices.contains(starter.id) {
                fresh.digimonUnlocked[starter.id] = true
            }
        }
        fresh.normalize(for: catalog)
        state = fresh
        banner = "\(currentCharacter.name) • SYSTEM START"
        screen = .tutorial
        haptic(.success)
        save()
    }

    func completeTutorial() {
        state.tutorialSeen = true
        banner = "\(currentCharacter.name) • ADVENTURE START"
        screen = .home
        haptic(.success)
        save()
    }

    func navigate(_ destination: FullGameScreen) {
        banner = ""
        if state.defeated, destination != .camp, destination != .home {
            screen = .camp
            return
        }
        screen = destination
    }

    func goHome() {
        banner = ""
        screen = .home
    }

    /// Universal Watch navigation fallback used by the display long-press.
    ///
    /// Original GML objects each owned their own `vk_up` handler. Centralising
    /// the same parent routes prevents a SwiftUI sheet or secondary screen
    /// from becoming a dead end when it has no visible controls.
    func goBack() {
        banner = ""

        switch screen {
        case .boot, .home:
            break

        case .stats:
            screen = .home

        case .characterSelect:
            screen = .boot

        case .tutorial:
            screen = .characterSelect

        case .mainMenu, .extraMenu:
            screen = .home

        case .map, .status, .spirits, .camp, .connect:
            screen = .mainMenu

        case .database, .codeScanner, .games, .tv, .settings:
            screen = .extraMenu

        case .digiDigit, .digiShip:
            closeMiniGame()
            return

        case .digiStorm:
            storm = nil
            screen = .home

        case .connectBattle, .connectSend:
            screen = .connect

        case .ending:
            finishEnding()
            return

        case .battle, .capture:
            // Battle sub-state cancellation stays in BattleView so a hold can
            // return from move/scan/spirit selection without abandoning the
            // active encounter.
            return
        }

        haptic(.directionDown)
        save()
    }

    func openMainMenu() {
        screen = state.defeated ? .camp : .mainMenu
    }

    func openExtraMenu() {
        screen = .extraMenu
    }

    func addSteps(_ amount: Int) {
        guard amount > 0, state.hasStarted else { return }
        let progressScreens: Set<FullGameScreen> = [
            .home,
            .stats,
            .mainMenu,
            .extraMenu
        ]
        guard progressScreens.contains(screen),
              pendingEncounter == nil,
              battle == nil,
              storm == nil,
              miniGame == nil,
              !state.defeated else { return }
        let oldSteps = state.steps
        let oldHundreds = oldSteps / 100
        let newRaw = oldSteps + amount
        state.steps = newRaw > 999_999 ? newRaw % 1_000_000 : newRaw
        let crossedHundreds: Int
        if state.steps >= oldSteps {
            crossedHundreds = state.steps / 100 - oldHundreds
        } else {
            crossedHundreds = (999_999 / 100 - oldHundreds) + state.steps / 100 + 1
        }
        state.dPower = min(99, state.dPower + max(0, crossedHundreds))
        state.distance = max(0, state.distance - amount)

        if state.distance == 0 {
            pendingEncounter = .battle
            banner = "BOSS SIGNAL"
            cancelEncounterNotification()
            haptic(.notification)
        } else {
            let oldBoundary = oldSteps / 500
            let newBoundary = state.steps / 500
            if state.steps < oldSteps || newBoundary > oldBoundary {
                let shouldBattle = !state.lastEncounterWasBattle || Int.random(in: 0..<3) < 2
                pendingEncounter = shouldBattle ? .battle : .digiStorm
                banner = shouldBattle ? "DIGIMON DETECTED" : "DIGI-STORM"
                cancelEncounterNotification()
                haptic(.notification)
            }
        }
        save()
    }

    func acceptEncounter() {
        guard let pendingEncounter else { return }
        self.pendingEncounter = nil
        switch pendingEncounter {
        case .battle:
            startBattle()
        case .digiStorm:
            startDigiStorm()
        }
    }

    func dismissEncounter() {
        guard pendingEncounter != nil else { return }
        self.pendingEncounter = nil
        if Int.random(in: 0...100) >= 30 {
            state.distance += 500
            banner = "SIGNAL LOST • +500"
        } else {
            banner = "SIGNAL EVADED"
        }
        save()
    }

    func selectArea(_ id: Int) {
        guard availableAreas.contains(where: { $0.id == id }),
              let area = catalog.areas.first(where: { $0.id == id }) else { return }
        if state.currentArea == id {
            banner = "\(area.name) • \(state.distance) LEFT"
            return
        }
        state.currentArea = id
        let cleared = state.areaCleared.indices.contains(id) && state.areaCleared[id]
        state.distance = cleared ? max(1, area.distance / 2) : area.distance
        banner = "\(area.name) SELECTED"
        haptic(.click)
        save()
    }

    func selectCharacter(_ id: Int) {
        guard state.charactersUnlocked.indices.contains(id),
              state.charactersUnlocked[id],
              state.characterParty.indices.contains(id),
              state.characterParty[id] else { return }
        state.currentCharacter = id
        banner = "\(catalog.characters[id].name) ACTIVE"
        haptic(.click)
        save()
    }

    func cycleDock(_ slot: Int) {
        guard state.docks.indices.contains(slot) else { return }
        let occupiedElsewhere = Set(
            state.docks.enumerated().compactMap { index, id in
                index != slot && id >= 0 ? id : nil
            }
        )
        let ids = dockCandidates.map(\.id).filter { !occupiedElsewhere.contains($0) }
        guard !ids.isEmpty else {
            state.docks[slot] = -1
            return
        }
        if let currentIndex = ids.firstIndex(of: state.docks[slot]) {
            state.docks[slot] = currentIndex == ids.count - 1 ? -1 : ids[currentIndex + 1]
        } else {
            state.docks[slot] = ids[0]
        }
        haptic(.click)
        save()
    }

    func autoFillDocks() {
        let ids = Array(dockCandidates.prefix(4).map(\.id))
        for slot in state.docks.indices {
            state.docks[slot] = ids.indices.contains(slot) ? ids[slot] : -1
        }
        haptic(.success)
        save()
    }

    func clearDocks() {
        state.docks = [-1, -1, -1, -1]
        save()
    }

    func recoverAtCamp() {
        state.defeated = false
        state.lastEncounterWasBattle = false
        banner = "SYSTEM RECOVERED"
        haptic(.success)
        save()
    }

    func startBattle(forceEnemyID: Int? = nil) {
        let enemyID = forceEnemyID ?? selectEnemyID()
        let enemy = combatant(for: enemyID)
        var session = BattleSession(
            enemyID: enemyID,
            enemyHP: enemy.maxHP,
            activeDigimonID: nil,
            activeHP: 0,
            activeMaxHP: 0,
            copiedDocks: state.docks,
            copiedSpirits: state.spiritsObtained,
            message: "\(enemy.name) DETECTED",
            isBoss: state.distance == 0 && state.currentArea != 12,
            isFinalBoss: state.distance == 0 && state.currentArea == 12
        )
        session.enemyMove = Int.random(in: 0...2)
        battle = session
        state.lastEncounterWasBattle = true
        state.battles += 1
        screen = .battle
        banner = ""
        haptic(.notification)
        save()
    }

    func showBattleCommands() {
        guard var battle, battle.result == .none else { return }
        battle.phase = battle.activeDigimonID == nil ? .command : .chooseAttack
        battle.message = battle.activeDigimonID == nil ? "CHOOSE CALL" : "READY"
        self.battle = battle
    }

    func showSpiritSelection() {
        guard var battle, battle.result == .none else { return }
        guard battle.copiedSpirits.contains(true), state.dPower >= dPowerCost else {
            battle.message = "NO SPIRIT / D-POWER LOW"
            self.battle = battle
            haptic(.failure)
            return
        }
        battle.phase = .chooseSpirit
        battle.message = "SELECT SPIRIT"
        self.battle = battle
    }

    func beginBattleScan(_ purpose: BattleScanPurpose) {
        guard var battle, battle.result == .none else { return }
        scanPurpose = purpose
        scanBits = []
        battle.phase = .scanning
        switch purpose {
        case .call:
            battle.message = "SCAN DOCK CODE"
        case .attack:
            battle.message = "SCAN ATTACK"
        case .digiPower:
            battle.message = "SCAN DIGIPOWER DOCK"
        }
        self.battle = battle
        haptic(.start)
    }

    func recordScanBit(_ bit: Int) {
        guard var battle, battle.phase == .scanning, scanBits.count < 3 else { return }
        scanBits.append(bit == 0 ? 0 : 1)
        haptic(.click)
        guard scanBits.count == 3 else { return }
        if scanPurpose == .call {
            summonDock(from: scanBits, battle: &battle)
            self.battle = battle
        } else if scanPurpose == .attack {
            let move = moveForScan(scanBits)
            self.battle = battle
            resolveRound(playerMove: move)
        } else {
            applyDigiPower(from: scanBits, battle: &battle)
            self.battle = battle
        }
    }

    func summonSpirit(_ slot: Int) {
        guard var battle,
              battle.copiedSpirits.indices.contains(slot),
              battle.copiedSpirits[slot],
              state.characterParty.indices.contains(slot / 2),
              state.characterParty[slot / 2] else { return }
        let id = 100 + slot
        let value = combatant(for: id)
        battle.copiedSpirits[slot] = false
        battle.activeDigimonID = id
        battle.activeHP = value.maxHP
        battle.activeMaxHP = value.maxHP
        battle.phase = .chooseAttack
        battle.message = "\(value.name) SPIRIT EVOLUTION"
        self.battle = battle
        haptic(.success)
    }

    func summonAncient(for characterID: Int) {
        guard var battle,
              canUseAncient(characterID),
              state.dPower == 99 else {
            banner = "ANCIENT NEEDS 99 DP"
            haptic(.failure)
            return
        }
        let id = 122 + characterID
        let value = combatant(for: id)
        state.dPower = max(0, state.dPower - 20)
        battle.activeDigimonID = id
        battle.activeHP = value.maxHP
        battle.activeMaxHP = value.maxHP
        battle.prepaidAttack = true
        battle.phase = .chooseAttack
        battle.message = "\(value.name) ANCIENT EVOLUTION"
        self.battle = battle
        haptic(.success)
        save()
    }

    func canUseAncient(_ characterID: Int) -> Bool {
        let first = characterID * 2
        return state.characterParty.indices.contains(characterID)
            && state.characterParty[characterID]
            && state.spiritsObtained.indices.contains(first + 1)
            && state.spiritsObtained[first]
            && state.spiritsObtained[first + 1]
    }

    func summonBattleCode() {
        guard var battle else { return }
        let code = battleCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let digimon = catalog.digimon.first(where: { $0.code?.uppercased() == code }) else {
            battle.message = "CODE ERROR"
            self.battle = battle
            haptic(.failure)
            return
        }
        let initialPower = state.dPower
        let cost = digimon.type == "ancient" ? 20 : dPowerCost
        guard state.dPower >= cost else {
            battle.message = "D-POWER LOW"
            self.battle = battle
            haptic(.failure)
            return
        }
        var summonID = digimon.id
        if digimon.type == "spirit" {
            let owner = max(0, (digimon.id - 100) / 2)
            if !state.characterParty.indices.contains(owner) || !state.characterParty[owner] {
                summonID = 32
            }
        }
        if digimon.type == "ancient" {
            let owner = digimon.id - 122
            if initialPower != 99 || !canUseAncient(owner) {
                summonID = 32
            }
        }
        state.dPower -= cost
        let value = combatant(for: summonID)
        battle.activeDigimonID = summonID
        battle.activeHP = value.maxHP
        battle.activeMaxHP = value.maxHP
        battle.prepaidAttack = value.type == "ancient"
        battle.phase = .chooseAttack
        battle.message = summonID == digimon.id
            ? "\(value.name) CODE CALL"
            : "CODE REJECTED • \(value.name)"
        battleCodeInput = ""
        self.battle = battle
        haptic(.success)
        save()
    }

    func chooseAttack(_ move: Int) {
        resolveRound(playerMove: max(0, min(2, move)))
    }

    func attemptEvolution() {
        guard var battle, battle.result == .none else { return }
        guard !battle.evolvedThisTurn else {
            battle.message = "ONE BOOST PER TURN"
            self.battle = battle
            haptic(.failure)
            return
        }
        guard battle.callPower > 0,
              let activeID = battle.activeDigimonID,
              let source = catalog.digimon.first(where: { $0.id == activeID }) else {
            battle.message = "EVOLUTION LOCKED"
            self.battle = battle
            haptic(.failure)
            return
        }

        battle.evolvedThisTurn = true
        battle.callPower -= 1
        if let evolution = source.evolution,
           evolution >= 0,
           state.digimonUnlocked.indices.contains(evolution),
           state.digimonUnlocked[evolution],
           Int.random(in: 0...100) > 50 {
            let evolved = combatant(for: evolution)
            battle.activeDigimonID = evolution
            battle.activeHP = evolved.maxHP
            battle.activeMaxHP = evolved.maxHP
            battle.message = "EVOLVED • \(evolved.name)"
            haptic(.success)
        } else {
            battle.message = "EVOLUTION FAILED"
            haptic(.failure)
        }
        self.battle = battle
    }

    func swapActiveDigimon() {
        guard var battle, battle.result == .none else { return }
        battle.activeDigimonID = nil
        battle.activeHP = 0
        battle.activeMaxHP = 0
        battle.phase = .command
        battle.message = "DIGIMON DEPORTED"
        self.battle = battle
        haptic(.directionDown)
    }

    func escapeBattle() {
        guard var battle, battle.result == .none else { return }
        if battle.isBoss || battle.isFinalBoss {
            battle.message = "NO ESCAPE FROM BOSS"
            self.battle = battle
            haptic(.failure)
            return
        }
        battle.result = .escaped
        battle.phase = .result
        if Int.random(in: 0...100) >= 30 {
            state.distance += 500
            battle.message = "ESCAPED • +500 DIST"
        } else {
            battle.message = "ESCAPED"
        }
        self.battle = battle
        haptic(.directionDown)
        save()
    }

    func captureEnemy() {
        guard var battle, battle.phase == .capture else { return }
        unlockDigimon(battle.enemyID, addToDock: true)
        battle.capturedID = battle.enemyID
        battle.result = .win
        battle.phase = .result
        battle.message = "\(combatant(for: battle.enemyID).name) CAPTURED"
        self.battle = battle
        haptic(.success)
        save()
    }

    func continueAfterBattle() {
        let returnsToMap = battle?.result == .win
            && (battle?.isBoss == true || battle?.isFinalBoss == true)
        battle = nil
        scanBits = []
        if !endingMessage.isEmpty {
            screen = .ending
        } else if returnsToMap {
            screen = .map
        } else {
            screen = .home
        }
        scheduleEncounterNotification()
        save()
    }

    func startDigiStorm() {
        state.lastEncounterWasBattle = false
        let missing = state.charactersUnlocked.indices.filter {
            state.charactersUnlocked[$0] && !state.characterParty[$0]
        }
        if !missing.isEmpty {
            for id in missing { state.characterParty[id] = true }
            storm = DigiStormSession(taps: 0, target: 40, outcome: .partyRecovered(missing))
            banner = "PARTY RECOVERED"
        } else {
            storm = DigiStormSession()
            banner = "TAP TO RESIST"
        }
        screen = .digiStorm
        haptic(.notification)
        save()
    }

    func tapDigiStorm() {
        guard var storm, storm.outcome == .active else { return }
        storm.taps = min(storm.target, storm.taps + 1)
        self.storm = storm
        haptic(.click)
    }

    func resolveDigiStorm() {
        guard var storm, storm.outcome == .active else { return }
        let partyOthers = state.characterParty.indices.filter {
            $0 != state.currentCharacter && state.characterParty[$0]
        }
        if partyOthers.count <= 1 {
            storm.outcome = .safe
        } else if storm.taps >= storm.target {
            if Int.random(in: 0...100) > 80 {
                let area = randomUnclearedArea()
                state.currentArea = area
                state.distance += 500
                storm.outcome = .teleported(area)
            } else {
                storm.outcome = .safe
            }
        } else {
            let includeCurrent = Int.random(in: 0...100) > 80
            var lost = [Int]()
            repeat {
                lost.removeAll()
                for id in partyOthers {
                    let selected = Int.random(in: 0...100) > 50
                    if (!includeCurrent && selected) || (includeCurrent && !selected) {
                        lost.append(id)
                    }
                }
            } while lost.isEmpty
            for id in lost {
                state.characterParty[id] = false
            }
            storm.lostParty = lost
            if includeCurrent {
                let area = randomUnclearedArea()
                state.currentArea = area
                state.distance += 500
                storm.outcome = .teleported(area)
            } else {
                storm.outcome = .partyLost(lost)
            }
        }
        self.storm = storm
        haptic(storm.taps >= storm.target ? .success : .failure)
        save()
    }

    func continueAfterStorm() {
        let wasTeleported: Bool
        if case .teleported = storm?.outcome {
            wasTeleported = true
        } else {
            wasTeleported = false
        }
        storm = nil
        screen = wasTeleported ? .map : .home
        banner = ""
        scheduleEncounterNotification()
    }

    func finishBonusPresentation() {
        bonusPresentation = nil
    }

    func redeemCode() {
        let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let digimon = catalog.digimon.first(where: { $0.code?.uppercased() == code }) else {
            banner = "INVALID DIGI-CODE"
            haptic(.failure)
            return
        }
        if digimon.type == "spirit", (100...111).contains(digimon.id) {
            let slot = digimon.id - 100
            grantSpirit(slot)
        } else {
            unlockDigimon(digimon.id, addToDock: digimon.level != -4)
        }
        if !state.codesRedeemed.contains(code) { state.codesRedeemed.append(code) }
        banner = "\(digimon.displayName) UNLOCKED"
        codeInput = ""
        haptic(.success)
        save()
    }

    func startMiniGame(_ kind: MiniGameSession.Kind) {
        let dockDigimon = state.docks.filter { $0 >= 0 }.randomElement()
        miniGame = MiniGameSession(
            kind: kind,
            usedDigimonID: kind == .digiDigit ? (dockDigimon ?? 32) : nil
        )
        screen = kind == .digiDigit ? .digiDigit : .digiShip
        banner = ""
    }

    func playDigiDigit(move: Int) {
        guard var game = miniGame, game.kind == .digiDigit, !game.finished else { return }
        if move == game.targetMove {
            game.score = 1
            let reward = Int.random(in: 0...100)
            if reward <= 60 {
                applyRandomBonus()
                game.message = "BOX BREAK • \(banner)"
            } else if reward <= 90,
                      let target = catalog.digimon.filter({ $0.isEncounterEligible }).randomElement() {
                unlockDigimon(target.id, addToDock: true)
                game.message = "CAPTURE • \(target.displayName)"
            } else {
                game.message = "BOX EMPTY"
            }
            haptic(.success)
        } else {
            let dockCount = state.docks.filter { $0 >= 0 }.count
            let penalty = Int.random(in: 0...100)
            if dockCount <= 1 || penalty <= 50 {
                state.distance += 300
                game.message = "SCAN MISS • DIST +300"
            } else if penalty <= 90 {
                game.message = "SCAN MISS"
            } else if let usedID = game.usedDigimonID {
                if state.digimonUnlocked.indices.contains(usedID) {
                    state.digimonUnlocked[usedID] = false
                }
                state.docks = state.docks.map { $0 == usedID ? -1 : $0 }
                game.message = "DATA LOST • \(combatant(for: usedID).name)"
            }
            haptic(.failure)
        }
        game.finished = true
        state.digiDigitHighScore = max(state.digiDigitHighScore, game.score)
        save()
        miniGame = game
    }

    func playDigiShip(lane: Int) {
        guard var game = miniGame, game.kind == .digiShip, !game.finished else { return }
        let blockedLane = game.targetMove
        if lane == blockedLane {
            game.lives -= 1
            game.score -= 5
            game.message = "COLLISION • -5"
            haptic(.failure)
        } else {
            game.score += 1
            game.message = "ROW CLEAR • +1"
            haptic(.directionUp)
        }
        game.round += 1
        game.targetMove = [0, 1, 2].filter { $0 != blockedLane }.randomElement() ?? 0
        if game.round > 44 || game.lives <= 0 {
            finishMiniGame(&game)
        }
        miniGame = game
    }

    func closeMiniGame() {
        miniGame = nil
        screen = .games
        save()
    }

    func activateTV() {
        state.tvRewards += 1
        let roll = Int.random(in: 0...100)
        switch GameRules.tvOutcome(roll: roll) {
        case .bonus:
            applyRandomBonus()
            haptic(.success)
            save()
        case .capture:
            if let target = catalog.digimon.filter({ $0.isEncounterEligible }).randomElement() {
                unlockDigimon(target.id, addToDock: true)
                banner = "TV SIGNAL • \(target.displayName)"
                haptic(.success)
                save()
            }
        case .battle:
            startBattle()
        case .storm:
            startDigiStorm()
        }
    }

    func importLinkCode() {
        let compact = connectCodeInput
            .uppercased()
            .filter { $0.isHexDigit }
        guard compact.count == 14 else {
            connectMessage = "CODE MUST BE 14 HEX"
            haptic(.failure)
            return
        }
        var values = [Int]()
        var index = compact.startIndex
        for _ in 0..<7 {
            let next = compact.index(index, offsetBy: 2)
            guard let value = Int(compact[index..<next], radix: 16) else {
                connectMessage = "LINK CODE ERROR"
                return
            }
            values.append(value)
            index = next
        }
        guard values[0] == 1, values.prefix(6).reduce(0, ^) == values[6] else {
            connectMessage = "CHECKSUM ERROR"
            haptic(.failure)
            return
        }
        connectOpponent = values[2...5].map { $0 == 0 ? -1 : $0 - 1 }
        connectRound = 1
        connectPlayerScore = 0
        connectOpponentScore = 0
        connectMessage = "OFFLINE CODE LOADED"
        screen = .connectBattle
        haptic(.success)
    }

    func quickLinkBattle() {
        connectOpponent = Array(catalog.digimon.filter { $0.isEncounterEligible }.shuffled().prefix(4).map(\.id))
        while connectOpponent.count < 4 { connectOpponent.append(32) }
        connectRound = 1
        connectPlayerScore = 0
        connectOpponentScore = 0
        connectMessage = "OFFLINE TRAINING"
        screen = .connectBattle
    }

    func playConnectMove(_ move: Int) {
        guard connectRound > 0, connectRound <= 5 else { return }
        let enemyMove = Int.random(in: 0...2)
        if move == enemyMove {
            connectMessage = "ROUND \(connectRound) • DRAW"
        } else if GameRules.beats(move, enemyMove) {
            connectPlayerScore += 1
            connectMessage = "ROUND \(connectRound) • WIN"
            haptic(.directionUp)
        } else {
            connectOpponentScore += 1
            connectMessage = "ROUND \(connectRound) • LOSE"
            haptic(.directionDown)
        }
        connectRound += 1
        if connectRound > 5 {
            if connectPlayerScore > connectOpponentScore {
                state.connectWins += 1
                connectMessage = "LINK BATTLE CLEAR"
                haptic(.success)
            } else if connectPlayerScore == connectOpponentScore {
                connectMessage = "LINK BATTLE DRAW"
            } else {
                connectMessage = "LINK BATTLE LOST"
                haptic(.failure)
            }
            save()
        }
    }

    func finishEnding() {
        endingMessage = ""
        screen = .characterSelect
        save()
    }

    func setSoundEnabled(_ enabled: Bool) {
        state.soundEnabled = enabled
        save()
    }

    func setHapticsEnabled(_ enabled: Bool) {
        state.hapticsEnabled = enabled
        if enabled { haptic(.click) }
        save()
    }

    func setGridEnabled(_ enabled: Bool) {
        state.gridEnabled = enabled
        save()
    }

    func setPalette(_ index: Int) {
        state.paletteIndex = max(0, min(5, index))
        save()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        state.notificationsEnabled = enabled
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.state.notificationsEnabled = granted
                    if granted { self.scheduleEncounterNotification() }
                    self.save()
                }
            }
        } else {
            cancelEncounterNotification()
            save()
        }
    }

    func resetGame() {
        let settings = state
        var fresh = FullSaveState()
        fresh.paletteIndex = settings.paletteIndex
        fresh.soundEnabled = settings.soundEnabled
        fresh.hapticsEnabled = settings.hapticsEnabled
        fresh.gridEnabled = settings.gridEnabled
        fresh.notificationsEnabled = settings.notificationsEnabled
        fresh.normalize(for: catalog)
        state = fresh
        pendingEncounter = nil
        battle = nil
        storm = nil
        miniGame = nil
        endingMessage = ""
        screen = .boot
        cancelEncounterNotification()
        UserDefaults.standard.removeObject(forKey: saveKey)
        UserDefaults.standard.removeObject(forKey: backupSaveKey)
        save()
    }

    func save() {
        state.lastSaved = Date()
        if let data = try? JSONEncoder().encode(state) {
            let defaults = UserDefaults.standard
            if let previous = defaults.data(forKey: saveKey), previous != data {
                defaults.set(previous, forKey: backupSaveKey)
            }
            defaults.set(data, forKey: saveKey)
        }
    }

    func combatant(for id: Int) -> Combatant {
        guard let source = catalog.digimon.first(where: { $0.id == id }) else {
            return Combatant(
                id: id,
                name: "UNKNOWN",
                sprite: "spr_question_dtector",
                type: "rookie",
                level: 1,
                maxHP: 30,
                energy: 10,
                crunch: 10,
                ability: 10,
                evolution: nil
            )
        }

        var hp = source.hp
        var energy = source.energy
        var crunch = source.crunch
        var ability = source.ability
        if let formula = spiritFormula(for: id),
           state.characterStats.indices.contains(formula.character) {
            let stats = state.characterStats[formula.character]
            hp = stats.hp + formula.hp
            energy = stats.spirit + formula.energy
            crunch = stats.stamina + formula.crunch
            ability = stats.skill + formula.ability
        }

        return Combatant(
            id: id,
            name: source.displayName,
            sprite: source.sprite,
            type: source.type,
            level: source.level,
            maxHP: max(1, hp),
            energy: max(1, energy),
            crunch: max(1, crunch),
            ability: max(1, ability),
            evolution: (source.evolution ?? -1) >= 0 ? source.evolution : nil
        )
    }

    private func receivePedometer(_ total: Int) {
        let day = Self.dayKey(Date())
        if state.motionDay != day {
            state.motionDay = day
            state.lastMotionTotal = total
            save()
            return
        }
        let delta = max(0, total - state.lastMotionTotal)
        state.lastMotionTotal = max(state.lastMotionTotal, total)
        if delta > 0 { addSteps(delta) }
    }

    private func selectEnemyID() -> Int {
        if state.distance == 0, state.currentArea == 12 {
            if state.newGamePlus {
                return state.lastBossUnlocked ? 130 : 128
            }
            return state.lastBossUnlocked ? 127 : 120
        }
        if state.distance == 0 {
            let area = currentArea
            if let dependency = area.bossUpgradeDependencyArea,
               state.areaCleared.indices.contains(dependency),
               state.areaCleared[dependency],
               let upgraded = area.bossUpgraded {
                return upgraded
            }
            return area.bossPrimary ?? 32
        }

        let targetLevel = min(70, state.level)
        let possible = catalog.digimon.filter {
            $0.isEncounterEligible && ($0.level - targetLevel) >= 5 && ($0.level - targetLevel) <= 10
        }
        return possible.randomElement()?.id ?? 32
    }

    private func summonDock(from bits: [Int], battle: inout BattleSession) {
        let slot = dockSlotForScan(bits)
        var selected = battle.copiedDocks.indices.contains(slot) ? battle.copiedDocks[slot] : -1
        if selected < 0 { selected = 32 }
        let chosen = combatant(for: selected)
        let cost = selected == 32 ? 2 : callCost(for: chosen.level)
        if selected != 32 && cost <= battle.callPower + 2 && battle.callPower > 0 {
            battle.callPower = max(0, battle.callPower - cost)
            battle.copiedDocks[slot] = -1
        } else {
            battle.callPower = max(0, battle.callPower - 2)
            selected = 32
        }
        let summoned = combatant(for: selected)
        battle.activeDigimonID = selected
        battle.activeHP = summoned.maxHP
        battle.activeMaxHP = summoned.maxHP
        battle.phase = .chooseAttack
        battle.message = "\(summoned.name) • CALL \(battle.callPower)"
        haptic(.success)
    }

    private func applyDigiPower(from bits: [Int], battle: inout BattleSession) {
        guard let activeID = battle.activeDigimonID,
              combatant(for: activeID).type == "spirit" else {
            battle.phase = .chooseAttack
            battle.message = "DIGIPOWER NEEDS SPIRIT"
            haptic(.failure)
            return
        }
        guard !battle.evolvedThisTurn else {
            battle.phase = .chooseAttack
            battle.message = "ONE BOOST PER TURN"
            haptic(.failure)
            return
        }
        guard state.dPower >= dPowerCost else {
            battle.phase = .chooseAttack
            battle.message = "D-POWER LOW"
            haptic(.failure)
            return
        }

        let slot = dockSlotForScan(bits)
        var selected = battle.copiedDocks.indices.contains(slot) ? battle.copiedDocks[slot] : -1
        if selected < 0 { selected = 32 }
        let helper = combatant(for: selected)
        let cost = selected == 32 ? 2 : callCost(for: helper.level)
        if selected != 32 && cost <= battle.callPower + 2 && battle.callPower > 0 {
            battle.callPower = max(0, battle.callPower - cost)
            battle.copiedDocks[slot] = -1
        } else {
            battle.callPower = max(0, battle.callPower - 2)
            selected = 32
        }

        state.dPower -= dPowerCost
        let assist = combatant(for: selected)
        let succeeds = Int.random(in: 0...100) < 50 + state.level - assist.level
        if succeeds {
            battle.energyBonus = assist.energy
            battle.crunchBonus = assist.crunch
            battle.abilityBonus = assist.ability
            battle.message = "DIGIPOWER • \(assist.name)"
            haptic(.success)
        } else {
            battle.message = "DIGIPOWER FAILED"
            haptic(.failure)
        }
        battle.evolvedThisTurn = true
        battle.phase = .chooseAttack
        save()
    }

    private func dockSlotForScan(_ bits: [Int]) -> Int {
        GameRules.dockSlot(for: bits)
    }

    private func callCost(for digimonLevel: Int) -> Int {
        GameRules.callCost(levelDifference: digimonLevel - state.level)
    }

    private func moveForScan(_ bits: [Int]) -> Int {
        GameRules.moveForScan(bits, fallback: Int.random(in: 0...2))
    }

    private func resolveRound(playerMove: Int) {
        guard var battle,
              battle.result == .none,
              let activeID = battle.activeDigimonID else { return }
        let mine = combatant(for: activeID)
        let enemy = combatant(for: battle.enemyID)
        let previousEnemyMove = battle.enemyMove
        var choices = [0, 1, 2].filter { $0 != previousEnemyMove }
        if Bool.random() { choices.append(previousEnemyMove) }
        let enemyMove = choices.randomElement() ?? Int.random(in: 0...2)
        battle.mineMove = playerMove
        battle.enemyMove = enemyMove
        battle.round += 1
        battle.phase = .resolving

        let playerCost: Int
        if mine.type == "ancient" {
            playerCost = battle.prepaidAttack ? 0 : 20
            battle.prepaidAttack = false
        } else if mine.type == "spirit" {
            playerCost = dPowerCost
        } else {
            playerCost = 0
        }
        guard state.dPower >= playerCost else {
            battle.activeDigimonID = nil
            battle.activeHP = 0
            battle.activeMaxHP = 0
            battle.phase = .command
            battle.message = "D-POWER EMPTY • SPIRIT OFF"
            self.battle = battle
            haptic(.failure)
            return
        }
        state.dPower -= playerCost

        let comparisonMineStats = [
            mine.energy + battle.energyBonus,
            mine.crunch + battle.crunchBonus,
            mine.ability + battle.abilityBonus
        ]
        let outcome = GameRules.combatOutcome(
            playerMove: playerMove,
            enemyMove: enemyMove,
            playerStat: comparisonMineStats[playerMove],
            enemyStat: enemy.stat(for: enemyMove),
            controlLevelExceeded: mine.type != "spirit"
                && mine.type != "ancient"
                && mine.level - state.level > 19
        )

        if outcome > 0 {
            let rawDamage = comparisonMineStats[playerMove]
            let damage = battle.enemyID == 130 ? max(0, rawDamage - 120) : rawDamage
            battle.enemyHP = max(0, battle.enemyHP - damage)
            battle.message = "\(moveName(playerMove)) HIT \(damage)"
            haptic(.directionUp)
        } else if outcome < 0 {
            let rawDamage = enemy.stat(for: enemyMove)
            let damage = mine.type == "ancient"
                ? Int((Double(rawDamage) / 2).rounded())
                : rawDamage
            battle.activeHP = max(0, battle.activeHP - damage)
            battle.message = "\(moveName(enemyMove)) DAMAGE \(damage)"
            haptic(.directionDown)
        } else {
            battle.message = "COLLISION • DRAW"
            haptic(.click)
        }
        battle.energyBonus = 0
        battle.crunchBonus = 0
        battle.abilityBonus = 0
        battle.evolvedThisTurn = false
        if outcome != 0 && mine.type != "spirit" && mine.type != "ancient" {
            state.dPower = min(99, state.dPower + 3)
        }

        self.battle = battle
        if battle.enemyHP == 0 {
            if battle.enemyID == 120 || battle.enemyID == 128 {
                let evolvedID = battle.enemyID == 120 ? 121 : 129
                let evolved = combatant(for: evolvedID)
                battle.enemyID = evolvedID
                battle.enemyHP = evolved.maxHP
                battle.phase = .chooseAttack
                battle.message = "ENEMY EVOLVED • \(evolved.name)"
                self.battle = battle
                haptic(.notification)
            } else {
                completeBattleWin()
            }
        } else if battle.activeHP == 0 {
            completeBattleLoss()
        } else if mine.type == "ancient" {
            if state.dPower >= 20 {
                battle.prepaidAttack = true
                state.dPower -= 20
                battle.phase = .chooseAttack
            } else {
                battle.activeDigimonID = nil
                battle.activeHP = 0
                battle.activeMaxHP = 0
                battle.phase = .command
                battle.message += " • ANCIENT OFF"
            }
            self.battle = battle
        } else if mine.type == "spirit" && state.dPower < dPowerCost {
            battle.activeDigimonID = nil
            battle.activeHP = 0
            battle.activeMaxHP = 0
            battle.phase = .command
            battle.message += " • SPIRIT OFF"
            self.battle = battle
        } else {
            battle.phase = .chooseAttack
            self.battle = battle
        }
        save()
    }

    private func completeBattleWin() {
        guard var battle else { return }
        state.wins += 1
        state.nextLevelUp -= 1
        if state.nextLevelUp <= 0 && state.level < 99 {
            levelUp()
            battle.levelChange = 1
        }

        if battle.isBoss || battle.isFinalBoss {
            handleBossWin(&battle)
            battle.result = .win
            battle.phase = .result
        } else if let recovered = state.spiritsUnlocked.indices.filter({
            state.spiritsUnlocked[$0] && !state.spiritsObtained[$0]
        }).randomElement() {
            state.spiritsObtained[recovered] = true
            battle.result = .win
            battle.phase = .result
            battle.message = "SPIRIT \(recovered + 1) RECOVERED"
        } else if Int.random(in: 0...100) < 50 {
            battle.phase = .capture
            battle.message = "CAPTURE SIGNAL READY"
        } else {
            battle.result = .win
            battle.phase = .result
            battle.message = "BATTLE CLEAR"
        }
        self.battle = battle
        haptic(.success)
    }

    private func completeBattleLoss() {
        guard var battle else { return }
        state.nextLevelDown -= 1
        if state.nextLevelDown <= 0 && state.level > 1 {
            levelDown()
            battle.levelChange = -1
        }
        state.distance += 500
        battle.result = .lose
        battle.phase = .result
        battle.message = "SYSTEM DOWN • +500 DIST"

        if Int.random(in: 0...100) < 50 {
            state.defeated = true
            if let activeID = battle.activeDigimonID {
                let active = combatant(for: activeID)
                if active.type == "spirit" || active.type == "ancient" {
                    if let slot = state.spiritsObtained.indices.filter({
                        state.spiritsObtained[$0]
                    }).randomElement() {
                        state.spiritsObtained[slot] = false
                        battle.lostSpiritID = slot
                        battle.message += " • SPIRIT LOST"
                    }
                } else if state.docks.filter({ $0 >= 0 }).count > 1 {
                    if state.digimonUnlocked.indices.contains(activeID) {
                        state.digimonUnlocked[activeID] = false
                    }
                    state.docks = state.docks.map { $0 == activeID ? -1 : $0 }
                    battle.message += " • DATA LOST"
                }
            }
        }
        self.battle = battle
        haptic(.failure)
    }

    private func handleBossWin(_ battle: inout BattleSession) {
        if battle.isFinalBoss {
            unlockDigimon(battle.enemyID, addToDock: false)
            if !state.lastBossUnlocked {
                if state.newGamePlus {
                    unlockDigimon(128, addToDock: false)
                    unlockDigimon(129, addToDock: false)
                } else {
                    unlockDigimon(120, addToDock: false)
                    unlockDigimon(121, addToDock: false)
                }
                state.lastBossUnlocked = true
                state.distance = 50
                battle.message = "FINAL PHASE UNLOCKED • 50"
                return
            }

            if !state.newGamePlus {
                unlockDigimon(127, addToDock: false)
                state.charactersUnlocked[5] = true
                state.characterParty[5] = true
                grantSpirit(10)
                grantSpirit(11)
                endingMessage = "KOICHI JOINED\nDARKNESS SPIRITS UNLOCKED"
            } else {
                unlockDigimon(128, addToDock: false)
                unlockDigimon(129, addToDock: false)
                unlockDigimon(130, addToDock: false)
                endingMessage = "LUCEMON ROUTE CLEAR\nNEW GAME+ COMPLETE"
            }
            state.completedRuns += 1
            state.newGamePlus = true
            state.areaCleared = Array(repeating: false, count: 13)
            state.lastBossUnlocked = false
            state.currentArea = 0
            state.distance = catalog.areas.first?.distance ?? 6000
            battle.message = "ADVENTURE COMPLETE"
            return
        }

        let canonical: Int
        switch battle.enemyID {
        case 131: canonical = 112
        case 132: canonical = 113
        case 133: canonical = 114
        case 134: canonical = 115
        case 135: canonical = 116
        case 136: canonical = 117
        case 137: canonical = 118
        case 138: canonical = 119
        default: canonical = battle.enemyID
        }
        unlockDigimon(canonical, addToDock: false)
        if let spirit = spiritUnlocked(by: canonical),
           state.spiritsUnlocked.indices.contains(spirit),
           !state.spiritsUnlocked[spirit] {
            grantSpirit(spirit)
            battle.message = "BOSS CLEAR • SPIRIT \(spirit + 1)"
        } else if let reward = catalog.digimon.filter({ $0.isEncounterEligible }).randomElement() {
            unlockDigimon(reward.id, addToDock: true)
            battle.capturedID = reward.id
            battle.message = "BOSS CLEAR • \(reward.displayName)"
        }
        clearCurrentArea()
    }

    private func clearCurrentArea() {
        if state.areaCleared.indices.contains(state.currentArea) {
            state.areaCleared[state.currentArea] = true
        }
        if state.areaCleared.prefix(12).allSatisfy({ $0 }) {
            state.currentArea = 12
            state.distance = catalog.areas.first(where: { $0.id == 12 })?.distance ?? 12_000
            GameAudio.shared.play(
                "sound_change_final_map_dtector",
                enabled: state.soundEnabled
            )
            return
        }

        let groupStart = (state.currentArea / 3) * 3
        let groupEnd = min(groupStart + 2, 11)
        if let next = (groupStart...groupEnd).first(where: { !state.areaCleared[$0] }) {
            state.currentArea = next
        } else if let next = (0..<12).first(where: { !state.areaCleared[$0] }) {
            state.currentArea = next
        }
        state.distance = catalog.areas.first(where: { $0.id == state.currentArea })?.distance ?? 6000
        GameAudio.shared.play(
            "sound_change",
            enabled: state.soundEnabled
        )
    }

    private func unlockDigimon(_ id: Int, addToDock: Bool) {
        guard state.digimonUnlocked.indices.contains(id) else { return }
        let wasLocked = !state.digimonUnlocked[id]
        state.digimonUnlocked[id] = true
        guard wasLocked, addToDock, !state.docks.contains(id),
              let empty = state.docks.firstIndex(of: -1) else { return }
        state.docks[empty] = id
    }

    private func grantSpirit(_ slot: Int) {
        guard state.spiritsUnlocked.indices.contains(slot),
              state.spiritsObtained.indices.contains(slot) else { return }
        state.spiritsUnlocked[slot] = true
        state.spiritsObtained[slot] = true
    }

    private func spiritUnlocked(by bossID: Int) -> Int? {
        switch bossID {
        case 112: return 4
        case 113: return 5
        case 114: return 8
        case 115: return 9
        case 116: return 2
        case 117: return 0
        case 118: return 6
        case 119: return 7
        case 96, 98: return 1
        case 97, 99: return 3
        default: return nil
        }
    }

    private func levelUp() {
        state.level = min(99, state.level + 1)
        state.nextLevelUp = 5
        state.nextLevelDown = 5
        for index in state.characterStats.indices {
            let definition = catalog.characters.indices.contains(index)
                ? catalog.characters[index]
                : CharacterDefinition.defaults[index]
            state.characterStats[index].hp = min(definition.capHP, state.characterStats[index].hp + Int.random(in: 1...4))
            state.characterStats[index].spirit = min(definition.capSpirit, state.characterStats[index].spirit + Int.random(in: 1...4))
            state.characterStats[index].stamina = min(definition.capStamina, state.characterStats[index].stamina + Int.random(in: 1...4))
            state.characterStats[index].skill = min(definition.capSkill, state.characterStats[index].skill + Int.random(in: 1...4))
        }
        banner = "LEVEL UP • \(state.level)"
    }

    private func levelDown() {
        state.level = max(1, state.level - 1)
        state.nextLevelUp = 5
        state.nextLevelDown = 5
        for index in state.characterStats.indices {
            state.characterStats[index].hp = max(0, state.characterStats[index].hp - Int.random(in: 0...3) + 1)
            state.characterStats[index].spirit = max(0, state.characterStats[index].spirit - Int.random(in: 0...3) + 1)
            state.characterStats[index].stamina = max(0, state.characterStats[index].stamina - Int.random(in: 0...3) + 1)
            state.characterStats[index].skill = max(0, state.characterStats[index].skill - Int.random(in: 0...3) + 1)
        }
        banner = "LEVEL DOWN • \(state.level)"
    }

    private func finishMiniGame(_ game: inout MiniGameSession) {
        game.finished = true
        if game.kind == .digiDigit {
            state.digiDigitHighScore = max(state.digiDigitHighScore, game.score)
        } else {
            game.score = max(0, game.score)
            state.digiShipHighScore = max(state.digiShipHighScore, game.score)
            let reduction = game.score * 10
            state.distance = max(1, state.distance - reduction)
            game.message = "FINISH • DIST -\(reduction)"
        }
        save()
    }

    private func applyRandomBonus() {
        if state.level >= 99 {
            GameAudio.shared.play(
                "sound_bonus_dtector",
                enabled: state.soundEnabled
            )
            state.distance = max(1, state.distance - 500)
            banner = "DISTANCE -500"
            bonusPresentation = BonusPresentation(
                type: 0,
                value: state.distance,
                startedAt: Date()
            )
            return
        }
        let roll = Int.random(in: 0...100)
        let outcome = GameRules.bonusOutcome(roll: roll)
        let type: Int
        switch outcome {
        case .distanceMinus500: type = 0
        case .distancePlus300: type = 1
        case .dPowerPlus10: type = 2
        case .levelUp: type = 3
        }
        GameAudio.shared.play(
            type == 3
                ? "sound_level_up_dtector"
                : "sound_bonus_dtector",
            enabled: state.soundEnabled
        )
        switch outcome {
        case .distanceMinus500:
            state.distance = max(1, state.distance - 500)
            banner = "DISTANCE -500"
        case .distancePlus300:
            state.distance += 300
            banner = "DISTANCE +300"
        case .dPowerPlus10:
            state.dPower = min(99, state.dPower + 10)
            banner = "D-POWER +10"
        case .levelUp:
            levelUp()
        }
        let value = type == 2
            ? state.dPower
            : type == 3
                ? state.level
                : state.distance
        bonusPresentation = BonusPresentation(
            type: type,
            value: value,
            startedAt: Date()
        )
    }

    private func randomUnclearedArea() -> Int {
        let values = (0..<min(12, state.areaCleared.count)).filter { !state.areaCleared[$0] }
        return values.randomElement() ?? state.currentArea
    }

    private func moveName(_ move: Int) -> String {
        switch move {
        case 0: "ENERGY"
        case 1: "CRUNCH"
        default: "ABILITY"
        }
    }

    private func spiritFormula(for id: Int) -> (character: Int, hp: Int, energy: Int, crunch: Int, ability: Int)? {
        switch id {
        case 100: return (0, 75, 40, 25, 30)
        case 101: return (0, 120, 35, 50, 40)
        case 102: return (1, 75, 25, 30, 45)
        case 103: return (1, 120, 50, 50, 25)
        case 104: return (2, 80, 25, 50, 20)
        case 105: return (2, 120, 40, 60, 25)
        case 131: return (2, 100, 25, 20, 50)
        case 132: return (2, 150, 25, 60, 50)
        case 106: return (3, 70, 25, 20, 50)
        case 107: return (3, 110, 40, 35, 60)
        case 137: return (3, 90, 60, 20, 25)
        case 138: return (3, 120, 25, 80, 30)
        case 108: return (4, 70, 30, 30, 30)
        case 109: return (4, 130, 40, 50, 35)
        case 133: return (4, 80, 35, 35, 35)
        case 134: return (4, 120, 55, 20, 55)
        case 110: return (5, 75, 45, 30, 25)
        case 111: return (5, 120, 25, 50, 50)
        case 135: return (5, 50, 50, 20, 40)
        case 136: return (5, 70, 25, 70, 60)
        default: return nil
        }
    }

    private func haptic(_ type: WKHapticType) {
        guard state.hapticsEnabled else { return }
        WKInterfaceDevice.current().play(type)
    }

    private func scheduleEncounterNotification() {
        guard state.notificationsEnabled, pendingEncounter == nil, state.hasStarted else { return }
        let content = UNMutableNotificationContent()
        content.title = "D‑Tector"
        content.body = "\(distanceToNextEvent) steps until the next signal"
        if state.soundEnabled { content.sound = .default }
        let estimatedSeconds = max(60, Double(max(1, distanceToNextEvent)) * 0.6)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: estimatedSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: "next-encounter", content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["next-encounter"])
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelEncounterNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["next-encounter"])
    }

    private static func dayKey(_ date: Date) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(values.year ?? 0)-\(values.month ?? 0)-\(values.day ?? 0)"
    }
}
