import AVFoundation
import CoreMotion
import Foundation
import SwiftUI

enum UnityDTScreen: String, Codable {
    case charSelection
    case character
    case mainMenu
    case app
    case battle
    case result
}

enum UnityDTApp: String, Codable, CaseIterable {
    case map
    case status
    case game
    case database
    case digits
    case camp
    case connect
    // Added by the port: two browsers over data the game already has.
    case evolve
    case fusion

    static let visibleMainMenuCases: [UnityDTApp] = [
        .map,
        .status,
        .game,
        .database,
        .digits,
        .camp,
        .connect,
    ]

    var title: String {
        switch self {
        case .map: return "MAP"
        case .status: return "STATUS"
        case .game: return "GAME"
        case .database: return "DATABASE"
        case .digits: return "DIGITS"
        case .camp: return "CAMP"
        case .connect: return "CONNECT"
        case .evolve: return "EVOLVE"
        case .fusion: return "FUSION"
        }
    }

    var mainMenuSpriteIndex: Int {
        switch self {
        case .map: return 0
        case .status: return 1
        case .game: return 2
        case .database: return 3
        case .digits: return 4
        case .camp: return 5
        case .connect: return 6
        case .evolve: return 7
        case .fusion: return 8
        }
    }
}

enum UnityDTBattleScreen: String, Codable {
    case mainMenu
    case ddocks
    case spiritElements
    case spiritGallery
    case digits
    case combatMenu
    case attackMenu
    case regularEvolve
}

enum UnityDTMapScreen: String, Codable {
    case map
    case areaSelection
    case distance
}

enum UnityDTDatabaseScreen: String, Codable {
    case menu
    case spiritMenu
    case gallery
    case pages
    case ddockList
    case ddockDisplay
}

struct UnityDTStats: Codable, Hashable {
    let HP: Int
    let EN: Int
    let CR: Int
    let AB: Int

    var total: Int { HP + EN + CR + AB }
}

struct UnityDTDigimon: Codable, Identifiable, Hashable {
    let number: Int
    let order: Int
    let name: String
    let stage: Int
    let spiritType: Int
    let abilityName: String
    let element: Int
    let evolution: String?
    let extraEvolutions: [String]?
    let disabled: Bool
    let baseLevel: Int
    let stats: UnityDTStats
    let bossStats: UnityDTStats?
    let isPseudo: Bool
    let code: String?

    var id: String { name }
    var displayName: String { name.replacingOccurrences(of: "_", with: " ").uppercased() }
    var battleStats: UnityDTStats { bossStats ?? stats }
}

struct UnityDTRarity: Codable, Hashable {
    let digimon: String
    let rarity: Int
    let exclusive: Bool
}

struct UnityDTCoord: Codable, Hashable {
    let x: Int
    let y: Int
}

struct UnityDTArea: Codable, Hashable {
    let number: Int
    let map: Int
    let distance: Int
    let coords: UnityDTCoord
}

struct UnityDTWorld: Codable, Hashable {
    let number: Int
    let multiMap: Bool?
    let worldSprite: String
    let shuffle: Bool?
    let areas: [UnityDTArea]
    let bosses: [String]
    let removePlayer: Bool?
    let bossMode: String?
    let showEyes: Bool?
    let lockTravel: Bool?
    let semibossMode: String?
    let semibosses: [[String]]?
}

struct UnityDTBattleState: Codable, Hashable {
    var enemyName: String
    var playerName: String
    var playerHP: Int
    var playerMaxHP: Int
    var enemyHP: Int
    var enemyMaxHP: Int
    var playerEN: Int
    var enemyEN: Int
    var playerLevel: Int
    var enemyLevel: Int
    var turn: Int
    var message: String
    var flash: Int
    var victory: Bool
    var defeat: Bool
    var boss: Bool
    var screen: UnityDTBattleScreen
    var menuIndex: Int
    var ddockIndex: Int
    var combatMenuIndex: Int
    var attackIndex: Int
    var callPoints: Int
    var combatOptions: [Int]
    var callPointsForEvolution: Int
    var ddockPurpose: Int
    var spiritElementIndex: Int
    var spiritGalleryIndex: Int
    var codeSelectedAscii: Int
    var codeInput: String
    var codeStatus: Int
    var friendlyStats: UnityDTMutableStats?
    var enemyStats: UnityDTMutableStats
    var originalPlayerName: String
    var lastFriendlyAttack: Int?
    var lastEnemyAttack: Int?
    /// Battle.cs attacksAwardSP / attacksCostSP.
    var attacksAwardSP: Bool? = nil
    var attacksCostSP: Bool? = nil

    var availableCombatOptions: [Int] {
        combatOptions.isEmpty ? [0, 1, 4] : combatOptions
    }
}

struct UnityDTMutableStats: Codable, Hashable {
    var HP: Int
    var EN: Int
    var CR: Int
    var AB: Int
    var maxHP: Int

    init(_ stats: UnityDTStats) {
        HP = stats.HP
        EN = stats.EN
        CR = stats.CR
        AB = stats.AB
        maxHP = stats.HP
    }

    func attackDamage(_ attack: Int) -> Int {
        switch attack {
        case 0: return EN
        case 1: return CR
        case 2: return AB
        default: return 0
        }
    }

    func energyRank() -> Int {
        if EN < 20 { return 0 }
        if EN < 30 { return 1 }
        if EN < 45 { return 2 }
        if EN < 60 { return 3 }
        if EN < 75 { return 4 }
        if EN < 90 { return 5 }
        if EN < 105 { return 6 }
        if EN < 120 { return 7 }
        if EN < 135 { return 8 }
        if EN < 150 { return 9 }
        if EN < 175 { return 10 }
        if EN < 200 { return 11 }
        if EN < 225 { return 12 }
        if EN < 250 { return 13 }
        if EN < 275 { return 14 }
        return 15
    }
}

struct UnityDTSaveState: Codable {
    var playerChar: Int?
    var playerExperience: Int
    var spiritPower: Int
    var steps: Int
    var stepsToNextEvent: Int
    var savedEvent: Int
    var currentWorld: Int
    var currentArea: Int
    var currentDistance: Int
    var completedAreas: [[Bool]]
    var unlocked: [String: Int]
    var ddocks: [String]
    var screen: UnityDTScreen
    var app: UnityDTApp?
    var menuIndex: Int
    var charIndex: Int
    var databaseIndex: Int
    var statusPage: Int
    var mapPage: Int
    var mapScreen: UnityDTMapScreen
    var mapDisplayMap: Int
    var mapDisplayAreaIndex: Int
    var databaseScreen: UnityDTDatabaseScreen
    var databaseMenuIndex: Int
    var databaseGalleryIndex: Int
    var databasePageIndex: Int
    var databaseDockIndex: Int
    var databaseElementIndex: Int
    var codeSelectedAscii: Int
    var codeStatus: Int
    var digitsCode: String
    var battle: UnityDTBattleState?
    var banner: String
    /// GameManager.IsCharacterDefeated. Optional so saves written
    /// before it existed still decode.
    var isCharacterDefeated: Bool?
    /// Points banked in the TRAINING sparring ground. Optional so saves
    /// written before it existed still decode.
    var trainingScore: Int?
    /// The enemy a pending walking event will spawn. Decided when the
    /// event triggers so the character screen can show the very digimon
    /// the battle will use. Optional so older saves still decode.
    var pendingEnemy: String?

    static let empty = UnityDTSaveState(
        playerChar: nil,
        playerExperience: 0,
        spiritPower: 0,
        steps: 0,
        stepsToNextEvent: 300,
        savedEvent: 0,
        currentWorld: 0,
        currentArea: 0,
        currentDistance: 6000,
        completedAreas: [],
        unlocked: [:],
        ddocks: ["", "", "", ""],
        screen: .charSelection,
        app: nil,
        menuIndex: 0,
        charIndex: 0,
        databaseIndex: 0,
        statusPage: 0,
        mapPage: 0,
        mapScreen: .map,
        mapDisplayMap: 0,
        mapDisplayAreaIndex: 0,
        databaseScreen: .menu,
        databaseMenuIndex: 0,
        databaseGalleryIndex: 0,
        databasePageIndex: 0,
        databaseDockIndex: 0,
        databaseElementIndex: 0,
        codeSelectedAscii: 0x41,
        codeStatus: 0,
        digitsCode: "",
        battle: nil,
        banner: "SELECT CHARACTER"
    )
}

final class UnityDTCatalog {
    static let shared = UnityDTCatalog()

    let digimon: [UnityDTDigimon]
    let digimonByName: [String: UnityDTDigimon]
    let rarities: [UnityDTRarity]
    let rarityByName: [String: UnityDTRarity]
    let worlds: [UnityDTWorld]
    let initials: [String]
    let assetManifest: [String: String]
    let spriteDBManifest: [String: SpriteDBValue]

    private init() {
        digimon = Self.decode("digimonDB", fallback: [UnityDTDigimon]()).filter { !$0.disabled }.sorted { $0.order < $1.order }
        digimonByName = Dictionary(uniqueKeysWithValues: digimon.map { ($0.name, $0) })
        rarities = Self.decode("frontier_rarities", fallback: [UnityDTRarity]())
        rarityByName = Dictionary(uniqueKeysWithValues: rarities.map { ($0.digimon, $0) })
        worlds = Self.decode("worlds", fallback: [UnityDTWorld]()).sorted { $0.number < $1.number }
        initials = Self.decode("initials", fallback: [String]())
        assetManifest = Self.decode("unity_asset_manifest", fallback: [String: String]())
        spriteDBManifest = Self.decode("spritedb_manifest", fallback: [String: SpriteDBValue]())
    }

    private static func decode<T: Decodable>(_ name: String, fallback: T) -> T {
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "UnityData")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "UnityFlat")

        guard let url, let data = try? Data(contentsOf: url) else {
            return fallback
        }

        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }

    func assetName(for key: String) -> String? {
        if let fileName = assetManifest[key] {
            return (fileName as NSString).deletingPathExtension
        }

        // Most digimon only ship a default pose. Unity's
        // SpriteDatabase.GetDigimonSprite falls back through the same
        // chain rather than drawing nothing, so a digimon with no attack
        // sprite still appears — just without the pose change.
        let fallbacks = ["_sm": "_sp", "_cr": "_at", "_at": "", "_sp": "", "_bl": "", "_wh": ""]
        var candidate = key
        while let suffix = fallbacks.keys.first(where: candidate.hasSuffix) {
            candidate = String(candidate.dropLast(suffix.count))
                + (fallbacks[suffix] ?? "")
            if let fileName = assetManifest[candidate] {
                return (fileName as NSString).deletingPathExtension
            }
        }
        return nil
    }

    func spriteDBKey(_ field: String, _ index: Int? = nil) -> String? {
        guard let value = spriteDBManifest[field] else { return nil }
        switch (value, index) {
        case (.string(let key), nil):
            return key
        case (.array(let keys), .some(let index)):
            return keys[safe: index]
        default:
            return nil
        }
    }

    func playerSpiritName(for char: Int) -> String {
        switch char {
        case 1: return "lobomon"
        case 2: return "kazemon"
        case 3: return "beetlemon"
        case 4: return "kumamon"
        case 5: return "loweemon"
        default: return "agunimon"
        }
    }

    func rarity(of digimonName: String) -> Int {
        rarityByName[digimonName]?.rarity ?? 5
    }

    func randomBattleDigimon(playerLevel: Int, excluding excluded: Set<String>) -> UnityDTDigimon {
        let eligible = digimon.filter { digimon in
            guard !digimon.isPseudo, digimon.baseLevel <= playerLevel + 20, !excluded.contains(digimon.name) else { return false }
            guard let rarity = rarityByName[digimon.name], !rarity.exclusive else { return false }
            return (0...3).contains(rarity.rarity)
        }

        let roll = Double.random(in: 0..<1)
        let targetRarity: Int
        if roll < 0.50 { targetRarity = 0 }
        else if roll < 0.80 { targetRarity = 1 }
        else if roll < 0.95 { targetRarity = 2 }
        else { targetRarity = 3 }

        let byRarity = eligible.filter { rarity(of: $0.name) == targetRarity }
        return (byRarity.randomElement() ?? eligible.randomElement() ?? digimon.first)!
    }
}

enum SpriteDBValue: Codable, Hashable {
    case string(String)
    case array([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            // Unity serializes unset sprite slots as {fileID: 0} -> null
            self = .string("")
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else {
            let items = try container.decode([String?].self)
            self = .array(items.map { $0 ?? "" })
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text):
            try container.encode(text)
        case .array(let array):
            try container.encode(array)
        }
    }
}

/// A visual event produced by gameplay. The model records these as it
/// resolves an action and the view drains them into its cutscene queue,
/// which is how the original chains several animations off a single
/// input — see the `EnqueueAnimation` calls in `Battle.cs`.
enum UnityDTGameEvent: Equatable {
    case spendCallPoints(before: Int, after: Int)
    case awardSpiritPower(before: Int, after: Int)
    case paySpiritPower(before: Int, after: Int)
    case levelUp(before: Int, after: Int)
    case levelDown(before: Int, after: Int)
    case levelUpDigimon(String)
    case levelDownDigimon(String)
    case eraseDigimon(String)
    case unlockDigimon(name: String, spiritForm: Bool)
    case receiveSpirit(String)
    case loseSpirit(spirit: String, enemy: String)
    case changeDistance(before: Int, after: Int)
    case charHappy
    case charSad
    case enemyEscapes(enemy: String, friendly: String)
    case deportSpirit(String)
    case deportDigimon(String)
    case awardDistance(score: Int, before: Int, after: Int)
    case forcedTravel(
        world: Int,
        areaBefore: Int,
        areaAfter: Int,
        distance: Int
    )
    case displayNewArea(world: Int, area: Int, distance: Int)
    case destroyBox
    case boxResists(String)
    case rewardEmpty
    case rewardDistance(punishment: Bool, before: Int, after: Int)
    case rewardSpiritPower(punishment: Bool, before: Int, after: Int)
    case rewardCode(digimon: String, code: String)
    case dataStorm(moved: Bool)
    case previewEvolution(before: String, after: String)
    case previewTransform(digimon: String)
    case previewEncounter(enemy: String)
    case previewBattleTurn(
        friendly: String,
        enemy: String,
        friendlyAttack: Int,
        enemyAttack: Int,
        playerHPBefore: Int,
        playerHPAfter: Int,
        enemyHPBefore: Int,
        enemyHPAfter: Int
    )
}

@MainActor
final class UnityDTGameModel: ObservableObject {
    private let TIE_DAMAGE_THRESHOLD = 5

    @Published var state: UnityDTSaveState
    private var recordedEvents: [UnityDTGameEvent] = []
    private var leadingEvents: [UnityDTGameEvent] = []
    /// QA only: drop the enemy to 1 HP as soon as a battle starts.
    var qaFinishNextBattle = false
    @Published var frame: Int = 0
    @Published var animationFrame: Int = 0
    @Published var miniGame: UnityDTMiniGame?
    /// Bumped by `record(_:)` so the view can drain events that were
    /// queued outside of an input.
    @Published var recordedEventTick: Int = 0
    /// EVOLVE and FUSION browser cursors. Deliberately not part of the
    /// save file — they are just where you were looking.
    @Published var evolveIndex: Int = 0
    @Published var fusionIndex: Int = 0
    @Published var fusionPage: Int = 0
    /// Original work for the Watch port: guarded reset inside STATUS.
    @Published var statusResetConfirmStep: Int = 0

    let catalog = UnityDTCatalog.shared

    private let saveKey = "UnityDTFullCoreSave.v4.2.sourceLockedAllScreens"
    private var tickTimer: Timer?
    private var animationTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var didActivateAudioSession = false

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode(UnityDTSaveState.self, from: data) {
            state = decoded
        } else {
            state = .empty
            bootstrapCompletedAreas()
        }

        configureQAFromLaunchArguments()

        let logicalTimer = Timer(
            timeInterval: 0.12,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(logicalTimer, forMode: .common)
        tickTimer = logicalTimer

        let displayTimer = Timer(
            timeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.animationFrame =
                    (self.animationFrame + 1) % 1_000_000
            }
        }
        RunLoop.main.add(displayTimer, forMode: .common)
        animationTimer = displayTimer
    }

    deinit {
        tickTimer?.invalidate()
        animationTimer?.invalidate()
    }

    var playerLevel: Int {
        max(1, Int(floor(pow(Double(max(0, state.playerExperience)), 1.0 / 3.0))))
    }

    var currentWorld: UnityDTWorld? {
        catalog.worlds[safe: state.currentWorld]
    }

    var currentArea: UnityDTArea? {
        currentWorld?.areas[safe: state.currentArea]
    }

    var menuApp: UnityDTApp {
        UnityDTApp.visibleMainMenuCases[safe: state.menuIndex] ?? .map
    }

    var selectedDigimon: UnityDTDigimon? {
        catalog.digimon[safe: state.databaseIndex]
    }

    var activePartnerName: String {
        state.ddocks.first(where: { !$0.isEmpty }) ?? catalog.playerSpiritName(for: state.playerChar ?? 0)
    }

    func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    /// Records a cutscene-worthy event. `leading` events play before the
    /// screen transition's own cutscene, which is the order Unity uses
    /// for e.g. SpendCallPoints followed by SummonDigimon.
    func record(_ event: UnityDTGameEvent, leading: Bool = false) {
        if leading {
            leadingEvents.append(event)
        } else {
            recordedEvents.append(event)
        }
        // Most events are recorded while an input is being handled, and
        // the view drains them straight afterwards. Some — a jackpot
        // that times out, a mini-game that ends on its own clock — are
        // recorded from the tick instead, and used to sit unqueued until
        // the player happened to tap again. This lets the view notice.
        recordedEventTick &+= 1
    }

    /// Hands the view everything that happened during the last action.
    func drainEvents(leading: Bool = false) -> [UnityDTGameEvent] {
        if leading {
            defer { leadingEvents.removeAll() }
            return leadingEvents
        }
        defer { recordedEvents.removeAll() }
        return recordedEvents
    }

    func resetToUnityNewGame() {
        statusResetConfirmStep = 0
        state = .empty
        bootstrapCompletedAreas()
        save()
    }

    func left() {
        play("button_b")
        switch state.screen {
        case .charSelection:
            state.charIndex = wrap(state.charIndex - 1, count: 6)
        case .mainMenu:
            state.menuIndex = wrap(
                state.menuIndex - 1,
                count: UnityDTApp.visibleMainMenuCases.count
            )
        case .app:
            appLeft()
        case .battle:
            battleLeft()
        case .result:
            finishResult()
        case .character:
            state.menuIndex = 0
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        }
    }

    func right() {
        play("button_b")
        switch state.screen {
        case .charSelection:
            state.charIndex = wrap(state.charIndex + 1, count: 6)
        case .mainMenu:
            state.menuIndex = wrap(
                state.menuIndex + 1,
                count: UnityDTApp.visibleMainMenuCases.count
            )
        case .app:
            appRight()
        case .battle:
            battleRight()
        case .result:
            finishResult()
        case .character:
            state.menuIndex = 0
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        }
    }

    func centerTap() {
        switch state.screen {
        case .charSelection:
            createNewGame(character: state.charIndex)
        case .character:
            if state.savedEvent != 0 || state.currentDistance == 1 {
                confirm()
            } else {
                takeStep(source: "tap")
            }
        case .mainMenu:
            openCurrentMenuApp()
        case .app:
            confirmApp()
        case .battle:
            battleA()
        case .result:
            finishResult()
        }
    }

    func longBack() {
        play("button_b")
        switch state.screen {
        case .charSelection:
            state.banner = "HOLD BACK"
        case .character:
            // Character is the root screen on Apple Watch.
            break
        case .mainMenu:
            state.screen = .character
            state.banner = "CHARACTER"
        case .app:
            appBack()
        case .battle:
            battleB()
        case .result:
            finishResult()
        }
    }

    func takeStep(source: String) {
        guard state.playerChar != nil else { return }
        guard state.screen == .character else { return }
        // LogicManager.ShakeDisabled: a defeated character cannot be
        // walked until it has rested at the Camp.
        if source == "shake", state.isCharacterDefeated == true {
            return
        }

        // Walking again means the last battle is well and truly over, so
        // its leftover state can go.
        state.battle = nil

        state.stepsToNextEvent -= 1
        state.steps += 1

        if state.stepsToNextEvent <= 0 && state.currentDistance > 1 {
            state.stepsToNextEvent = Int.random(in: 3...5) * 100
            state.savedEvent = 1
            state.pendingEnemy = catalog.randomBattleDigimon(
                playerLevel: playerLevel,
                excluding: Set(state.unlocked.keys)
            ).name
            state.banner = "EVENT"
            play("event")
        }

        let nextStop = 1
        state.currentDistance = max(nextStop, state.currentDistance - 1)
        if state.currentDistance == 1 {
            state.savedEvent = 2
            state.pendingEnemy = currentWorld?.bosses.randomElement()
            state.banner = "BOSS CALL"
            play("event")
        } else if state.savedEvent == 0 {
            state.banner = source == "shake" ? "SHAKE STEP" : "STEP"
        }
        save()
    }

    func confirm() {
        play("button_a")
        switch state.screen {
        case .character:
            if state.savedEvent == 2 || state.currentDistance == 1 {
                startBossBattle()
            } else if state.savedEvent == 1 {
                if Double.random(in: 0..<1) < 0.85 {
                    startRandomBattle()
                } else {
                    let uncompletedAreas = (currentWorld?.areas ?? [])
                        .map(\.number)
                        .filter {
                            state.completedAreas[
                                safe: state.currentWorld
                            ]?[safe: $0] != true
                        }
                    if uncompletedAreas.count >= 2,
                       Double.random(in: 0..<1) < 0.33,
                       let destination = uncompletedAreas.randomElement() {
                        state.currentArea = destination
                        state.currentDistance += 1000
                    }
                    state.savedEvent = 0
                    state.pendingEnemy = nil
                    state.banner = "DIGISTORM"
                    play("digistorm")
                }
            } else {
                state.screen = .mainMenu
                state.banner = "MAIN MENU"
            }
        default:
            centerTap()
        }
    }

    private func createNewGame(character: Int) {
        var fresh = UnityDTSaveState.empty
        fresh.playerChar = character
        fresh.charIndex = character
        fresh.spiritPower = 99
        fresh.currentWorld = 0
        fresh.currentArea = 0
        fresh.currentDistance = catalog.worlds.first?.areas.first?.distance ?? 6000
        fresh.screen = .character
        fresh.banner = "GAME START"
        fresh.completedAreas = catalog.worlds.map { world in Array(repeating: false, count: world.areas.count) }

        let spirit = catalog.playerSpiritName(for: character)
        fresh.unlocked[spirit] = 1
        let initial = catalog.initials.randomElement() ?? "agumon"
        fresh.unlocked[initial] = 1
        fresh.ddocks = [initial, "", "", ""]

        state = fresh
        play("game_start")
        save()
    }

    private func openCurrentMenuApp() {
        let app = menuApp
        // LogicManager.InputA: while defeated the only app that opens
        // is the Camp, everything else just buzzes.
        if state.isCharacterDefeated == true, app != .camp {
            play("button_b")
            return
        }
        state.app = app
        state.screen = .app
        state.banner = app.title
        switch app {
        case .map:
            let map = currentArea?.map ?? 0
            state.mapScreen = .map
            state.mapDisplayMap = map
            state.mapPage = map
            state.mapDisplayAreaIndex = originalAreaIndexInDisplayedMap()
        case .status:
            state.statusPage = 0
            statusResetConfirmStep = 0
        case .database:
            state.databaseScreen = .menu
            state.databaseMenuIndex = 0
            state.databaseGalleryIndex = 0
            state.databasePageIndex = 0
            state.databaseDockIndex = 0
            state.databaseElementIndex = 0
        case .digits:
            resetCodeInput()
        case .game:
            state.mapPage = 0
            state.databaseIndex = 0
        case .camp:
            break
        case .evolve:
            openEvolveApp()
        case .fusion:
            openFusionApp()
        case .connect:
            state.app = nil
            state.screen = .mainMenu
            return
        }
        play("button_a")
        save()
    }

    private func bootstrapCompletedAreas() {
        if state.completedAreas.count != catalog.worlds.count {
            state.completedAreas = catalog.worlds.map { world in Array(repeating: false, count: world.areas.count) }
        }
        if let area = currentArea, state.currentDistance <= 0 {
            state.currentDistance = area.distance
        }
    }

    private func appLeft() {
        switch state.app {
        case .database:
            databaseLeft()
        case .status:
            statusResetConfirmStep = 0
            state.statusPage = wrap(state.statusPage - 1, count: 9)
        case .map:
            mapLeft()
        case .digits:
            codeLeft()
        case .evolve:
            evolveBrowse(-1)
        case .fusion:
            fusionBrowse(-1)
        case .game:
            if miniGame != nil {
                miniGameLeft()
                save()
                return
            }
            // The reward menu carries a fourth entry the original
            // never had: PIPE MONSTERS, Version 4's exclusive game.
            let count = state.mapPage == 1
                ? 4
                : state.mapPage == 2 ? 4 : 3
            state.databaseIndex = wrap(
                state.databaseIndex - 1,
                count: count
            )
        default:
            state.banner = state.app?.title ?? ""
        }
        save()
    }

    private func appRight() {
        switch state.app {
        case .database:
            databaseRight()
        case .status:
            statusResetConfirmStep = 0
            state.statusPage = wrap(state.statusPage + 1, count: 9)
        case .map:
            mapRight()
        case .digits:
            codeRight()
        case .evolve:
            evolveBrowse(1)
        case .fusion:
            fusionBrowse(1)
        case .game:
            if miniGame != nil {
                miniGameRight()
                save()
                return
            }
            // The reward menu carries a fourth entry the original
            // never had: PIPE MONSTERS, Version 4's exclusive game.
            let count = state.mapPage == 1
                ? 4
                : state.mapPage == 2 ? 4 : 3
            state.databaseIndex = wrap(
                state.databaseIndex + 1,
                count: count
            )
        default:
            state.banner = state.app?.title ?? ""
        }
        save()
    }

    private func confirmApp() {
        switch state.app {
        case .map:
            mapA()
        case .status:
            if state.statusPage == 8 {
                if statusResetConfirmStep < 3 {
                    statusResetConfirmStep += 1
                    play("button_a")
                } else {
                    play("button_a")
                    resetToUnityNewGame()
                    return
                }
            } else {
                state.statusPage = wrap(state.statusPage + 1, count: 9)
            }
        case .game:
            if miniGame != nil {
                miniGameA()
                save()
                return
            }
            // LogicManager.InputA has no handler for the reward menu's
            // ENERGY WARS / DIGI-CATCH entries, nor for travel entry 1 —
            // those games were never built. The original stays silent on
            // them rather than playing a confirm beep.
            var handled = true
            if state.mapPage == 0 {
                if state.databaseIndex == 0 {
                    startMiniGame(.finder)
                } else if state.databaseIndex == 1 {
                    state.mapPage = 1
                    state.databaseIndex = 0
                } else if state.databaseIndex == 2 {
                    state.mapPage = 2
                    state.databaseIndex = 0
                } else {
                    handled = false
                }
            } else if state.mapPage == 1 {
                if state.databaseIndex == 0 {
                    startMiniGame(.jackpot)
                } else if state.databaseIndex == 1 {
                    startMiniGame(.energyWars)
                } else if state.databaseIndex == 2 {
                    startMiniGame(.digiCatch)
                } else if state.databaseIndex == 3 {
                    startMiniGame(.pipeMonsters)
                } else {
                    handled = false
                }
            } else if state.mapPage == 2 {
                if state.databaseIndex == 0 {
                    startMiniGame(.speedRunner)
                } else if state.databaseIndex == 2 {
                    startMiniGame(.digiHunter)
                } else if state.databaseIndex == 3 {
                    startMiniGame(.maze)
                } else {
                    handled = false
                }
            }
            if handled { play("button_a") }
        case .database:
            databaseA()
        case .digits:
            codeA(submitError: false) { digimon in
                unlock(digimon)
                state.banner = "CODE OK"
                play("unlock_code_long")
                state.app = nil
                state.screen = .mainMenu
            }
        case .camp:
            // Camp.cs EndCamp: CloseCamp, then CharHappy, and the
            // defeated state clears — resting is the only way out of it.
            state.isCharacterDefeated = false
            state.screen = .character
            state.app = nil
            state.banner = "CHARACTER"
            record(.charHappy)
        case .evolve:
            evolveConfirm()
        case .fusion:
            fusionConfirm()
        case .connect:
            break
        case .none:
            break
        }
        save()
    }

    private func appBack() {
        switch state.app {
        case .map:
            mapB()
        case .database:
            databaseB()
        case .status:
            if statusResetConfirmStep > 0 {
                statusResetConfirmStep = 0
                play("button_b")
            } else {
                state.app = nil
                state.screen = .mainMenu
                state.banner = "MAIN MENU"
            }
        case .digits:
            codeB()
        case .camp:
            state.screen = .character
            state.app = nil
            state.banner = "CHARACTER"
            play("char_happy")
        case .game:
            if miniGame != nil {
                miniGameB()
                save()
                return
            }
            if state.mapPage == 0 {
                state.app = nil
                state.screen = .mainMenu
                state.banner = "MAIN MENU"
            } else {
                state.mapPage = 0
                state.databaseIndex = 0
                play("button_b")
            }
        default:
            state.app = nil
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        }
        save()
    }

    private func areasInDisplayedMap() -> [UnityDTArea] {
        (currentWorld?.areas ?? []).filter { $0.map == state.mapDisplayMap }.sorted { $0.number < $1.number }
    }

    private func originalAreaIndexInDisplayedMap() -> Int {
        let areas = areasInDisplayedMap()
        return areas.firstIndex(where: { $0.number == state.currentArea }) ?? 0
    }

    private func selectedMapArea() -> UnityDTArea? {
        areasInDisplayedMap()[safe: state.mapDisplayAreaIndex]
    }

    private func mapLeft() {
        guard let world = currentWorld else { return }
        switch state.mapScreen {
        case .map:
            if world.lockTravel == true || world.multiMap != true {
                play("button_b")
                return
            }
            state.mapDisplayMap = wrap(state.mapDisplayMap - 1, count: 4)
            state.mapPage = state.mapDisplayMap
            state.mapDisplayAreaIndex = 0
            play("button_a")
        case .areaSelection:
            if world.lockTravel == true {
                play("button_b")
                return
            }
            state.mapDisplayAreaIndex = wrap(state.mapDisplayAreaIndex - 1, count: max(1, areasInDisplayedMap().count))
            play("button_a")
        case .distance:
            play("button_b")
        }
    }

    private func mapRight() {
        guard let world = currentWorld else { return }
        switch state.mapScreen {
        case .map:
            if world.lockTravel == true || world.multiMap != true {
                play("button_b")
                return
            }
            state.mapDisplayMap = wrap(state.mapDisplayMap + 1, count: 4)
            state.mapPage = state.mapDisplayMap
            state.mapDisplayAreaIndex = 0
            play("button_a")
        case .areaSelection:
            if world.lockTravel == true {
                play("button_b")
                return
            }
            state.mapDisplayAreaIndex = wrap(state.mapDisplayAreaIndex + 1, count: max(1, areasInDisplayedMap().count))
            play("button_a")
        case .distance:
            play("button_b")
        }
    }

    private func mapA() {
        switch state.mapScreen {
        case .map:
            state.mapScreen = .areaSelection
            state.mapDisplayAreaIndex = state.mapDisplayMap == (currentArea?.map ?? 0) ? originalAreaIndexInDisplayedMap() : 0
            play("button_a")
        case .areaSelection:
            state.mapScreen = .distance
            play("button_a")
        case .distance:
            if let area = selectedMapArea(), area.number != state.currentArea {
                state.currentArea = area.number
                state.currentDistance = area.distance
                state.savedEvent = 0
                state.banner = "TRAVEL"
                play("map_travel")
            }
            state.app = nil
            state.screen = .character
        }
    }

    private func mapB() {
        switch state.mapScreen {
        case .map:
            state.app = nil
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        case .areaSelection:
            state.mapScreen = .map
            play("button_b")
        case .distance:
            state.mapScreen = .areaSelection
            play("button_b")
        }
    }

    private func resetCodeInput() {
        state.codeSelectedAscii = 0x41
        state.codeStatus = 0
        state.digitsCode = ""
    }

    private func codeA(submitError: Bool, onSuccess: (String) -> Void) {
        if state.digitsCode.count < 5 {
            state.digitsCode.append(Character(UnicodeScalar(state.codeSelectedAscii)!))
            if state.digitsCode.count == 5 {
                state.codeStatus = 1
            }
            play("button_a")
        } else if state.codeStatus == 1 {
            let code = state.digitsCode.lowercased()
            if let hit = catalog.digimon.first(where: { $0.code?.lowercased() == code }) {
                onSuccess(hit.name)
            } else if submitError {
                onSuccess("numemon")
            } else {
                state.codeStatus = 2
                play("unpleasant_beep")
            }
        } else if state.codeStatus == 2 {
            state.digitsCode = String(state.digitsCode.dropLast())
            state.codeStatus = 0
            play("button_a")
        }
    }

    private func codeB() {
        if state.digitsCode.isEmpty {
            state.app = nil
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        } else {
            state.digitsCode = String(state.digitsCode.dropLast())
            state.codeStatus = 0
            play("button_b")
        }
    }

    private func codeLeft() {
        if state.digitsCode.count >= 5, state.codeStatus == 2 {
            state.digitsCode = String(state.digitsCode.dropLast())
            state.codeStatus = 0
            play("button_a")
            return
        }
        guard state.digitsCode.count < 5 else {
            play("button_b")
            return
        }
        if state.codeSelectedAscii == 0x41 {
            state.codeSelectedAscii = 0x39
        } else if state.codeSelectedAscii == 0x30 {
            state.codeSelectedAscii = 0x5A
        } else {
            state.codeSelectedAscii -= 1
        }
        play("button_a")
    }

    private func codeRight() {
        if state.digitsCode.count >= 5, state.codeStatus == 2 {
            state.digitsCode = String(state.digitsCode.dropLast())
            state.codeStatus = 0
            play("button_a")
            return
        }
        guard state.digitsCode.count < 5 else {
            play("button_b")
            return
        }
        if state.codeSelectedAscii == 0x5A {
            state.codeSelectedAscii = 0x30
        } else if state.codeSelectedAscii == 0x39 {
            state.codeSelectedAscii = 0x41
        } else {
            state.codeSelectedAscii += 1
        }
        play("button_a")
    }

    private func unlockedDigimonInStage(_ stage: Int) -> [String] {
        catalog.digimon
            .filter { $0.stage == stage && isUnlocked($0.name) }
            .sorted { $0.order < $1.order }
            .map(\.name)
    }

    private func unlockedSpiritsOfElement(_ element: Int) -> [String] {
        catalog.digimon
            .filter { $0.stage == 6 && $0.element == element && $0.spiritType != 4 && isUnlocked($0.name) }
            .sorted { $0.order < $1.order }
            .map(\.name)
    }

    private func unlockedFusionDigimon() -> [String] {
        catalog.digimon
            .filter { $0.stage == 6 && $0.spiritType == 4 && isUnlocked($0.name) }
            .sorted { $0.order < $1.order }
            .map(\.name)
    }

    var databaseGalleryList: [String] {
        switch state.databaseScreen {
        case .gallery, .pages, .ddockList, .ddockDisplay:
            if state.databaseMenuIndex == 6 {
                let element = databaseAvailableElements()[safe: state.databaseElementIndex] ?? 0
                return element < 10 ? unlockedSpiritsOfElement(element) : unlockedFusionDigimon()
            }
            return unlockedDigimonInStage(state.databaseMenuIndex)
        default:
            return []
        }
    }

    var databasePageDigimon: UnityDTDigimon? {
        let list = databaseGalleryList
        guard let name = list[safe: state.databaseGalleryIndex] else { return nil }
        return catalog.digimonByName[name]
    }

    func databaseAvailableElements() -> [Int] {
        let allSpirits = unlockedDigimonInStage(6)
        var elements = Set<Int>()
        for name in allSpirits {
            if let d = catalog.digimonByName[name] {
                elements.insert(d.element)
            }
        }
        if !unlockedFusionDigimon().isEmpty {
            elements.insert(10)
        }
        return elements.sorted()
    }

    private func databaseLeft() {
        switch state.databaseScreen {
        case .menu:
            state.databaseMenuIndex = wrap(state.databaseMenuIndex - 1, count: 8)
        case .spiritMenu:
            state.databaseElementIndex = wrap(state.databaseElementIndex - 1, count: max(1, databaseAvailableElements().count))
        case .gallery:
            state.databaseGalleryIndex = wrap(state.databaseGalleryIndex - 1, count: max(1, databaseGalleryList.count))
        case .pages:
            state.databasePageIndex = wrap(state.databasePageIndex - 1, count: databasePageCount())
        case .ddockList, .ddockDisplay:
            state.databaseDockIndex = wrap(state.databaseDockIndex - 1, count: 4)
        }
        play("button_a")
    }

    private func databaseRight() {
        switch state.databaseScreen {
        case .menu:
            state.databaseMenuIndex = wrap(state.databaseMenuIndex + 1, count: 8)
        case .spiritMenu:
            state.databaseElementIndex = wrap(state.databaseElementIndex + 1, count: max(1, databaseAvailableElements().count))
        case .gallery:
            state.databaseGalleryIndex = wrap(state.databaseGalleryIndex + 1, count: max(1, databaseGalleryList.count))
        case .pages:
            state.databasePageIndex = wrap(state.databasePageIndex + 1, count: databasePageCount())
        case .ddockList, .ddockDisplay:
            state.databaseDockIndex = wrap(state.databaseDockIndex + 1, count: 4)
        }
        play("button_a")
    }

    private func databaseA() {
        switch state.databaseScreen {
        case .menu:
            let list = unlockedDigimonInStage(state.databaseMenuIndex)
            guard !list.isEmpty else { play("button_b"); return }
            if state.databaseMenuIndex < 6 {
                state.databaseGalleryIndex = 0
                state.databaseScreen = .gallery
            } else {
                state.databaseElementIndex = 0
                state.databaseScreen = .spiritMenu
            }
            play("button_a")
        case .spiritMenu:
            let element = databaseAvailableElements()[safe: state.databaseElementIndex] ?? 0
            let list = element < 10 ? unlockedSpiritsOfElement(element) : unlockedFusionDigimon()
            guard !list.isEmpty else { play("button_b"); return }
            state.databaseGalleryIndex = 0
            state.databaseScreen = .gallery
            play("button_a")
        case .gallery:
            state.databasePageIndex = 0
            state.databaseScreen = .pages
            play("button_a")
        case .pages:
            state.databaseDockIndex = 0
            state.databaseScreen = .ddockList
            play("button_a")
        case .ddockList:
            state.databaseScreen = .ddockDisplay
            play("button_a")
        case .ddockDisplay:
            chooseDatabaseDDock()
            play("button_a")
        }
    }

    private func databaseB() {
        switch state.databaseScreen {
        case .menu:
            state.app = nil
            state.screen = .mainMenu
            state.banner = "MAIN MENU"
        case .spiritMenu:
            state.databaseScreen = .menu
            play("button_b")
        case .gallery:
            state.databaseScreen = state.databaseMenuIndex < 6 ? .menu : .spiritMenu
            play("button_b")
        case .pages:
            state.databaseScreen = .gallery
            play("button_b")
        case .ddockList:
            state.databaseScreen = .pages
            play("button_b")
        case .ddockDisplay:
            state.databaseScreen = .ddockList
            play("button_b")
        }
    }

    private func databasePageCount() -> Int {
        guard let d = databasePageDigimon else { return 2 }
        return d.code?.isEmpty == false ? 3 : 2
    }

    private func chooseDatabaseDDock() {
        guard let chosen = databasePageDigimon else { return }
        if let existing = state.ddocks.firstIndex(of: chosen.name) {
            state.ddocks[existing] = state.ddocks[safe: state.databaseDockIndex] ?? ""
        }
        if state.ddocks.indices.contains(state.databaseDockIndex) {
            state.ddocks[state.databaseDockIndex] = chosen.name
        }
        state.databaseScreen = state.databaseMenuIndex < 6 ? .menu : .spiritMenu
        state.databaseGalleryIndex = 0
        state.databasePageIndex = 0
        state.databaseDockIndex = 0
        state.banner = "D-DOCK"
    }

    private var currentEnemy: UnityDTDigimon? {
        guard let battle = state.battle else { return nil }
        return catalog.digimonByName[battle.enemyName]
    }

    private var currentPlayerDigimon: UnityDTDigimon? {
        guard let battle = state.battle else { return nil }
        return catalog.digimonByName[battle.playerName]
    }

    func startRandomBattle() {
        // Whatever was shown looming on the character screen is the
        // digimon that turns up.
        let enemy = state.pendingEnemy
            .flatMap { catalog.digimonByName[$0] }
            ?? catalog.randomBattleDigimon(
                playerLevel: playerLevel,
                excluding: Set(state.unlocked.keys)
            )
        state.pendingEnemy = nil
        beginBattle(enemy: enemy, boss: false)
    }

    private func startBossBattle() {
        let world = currentWorld
        let bossName = state.pendingEnemy
            ?? world?.bosses.randomElement() ?? "agunimon"
        let enemy = catalog.digimonByName[bossName] ?? catalog.randomBattleDigimon(playerLevel: playerLevel + 15, excluding: [])
        state.pendingEnemy = nil
        beginBattle(enemy: enemy, boss: true)
    }

    private func beginBattle(enemy: UnityDTDigimon, boss: Bool) {
        let enemyStats = boss ? bossStats(enemy) : enemy.stats
        let enemyMutable = UnityDTMutableStats(enemyStats)
        state.battle = UnityDTBattleState(
            enemyName: enemy.name,
            playerName: "",
            playerHP: 0,
            playerMaxHP: 0,
            enemyHP: max(1, enemyStats.HP),
            enemyMaxHP: max(1, enemyStats.HP),
            playerEN: 0,
            enemyEN: max(1, enemyStats.EN),
            playerLevel: playerLevel,
            enemyLevel: boss ? playerLevel : enemy.baseLevel,
            turn: 0,
            message: boss ? "BOSS!" : "BATTLE!",
            flash: 0,
            victory: false,
            defeat: false,
            boss: boss,
            screen: .mainMenu,
            menuIndex: 0,
            ddockIndex: 0,
            combatMenuIndex: 0,
            attackIndex: 0,
            callPoints: 10,
            combatOptions: [0, 1, 4],
            callPointsForEvolution: 1,
            ddockPurpose: 0,
            spiritElementIndex: 0,
            spiritGalleryIndex: 0,
            codeSelectedAscii: 0x41,
            codeInput: "",
            codeStatus: 0,
            friendlyStats: nil,
            enemyStats: enemyMutable,
            originalPlayerName: "",
            lastFriendlyAttack: nil,
            lastEnemyAttack: nil,
            attacksAwardSP: nil,
            attacksCostSP: nil
        )
        if qaFinishNextBattle {
            state.battle?.enemyHP = 1
            state.battle?.enemyStats.HP = 1
            state.battle?.enemyMaxHP = 1
        }
        state.screen = .battle
        // The encounter cutscene fires the clip from inside its own cue
        // list, the way Unity's coroutine does. Playing it here as well
        // doubled it up.
        save()
    }

    private func battleLeft() {
        guard var battle = state.battle else { return }
        switch battle.screen {
        case .mainMenu:
            battle.menuIndex = wrap(battle.menuIndex - 1, count: 4)
        case .ddocks:
            battle.ddockIndex = wrap(battle.ddockIndex - 1, count: 4)
        case .spiritElements:
            battle.spiritElementIndex = wrap(battle.spiritElementIndex - 1, count: max(1, battleAvailableSpiritElements().count))
        case .spiritGallery:
            battle.spiritGalleryIndex = wrap(battle.spiritGalleryIndex - 1, count: max(1, battleSpiritGallery().count))
        case .digits:
            battleCodeLeft(&battle)
        case .combatMenu:
            battle.combatMenuIndex = wrap(battle.combatMenuIndex - 1, count: battle.availableCombatOptions.count)
        case .attackMenu:
            battle.attackIndex = wrap(battle.attackIndex - 1, count: 3)
        case .regularEvolve:
            battle.callPointsForEvolution = max(1, battle.callPointsForEvolution - 1)
        }
        state.battle = battle
        play("button_a")
    }

    private func battleRight() {
        guard var battle = state.battle else { return }
        switch battle.screen {
        case .mainMenu:
            battle.menuIndex = wrap(battle.menuIndex + 1, count: 4)
        case .ddocks:
            battle.ddockIndex = wrap(battle.ddockIndex + 1, count: 4)
        case .spiritElements:
            battle.spiritElementIndex = wrap(battle.spiritElementIndex + 1, count: max(1, battleAvailableSpiritElements().count))
        case .spiritGallery:
            battle.spiritGalleryIndex = wrap(battle.spiritGalleryIndex + 1, count: max(1, battleSpiritGallery().count))
        case .digits:
            battleCodeRight(&battle)
        case .combatMenu:
            battle.combatMenuIndex = wrap(battle.combatMenuIndex + 1, count: battle.availableCombatOptions.count)
        case .attackMenu:
            battle.attackIndex = wrap(battle.attackIndex + 1, count: 3)
        case .regularEvolve:
            battle.callPointsForEvolution = min(max(1, battle.callPoints), battle.callPointsForEvolution + 1)
        }
        state.battle = battle
        play("button_a")
    }

    private func battleA() {
        guard var battle = state.battle else { return }
        switch battle.screen {
        case .mainMenu:
            if battle.menuIndex == 0 {
                battle.screen = .ddocks
                battle.ddockIndex = 0
                battle.ddockPurpose = 0
                battle.message = "BATTLE CALL"
                play("button_a")
            } else if battle.menuIndex == 1 {
                let elements = battleAvailableSpiritElements()
                if elements.isEmpty {
                    battle.message = "NO SPIRIT"
                    play("button_b")
                } else {
                    battle.screen = .spiritElements
                    battle.spiritElementIndex = 0
                    battle.spiritGalleryIndex = 0
                    battle.message = "SPIRIT ON"
                    play("button_a")
                }
            } else if battle.menuIndex == 2 {
                battle.screen = .digits
                battle.codeInput = ""
                battle.codeSelectedAscii = 0x41
                battle.codeStatus = 0
                battle.message = "DIGITS"
                play("button_a")
            } else if battle.menuIndex == 3 {
                state.battle = battle
                escapeBattle()
                return
            }
        case .ddocks:
            if battle.ddockPurpose == 1 {
                attemptBoostFromDDock(&battle)
            } else {
                summonFromDDock(&battle)
            }
        case .spiritElements:
            guard !battleSpiritGallery().isEmpty else {
                battle.message = "EMPTY"
                play("button_b")
                state.battle = battle
                return
            }
            battle.screen = .spiritGallery
            battle.spiritGalleryIndex = 0
            battle.message = "CHOOSE SPIRIT"
            play("button_a")
        case .spiritGallery:
            chooseSpiritFromBattleGallery(&battle)
        case .digits:
            battleCodeA(&battle)
        case .combatMenu:
            let selected = battle.availableCombatOptions[safe: battle.combatMenuIndex] ?? 0
            if selected == 0 {
                battle.screen = .attackMenu
                battle.attackIndex = 0
                battle.message = "ATTACK"
                play("button_a")
            } else if selected == 1 {
                guard battle.callPoints > 0 else {
                    battle.message = "NO CP"
                    play("button_b")
                    state.battle = battle
                    return
                }
                battle.screen = .regularEvolve
                battle.callPointsForEvolution = 1
                battle.message = "DIGIVOLVE"
                play("button_a")
            } else if selected == 3 {
                battle.screen = .ddocks
                battle.ddockPurpose = 1
                battle.ddockIndex = 0
                battle.message = "BOOST"
                play("button_a")
            } else if selected == 4 {
                state.battle = battle
                deportCurrentDigimon()
                return
            } else {
                battle.message = "CARD"
                play("button_b")
            }
        case .attackMenu:
            state.battle = battle
            submitTurn(friendlyAttack: battle.attackIndex)
            return
        case .regularEvolve:
            attemptRegularDigivolve(&battle)
        }
        state.battle = battle
        save()
    }

    private func battleB() {
        guard var battle = state.battle else { return }
        switch battle.screen {
        case .mainMenu, .combatMenu:
            // Battle.cs InputB shows the spirit power screen here rather
            // than backing out of the battle.
            battle.message = "SP \(state.spiritPower)"
            record(
                .paySpiritPower(
                    before: state.spiritPower,
                    after: state.spiritPower
                )
            )
        case .ddocks:
            battle.screen = battle.ddockPurpose == 1 ? .combatMenu : .mainMenu
            play("button_b")
        case .spiritElements:
            battle.screen = .mainMenu
            play("button_b")
        case .spiritGallery:
            battle.screen = .spiritElements
            play("button_b")
        case .digits:
            battleCodeB(&battle)
        case .attackMenu:
            battle.screen = .combatMenu
            play("button_b")
        case .regularEvolve:
            battle.screen = .combatMenu
            play("button_b")
        }
        state.battle = battle
        save()
    }

    func battleAvailableSpiritElements() -> [Int] {
        let spirits = unlockedDigimonInStage(6)
        var elements = Set<Int>()
        for name in spirits {
            if let d = catalog.digimonByName[name] {
                elements.insert(d.element)
            }
        }
        if !unlockedFusionDigimon().isEmpty {
            elements.insert(10)
        }
        return elements.sorted()
    }

    func battleSpiritGallery() -> [String] {
        guard let battle = state.battle else { return [] }
        let element = battleAvailableSpiritElements()[safe: battle.spiritElementIndex] ?? 0
        return element < 10 ? unlockedSpiritsOfElement(element) : unlockedFusionDigimon()
    }

    private func summonFromDDock(_ battle: inout UnityDTBattleState) {
        let chosen = battle.callPoints > 0 ? (state.ddocks[safe: battle.ddockIndex] ?? "") : "numemon"
        guard !chosen.isEmpty, let digimon = catalog.digimonByName[chosen] else {
            battle.message = "EMPTY"
            play("button_b")
            return
        }
        assignFriendly(&battle, digimon: digimon, mode: .regular)
        let callPointsBefore = battle.callPoints
        battle.callPoints = max(0, battle.callPoints - callCost(digimon, playerLevel: playerLevel))
        record(
            .spendCallPoints(
                before: callPointsBefore,
                after: battle.callPoints
            ),
            leading: true
        )
        battle.combatOptions = [0, 1, 4]
        battle.screen = .combatMenu
        battle.combatMenuIndex = 0
        battle.message = "SUMMON"
        play("summon_digimon")
    }

    private enum FriendlyAssignMode {
        case regular
        case code
        case spirit
        case ancient
        case digivolution(missingHP: Int)
    }

    private func assignFriendly(_ battle: inout UnityDTBattleState, digimon: UnityDTDigimon, mode: FriendlyAssignMode) {
        let stats: UnityDTMutableStats
        switch mode {
        case .regular:
            stats = friendlyMutableStats(digimon)
        case .code:
            state.spiritPower = max(0, state.spiritPower - 20)
            stats = friendlyMutableStats(digimon)
        case .spirit:
            stats = UnityDTMutableStats(bossStats(digimon))
        case .ancient:
            state.spiritPower = max(0, state.spiritPower - spiritCost(digimon, playerLevel: playerLevel))
            stats = UnityDTMutableStats(bossStats(digimon))
        case .digivolution(let missingHP):
            var evolved = friendlyMutableStats(digimon)
            evolved.maxHP = evolved.HP
            evolved.HP = max(0, evolved.HP - missingHP)
            stats = evolved
            unlock(digimon.name)
        }
        // Battle.cs: only digimon summoned from Battle Call earn spirit
        // power, and non-Ancient spirit forms pay it on every attack.
        switch mode {
        case .regular, .code, .digivolution:
            battle.attacksAwardSP = true
            battle.attacksCostSP = false
        case .spirit:
            battle.attacksAwardSP = false
            battle.attacksCostSP = true
        case .ancient:
            battle.attacksAwardSP = false
            battle.attacksCostSP = false
        }
        battle.playerName = digimon.name
        battle.originalPlayerName = digimon.name
        battle.friendlyStats = stats
        battle.playerHP = stats.HP
        battle.playerMaxHP = stats.maxHP
        battle.playerEN = stats.EN
    }

    private func chooseSpiritFromBattleGallery(_ battle: inout UnityDTBattleState) {
        let list = battleSpiritGallery()
        guard let name = list[safe: battle.spiritGalleryIndex],
              let chosen = catalog.digimonByName[name] else {
            battle.message = "EMPTY"
            play("button_b")
            return
        }
        let cost = spiritCost(chosen, playerLevel: playerLevel)
        let finalDigimon = cost > state.spiritPower ? (catalog.digimonByName["flamemon"] ?? chosen) : chosen
        let mode: FriendlyAssignMode = finalDigimon.spiritType == 3 || finalDigimon.name == "flamemon" ? .ancient : .spirit
        assignFriendly(&battle, digimon: finalDigimon, mode: mode)
        battle.combatOptions = [0, 3, 4]
        battle.screen = .combatMenu
        battle.combatMenuIndex = 0
        battle.message = "SPIRIT ON"
        play("summon_digimon")
    }

    private func battleCodeA(_ battle: inout UnityDTBattleState) {
        if battle.codeInput.count < 5 {
            battle.codeInput.append(Character(UnicodeScalar(battle.codeSelectedAscii)!))
            if battle.codeInput.count == 5 {
                battle.codeStatus = 1
            }
            play("button_a")
        } else if battle.codeStatus == 1 {
            let code = battle.codeInput.lowercased()
            var name = catalog.digimon.first(where: { $0.code?.lowercased() == code })?.name ?? "numemon"
            if let d = catalog.digimonByName[name], d.stage == 5 || d.stage == 6 {
                name = "numemon"
            }
            let digimon = catalog.digimonByName[name] ?? catalog.digimonByName["numemon"]
            if let digimon {
                unlock(digimon.name)
                assignFriendly(&battle, digimon: digimon, mode: .code)
                battle.combatOptions = [0, 1, 4]
                battle.screen = .combatMenu
                battle.combatMenuIndex = 0
                battle.message = "DIGITS CALL"
                play("summon_digimon")
            }
        } else if battle.codeStatus == 2 {
            battle.codeInput = String(battle.codeInput.dropLast())
            battle.codeStatus = 0
            play("button_a")
        }
    }

    private func battleCodeB(_ battle: inout UnityDTBattleState) {
        if battle.codeInput.isEmpty {
            battle.screen = .mainMenu
            play("button_b")
        } else {
            battle.codeInput = String(battle.codeInput.dropLast())
            battle.codeStatus = 0
            play("button_b")
        }
    }

    private func battleCodeLeft(_ battle: inout UnityDTBattleState) {
        if battle.codeInput.count >= 5, battle.codeStatus == 2 {
            battle.codeInput = String(battle.codeInput.dropLast())
            battle.codeStatus = 0
            play("button_a")
            return
        }
        guard battle.codeInput.count < 5 else { play("button_b"); return }
        if battle.codeSelectedAscii == 0x41 {
            battle.codeSelectedAscii = 0x39
        } else if battle.codeSelectedAscii == 0x30 {
            battle.codeSelectedAscii = 0x5A
        } else {
            battle.codeSelectedAscii -= 1
        }
        play("button_a")
    }

    private func battleCodeRight(_ battle: inout UnityDTBattleState) {
        if battle.codeInput.count >= 5, battle.codeStatus == 2 {
            battle.codeInput = String(battle.codeInput.dropLast())
            battle.codeStatus = 0
            play("button_a")
            return
        }
        guard battle.codeInput.count < 5 else { play("button_b"); return }
        if battle.codeSelectedAscii == 0x5A {
            battle.codeSelectedAscii = 0x30
        } else if battle.codeSelectedAscii == 0x39 {
            battle.codeSelectedAscii = 0x41
        } else {
            battle.codeSelectedAscii += 1
        }
        play("button_a")
    }

    private func attemptRegularDigivolve(_ battle: inout UnityDTBattleState) {
        guard let current = catalog.digimonByName[battle.playerName],
              let targetName = current.evolution,
              let target = catalog.digimonByName[targetName] else {
            battle.screen = .combatMenu
            battle.message = "NO EVO"
            play("button_b")
            return
        }
        let missingHP = max(0, battle.playerMaxHP - battle.playerHP)
        let callPointsBefore = battle.callPoints
        battle.callPoints = max(0, battle.callPoints - battle.callPointsForEvolution)
        // Battle.cs AttemptRegularDigivolve spends the points and plays
        // RegularEvolution either way; a failure is the same animation
        // with the same digimon on both sides, so it simply blinks and
        // stays put. There is no "FAILED" screen in the original.
        record(
            .spendCallPoints(
                before: callPointsBefore,
                after: battle.callPoints
            ),
            leading: true
        )
        let chance = evolveChance(target, playerLevel: playerLevel, callPoints: battle.callPointsForEvolution)
        if Double.random(in: 0..<1) < chance {
            assignFriendly(&battle, digimon: target, mode: .digivolution(missingHP: missingHP))
            battle.message = "EVOLVE"
        } else {
            battle.message = "FAILED"
        }
        battle.screen = .combatMenu
        battle.combatMenuIndex = 0
        play("summon_digimon")
    }

    private func attemptBoostFromDDock(_ battle: inout UnityDTBattleState) {
        guard let sacrificeName = state.ddocks[safe: battle.ddockIndex],
              !sacrificeName.isEmpty,
              let sacrifice = catalog.digimonByName[sacrificeName],
              var friendlyStats = battle.friendlyStats else {
            battle.message = "EMPTY"
            play("button_b")
            return
        }
        state.unlocked[sacrificeName] = 0
        state.ddocks[battle.ddockIndex] = ""
        // Battle.cs AttemptBoost plays BoostSucceed/BoostFailed as a
        // cutscene, not an inline message. presentTransition detects
        // this by diffing `message` against the "BOOST" set when the
        // d-dock list opened, so the two outcomes need their own text —
        // reusing "FAILED" collided with the regular-digivolve failure
        // check and played the wrong cutscene.
        if Double.random(in: 0..<1) < obeyChance(sacrifice, playerLevel: playerLevel) {
            let sacrificeStats = friendlyMutableStats(sacrifice)
            friendlyStats.HP += Int(ceil(Double(sacrificeStats.HP) / 2.0))
            friendlyStats.maxHP += Int(ceil(Double(sacrificeStats.HP) / 2.0))
            friendlyStats.EN += sacrificeStats.EN
            friendlyStats.CR += sacrificeStats.CR
            friendlyStats.AB += sacrificeStats.AB
            battle.friendlyStats = friendlyStats
            battle.playerHP = friendlyStats.HP
            battle.playerMaxHP = friendlyStats.maxHP
            battle.playerEN = friendlyStats.EN
            battle.message = "BOOSTED"
        } else {
            battle.message = "BOOST FAIL"
        }
        battle.screen = .combatMenu
        battle.combatMenuIndex = 0
        // The cutscene plays its own digipower_succeed/digipower_failed
        // cue; Unity's only immediate sound here is the d-dock tap.
        play("button_a")
    }

    private func deportCurrentDigimon() {
        guard var battle = state.battle else { return }
        battle.playerName = ""
        battle.originalPlayerName = ""
        battle.playerHP = 0
        battle.playerMaxHP = 0
        battle.playerEN = 0
        battle.friendlyStats = nil
        battle.combatOptions = [0, 1, 4]
        battle.screen = .mainMenu
        battle.message = "DEPORT"
        state.battle = battle
        play("button_a")
        save()
    }

    private func submitTurn(friendlyAttack startingFriendlyAttack: Int) {
        guard var battle = state.battle,
              let original = catalog.digimonByName[battle.originalPlayerName],
              let friendly = catalog.digimonByName[battle.playerName],
              let enemy = catalog.digimonByName[battle.enemyName],
              var friendlyStats = battle.friendlyStats else { return }

        // Battle.cs SubmitTurn opens by settling spirit power. A spirit
        // form pays its cost and the SPIRITS screen plays before the
        // turn; a called digimon earns 3 and it plays afterwards.
        let spiritBefore = state.spiritPower
        if battle.attacksCostSP == true {
            let cost = spiritCost(original, playerLevel: playerLevel)
            state.spiritPower = max(0, state.spiritPower - cost)
            record(
                .paySpiritPower(
                    before: spiritBefore,
                    after: state.spiritPower
                ),
                leading: true
            )
        }

        var friendlyAttack = startingFriendlyAttack
        var disobeyed = false
        if Double.random(in: 0..<1) > idleChance(original, playerLevel: playerLevel) {
            friendlyAttack = 3
            disobeyed = true
        } else if Double.random(in: 0..<1) > obeyChance(original, playerLevel: playerLevel) {
            friendlyAttack = Int.random(in: 0...2)
            disobeyed = true
        }

        let enemyAttack = chooseEnemyAttack(seed: state.steps + battle.turn + battle.enemyName.count, stats: battle.enemyStats)
        let result = chooseWinner(friendlyAttack: friendlyAttack, enemyAttack: enemyAttack, friendlyStats: friendlyStats, enemyStats: battle.enemyStats)
        var damage = result.damage

        if result.winner == 1 {
            let before = friendlyStats.HP
            friendlyStats.HP = max(0, friendlyStats.HP - damage)
            battle.playerHP = friendlyStats.HP
            battle.message = "\(enemy.displayName) -\(before - friendlyStats.HP)"
        } else if result.winner == 0 {
            if battle.boss {
                damage = max(0, damage - Int(floor(10.0 + (0.4 * Double(playerLevel)))))
            }
            let before = battle.enemyStats.HP
            battle.enemyStats.HP = max(0, battle.enemyStats.HP - damage)
            battle.enemyHP = battle.enemyStats.HP
            battle.message = "\(friendly.displayName) -\(before - battle.enemyStats.HP)"
        } else {
            battle.message = "CLASH"
        }

        if disobeyed {
            battle.message = "DISOBEY"
        }

        battle.friendlyStats = friendlyStats
        battle.lastFriendlyAttack = friendlyAttack
        battle.lastEnemyAttack = enemyAttack
        battle.screen = .combatMenu
        battle.turn += 1
        battle.flash = 6
        play("Battle/launch_attack")

        state.battle = battle

        if battle.attacksAwardSP == true {
            state.spiritPower = min(99, state.spiritPower + 3)
            // Battle.cs enqueues AWardSpiritPower every turn, even when
            // the meter is already full, so the screen always appears.
            record(
                .awardSpiritPower(
                    before: spiritBefore,
                    after: state.spiritPower
                )
            )
        }

        if battle.enemyStats.HP == 0 {
            winBattle()
        } else if friendlyStats.HP == 0 {
            loseBattle()
        } else {
            // Battle.cs sends a spirit form home once it can no longer
            // afford another attack.
            if battle.attacksCostSP == true,
               state.spiritPower
                < spiritCost(original, playerLevel: playerLevel) {
                deportCurrentDigimon()
            }
            save()
        }
    }

    /// Battle.cs WinBattle: level up, the character cheers, then the
    /// enemy is either levelled up or unlocked, and the distance drops.
    private func winBattle() {
        guard var battle = state.battle else { return }
        battle.victory = true
        battle.message = "WIN!"
        state.battle = battle

        recordDeportOfCurrentDigimon()
        let levelBefore = playerLevel
        addExperience(
            experienceGained(
                friendlyLevel: battle.playerLevel,
                enemyLevel: battle.enemyLevel
            )
        )
        if playerLevel > levelBefore {
            record(.levelUp(before: levelBefore, after: playerLevel))
        }
        record(.charHappy)

        if battle.boss || Bool.random() {
            let enemy = catalog.digimonByName[battle.enemyName]
            let isSpirit = enemy?.stage == 6
            let alreadyOwned = (state.unlocked[battle.enemyName] ?? 0) > 0
            unlock(battle.enemyName)
            if isSpirit {
                record(.receiveSpirit(battle.enemyName))
                if !alreadyOwned {
                    record(
                        .unlockDigimon(
                            name: battle.enemyName,
                            spiritForm: true
                        )
                    )
                }
            } else if alreadyOwned {
                record(.levelUpDigimon(battle.enemyName))
            } else {
                record(
                    .unlockDigimon(
                        name: battle.enemyName,
                        spiritForm: false
                    )
                )
            }
        }

        if battle.boss {
            markCurrentAreaComplete()
        } else {
            let distanceBefore = state.currentDistance
            state.currentDistance = max(1, state.currentDistance - 300)
            record(
                .changeDistance(
                    before: distanceBefore,
                    after: state.currentDistance
                )
            )
        }
        endBattle(message: "VICTORY", victory: true, defeat: false)
    }

    /// Battle.cs PlayAnimationDeportDigimon: whatever is on the field
    /// leaves it before the battle's result plays out. A spirit form
    /// gets the longer deport-spirit sequence.
    private func recordDeportOfCurrentDigimon() {
        guard let battle = state.battle,
              !battle.playerName.isEmpty else {
            return
        }
        if catalog.digimonByName[battle.playerName]?.stage == 6 {
            record(.deportSpirit(battle.playerName))
        } else {
            record(.deportDigimon(battle.playerName))
        }
    }

    /// Battle.cs LoseBattle: level down, the character despairs, the
    /// partner is punished or erased, and the distance grows.
    private func loseBattle() {
        guard let battle = state.battle else { return }

        recordDeportOfCurrentDigimon()
        let levelBefore = playerLevel
        addExperience(
            -experienceGained(
                friendlyLevel: battle.playerLevel,
                enemyLevel: battle.enemyLevel
            )
        )
        if playerLevel < levelBefore {
            record(.levelDown(before: levelBefore, after: playerLevel))
        }
        record(.charSad)

        let partner = battle.originalPlayerName.isEmpty
            ? battle.playerName
            : battle.originalPlayerName
        if !partner.isEmpty {
            let isSpirit = catalog.digimonByName[partner]?.stage == 6
            // Battle.cs sets IsCharacterDefeated here: always when a
            // spirit is lost or a digimon erased, and on a coin flip
            // when one merely levels down.
            if isSpirit {
                state.unlocked[partner] = 0
                state.isCharacterDefeated = true
                record(.loseSpirit(spirit: partner, enemy: battle.enemyName))
            } else if Bool.random() {
                let level = state.unlocked[partner] ?? 1
                if level > 1 {
                    state.unlocked[partner] = level - 1
                    if Bool.random() { state.isCharacterDefeated = true }
                    record(.levelDownDigimon(partner))
                } else {
                    state.unlocked[partner] = 0
                    state.ddocks = state.ddocks.map {
                        $0 == partner ? "" : $0
                    }
                    state.isCharacterDefeated = true
                    record(.eraseDigimon(partner))
                }
            }
        }

        let distanceBefore = state.currentDistance
        state.currentDistance += battle.boss ? 500 : 300
        record(
            .changeDistance(
                before: distanceBefore,
                after: state.currentDistance
            )
        )
        endBattle(message: "LOSE", victory: false, defeat: true)
    }

    private func endBattle(message: String, victory: Bool, defeat: Bool) {
        state.savedEvent = 0
        // Battle.cs ends with CloseApp(Screen.Character); there is no
        // win/lose screen in the original. The queued cutscenes are the
        // result, and the character screen is what they play over.
        state.screen = .character
        state.banner = message
        // The battle is kept until the next one starts so the turn that
        // ended it can still be animated.
        if var battle = state.battle {
            battle.message = message
            battle.victory = victory
            battle.defeat = defeat
            state.battle = battle
        }
        save()
    }

    private func escapeBattle() {
        addExperience(-experienceGained(friendlyLevel: playerLevel, enemyLevel: state.battle?.enemyLevel ?? playerLevel))
        state.currentDistance += 2000
        endBattle(message: "ESCAPE", victory: false, defeat: true)
    }

    private func finishResult() {
        state.battle = nil
        state.screen = .character
        state.banner = "CHARACTER"
        save()
    }

    private func markCurrentAreaComplete() {
        if state.completedAreas.indices.contains(state.currentWorld),
           state.completedAreas[state.currentWorld].indices.contains(state.currentArea) {
            state.completedAreas[state.currentWorld][state.currentArea] = true
        }
        let previousArea = state.currentArea
        if let world = currentWorld, state.currentArea + 1 < world.areas.count {
            state.currentArea += 1
            state.currentDistance = world.areas[state.currentArea].distance
            // Battle.cs TriggerVictoryAgainstBoss hands the player to a
            // new area and plays ForcedTravelMap — the map sliding to
            // the new quadrant, then the area and its distance.
            record(
                .forcedTravel(
                    world: state.currentWorld,
                    areaBefore: previousArea,
                    areaAfter: state.currentArea,
                    distance: state.currentDistance
                )
            )
        }
    }

    private func unlock(_ name: String) {
        if state.unlocked[name] == nil {
            state.unlocked[name] = 1
            if let digimon = catalog.digimonByName[name], digimon.stage != 5, digimon.stage != 6,
               let emptyIndex = state.ddocks.firstIndex(where: { $0.isEmpty }) {
                state.ddocks[emptyIndex] = name
            }
        }
    }

    private func isUnlocked(_ name: String) -> Bool {
        (state.unlocked[name] ?? 0) > 0
    }

    private func addExperience(_ amount: Int) {
        state.playerExperience = min(1_000_000, max(0, state.playerExperience + amount))
    }

    private func friendlyStats(_ digimon: UnityDTDigimon) -> UnityDTStats {
        let mutable = friendlyMutableStats(digimon)
        return UnityDTStats(HP: mutable.HP, EN: mutable.EN, CR: mutable.CR, AB: mutable.AB)
    }

    private func friendlyMutableStats(_ digimon: UnityDTDigimon) -> UnityDTMutableStats {
        let extra = max(0, (state.unlocked[digimon.name] ?? 1) - 1)
        let maxExtra = maxExtraLevel(digimon)
        func stat(_ base: Int) -> Int {
            guard extra > 0, maxExtra > 0 else { return base }
            return Int(ceil(Double(base) * (1.0 + (0.5 * (Double(extra) / Double(maxExtra))))))
        }
        return UnityDTMutableStats(UnityDTStats(
            HP: stat(digimon.stats.HP),
            EN: stat(digimon.stats.EN),
            CR: stat(digimon.stats.CR),
            AB: stat(digimon.stats.AB)
        ))
    }

    private func bossStats(_ digimon: UnityDTDigimon) -> UnityDTStats {
        let base = digimon.battleStats
        let level = bossLevel(digimon, playerLevel: playerLevel)
        func spiritStat(_ stat: Int) -> Int {
            let multiplier: Double
            if digimon.spiritType == 0 {
                multiplier = 0.25 + (0.005 * Double(level))
            } else if digimon.spiritType == 3 {
                multiplier = 0.20 + (0.008 * Double(level))
            } else {
                multiplier = 0.30 + (0.007 * Double(level))
            }
            return Int((Double(stat) * multiplier).rounded(.toNearestOrEven))
        }
        func regularBossStat(_ stat: Int) -> Int {
            Int((Double(stat) * (0.20 + (0.008 * Double(level)))).rounded(.toNearestOrEven))
        }
        return UnityDTStats(
            HP: digimon.stage == 6 ? spiritStat(base.HP) : regularBossStat(base.HP),
            EN: digimon.stage == 6 ? spiritStat(base.EN) : regularBossStat(base.EN),
            CR: digimon.stage == 6 ? spiritStat(base.CR) : regularBossStat(base.CR),
            AB: digimon.stage == 6 ? spiritStat(base.AB) : regularBossStat(base.AB)
        )
    }

    private func experienceGained(friendlyLevel: Int, enemyLevel: Int) -> Int {
        let a = 30.0 * Double(enemyLevel)
        let b = pow(Double((2 * enemyLevel) + 10), 2.5)
        let c = pow(Double(enemyLevel + friendlyLevel + 10), 2.5)
        let d = min(0.5, 0.025 + (0.025 * Double(friendlyLevel)))
        return Int(ceil(((a * (b / c)) + 1) * d))
    }

    private func maxExtraLevel(_ digimon: UnityDTDigimon) -> Int {
        let maxLevel: Int
        if digimon.stage == 0 {
            maxLevel = digimon.baseLevel * 2
        } else if digimon.stage == 6 || digimon.stage == 5 {
            maxLevel = digimon.baseLevel
        } else {
            maxLevel = Int(ceil(Double(digimon.baseLevel) * 1.5))
        }
        return max(0, maxLevel - digimon.baseLevel)
    }

    private func bossLevel(_ digimon: UnityDTDigimon, playerLevel: Int) -> Int {
        if digimon.stage == 6 {
            if digimon.spiritType == 3 {
                return Int((20.0 + (Double(playerLevel) * 0.8)).rounded(.toNearestOrEven))
            }
            return playerLevel
        }
        if digimon.stage == 5 {
            return playerLevel < 10 ? 10 : playerLevel
        }
        return playerLevel
    }

    private func callCost(_ digimon: UnityDTDigimon, playerLevel: Int) -> Int {
        let percLevelDiff = Double(digimon.baseLevel) / Double(playerLevel)
        let levelDiff = playerLevel - digimon.baseLevel
        if percLevelDiff < 0.55 && levelDiff >= 10 { return 0 }
        if percLevelDiff < 0.75 && levelDiff >= 5 { return 1 }
        if percLevelDiff < 0.90 && levelDiff >= 2 { return 2 }
        if percLevelDiff < 1.0 && levelDiff >= 1 { return 3 }
        if percLevelDiff == 1.0 { return 4 }
        if percLevelDiff < 1.30 { return 5 }
        if percLevelDiff < 1.60 { return 6 }
        if percLevelDiff < 2.0 { return 7 }
        if percLevelDiff < 3.0 { return 8 }
        if percLevelDiff < 4.0 { return 9 }
        return 10
    }

    private func spiritCost(_ digimon: UnityDTDigimon, playerLevel: Int) -> Int {
        var baseCost = 20.0
        var decay = 20.0
        if digimon.name == "susanoomon" {
            baseCost = 95
            decay = 50
        } else if digimon.stage == 5 {
            baseCost = 10
            decay = 20
        } else if digimon.stage == 6 {
            switch digimon.spiritType {
            case 0:
                baseCost = 20; decay = 30
            case 1:
                baseCost = 30; decay = 30
            case 2:
                baseCost = 35; decay = 40
            case 3:
                baseCost = 40; decay = 50
            case 4:
                baseCost = 55; decay = 60
            default:
                return 0
            }
        } else {
            return 0
        }
        return Int(floor(baseCost * pow(0.5, Double(playerLevel) / decay)))
    }

    private func evolveChance(_ digimon: UnityDTDigimon, playerLevel: Int, callPoints: Int) -> Double {
        let points = max(1, min(10, callPoints))
        let multiplier = Double(points - 1) / 20.0
        var extraLevel = Int(floor(Double(playerLevel) * multiplier))
        if extraLevel < points - 1 {
            extraLevel = points
        }
        let adjustedPlayerLevel = playerLevel + extraLevel
        let levelDiff = digimon.baseLevel - adjustedPlayerLevel
        if levelDiff <= 0 { return 1.0 }
        if levelDiff >= 10 { return 0.05 }

        let a = pow(Double(levelDiff), 2.0)
        let b = Double(levelDiff) / 10.0
        return max(0.05, 1.0 - (a / 100.0) + (0.05 * b))
    }

    private func obeyChance(_ digimon: UnityDTDigimon, playerLevel: Int) -> Double {
        let currentBase = (digimon.stage == 6 || digimon.stage == 5) ? bossLevel(digimon, playerLevel: playerLevel) : digimon.baseLevel
        let diff = currentBase - playerLevel
        if diff <= 0 { return 1.0 }
        if diff >= 10 { return 0.0 }
        return 1.0 - (pow(Double(diff), 2.0) / 100.0)
    }

    private func idleChance(_ digimon: UnityDTDigimon, playerLevel: Int) -> Double {
        let currentBase = (digimon.stage == 6 || digimon.stage == 5) ? bossLevel(digimon, playerLevel: playerLevel) : digimon.baseLevel
        let diff = currentBase - playerLevel
        if diff <= 0 { return 1.0 }
        if diff >= 20 { return 0.0 }
        return (pow(10.0, 1.5) - pow(Double(diff) / 2.0, 1.5)) / pow(10.0, -0.5)
    }

    private func chooseEnemyAttack(seed: Int, stats: UnityDTMutableStats) -> Int {
        let chanceEN = 30 + stats.EN
        let chanceCR = 30 + stats.CR
        let chanceAB = 30 + stats.AB
        let total = chanceEN + chanceCR + chanceAB
        let number = abs((seed &* 1103515245 &+ 12345) % max(1, total))
        if number < chanceEN { return 0 }
        if number < chanceEN + chanceCR { return 1 }
        return 2
    }

    func chooseWinner(
        friendlyAttack: Int,
        enemyAttack: Int,
        friendlyStats: UnityDTMutableStats,
        enemyStats: UnityDTMutableStats
    ) -> (winner: Int, damage: Int) {
        let friendlyDamage = friendlyStats.attackDamage(friendlyAttack)
        let enemyDamage = enemyStats.attackDamage(enemyAttack)
        if friendlyAttack == 3 {
            return (1, enemyDamage)
        }
        if friendlyAttack == enemyAttack {
            let diff = friendlyDamage - enemyDamage
            let damage = abs(diff)
            if friendlyAttack == 0 && friendlyStats.energyRank() != enemyStats.energyRank() {
                return friendlyStats.energyRank() > enemyStats.energyRank() ? (0, damage) : (1, damage)
            }
            if diff <= -TIE_DAMAGE_THRESHOLD { return (1, damage) }
            if diff >= TIE_DAMAGE_THRESHOLD { return (0, damage) }
            return (2, damage)
        }
        if friendlyAttack == 0 {
            if enemyAttack == 2 { return (0, friendlyDamage) }
            if enemyAttack == 1 { return (1, enemyDamage) }
        } else if friendlyAttack == 1 {
            if enemyAttack == 0 { return (0, friendlyDamage) }
            if enemyAttack == 2 { return (1, enemyDamage) }
        } else if friendlyAttack == 2 {
            if enemyAttack == 1 { return (0, friendlyDamage) }
            if enemyAttack == 0 { return (1, enemyDamage) }
        }
        return (2, 0)
    }

    private func tick() {
        frame = (frame + 1) % 10_000
        updateMiniGame(at: Date())
        if var battle = state.battle, battle.flash > 0 {
            battle.flash -= 1
            state.battle = battle
        }
    }

    private func wrap(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (value % count + count) % count
    }

    /// watchOS routes `AVAudioPlayer` output only while a playback
    /// session is active, so nothing is audible until this runs.
    private func activateAudioSessionIfNeeded() {
        guard !didActivateAudioSession else { return }
        didActivateAudioSession = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .default,
            policy: .default,
            options: [.duckOthers]
        )
        try? session.setActive(true)
    }

    func play(_ name: String) {
        activateAudioSessionIfNeeded()
        let clean = (name as NSString).lastPathComponent
        let subdir = (name as NSString).deletingLastPathComponent
        let directory = subdir == "." ? "UnityAudio" : "UnityAudio/\(subdir)"
        let url = Bundle.main.url(forResource: clean, withExtension: "mp3", subdirectory: directory)
            ?? Bundle.main.url(forResource: clean, withExtension: "mp3")
        guard let url else { return }
        // One clip at a time, like Unity's single AudioSource.
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.prepareToPlay()
        audioPlayer?.play()
    }

    /// `AudioManager.StopSound`, used by the battle animations to cut a
    /// travelling-attack loop the moment it connects.
    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

final class UnityWatchMotionBridge: ObservableObject {
    private let manager = CMMotionManager()
    private var detector = WristShakeDetector()

    func start(onShake: @escaping @MainActor () -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.04
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.rotationRate
            let accelMag = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
            let rotMag = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            if self.detector.ingest(accelerationMagnitude: accelMag, rotationMagnitude: rotMag, at: Date()) {
                Task { @MainActor in onShake() }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        detector.reset()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
