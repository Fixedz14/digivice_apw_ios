import Foundation

enum UnityDTMiniGameKind {
    case finder
    case jackpot
    case speedRunner
    case digiHunter
    case maze
    case energyWars
    case digiCatch
    case pipeMonsters
    case training
}

enum UnityDTMiniGame {
    case finder(UnityDTFinderGame)
    case jackpot(UnityDTJackpotGame)
    case speedRunner(UnityDTSpeedRunnerGame)
    case digiHunter(UnityDTDigiHunterGame)
    case maze(UnityDTMazeGame)
    case energyWars(UnityDTEnergyWarsGame)
    case digiCatch(UnityDTDigiCatchGame)
    case pipeMonsters(UnityDTPipeMonstersGame)
    case training(UnityDTTrainingGame)
}

struct UnityDTFinderGame {
    enum Phase: Equatable {
        case idle
        case hourglass
        case loading
        case failure
        case success
    }

    var phase: Phase = .idle
    var phaseStarted = Date()
    var tries = 0
}

struct UnityDTJackpotGame {
    enum Phase: Equatable {
        case intro
        case menu
        case showingPattern
        case input
        case result
    }

    var phase: Phase = .intro
    var phaseStarted = Date()
    var friendly: String
    var pattern: [Int]
    var playerSelection: [Int]
    var currentKey = 0
    var delay: TimeInterval
    var resultText = ""
    var resultCategory = 0
    var flashKey: Int?
    var flashUntil = Date.distantPast
}

struct UnityDTSpeedRow {
    var index: Int
    var y: Double
    var previousY: Double
    var collided = false
}

struct UnityDTSpeedRunnerGame {
    enum Phase: Equatable {
        case spawning
        case playing
        case respawning
        case gameOver
        case goal
    }

    var phase: Phase = .spawning
    var phaseStarted = Date()
    var lastUpdate = Date()
    var rows: [Int]
    var activeRows: [UnityDTSpeedRow] = []
    var nextRow = 0
    var rocketLane = 1
    var rowsBeaten = 0
    var roundRowsBeaten = 0
    var crashes = 0
    var currentSpeed = 0
    var finishY = -32.0
}

struct UnityDTHunterFace {
    var value = 0
    var expiresAt = Date.distantPast
    var explosionUntil = Date.distantPast
}

struct UnityDTDigiHunterGame {
    enum Phase: Equatable {
        case intro
        case playing
        case finishing
        case end
    }

    var phase: Phase = .intro
    var phaseStarted = Date()
    var playStarted = Date.distantPast
    var score = 0
    var playerX = 0
    var playerY = 0
    var faces = [UnityDTHunterFace](
        repeating: UnityDTHunterFace(),
        count: 9
    )
    var nextSpawn = Date.distantPast
}

enum UnityDTMazeDirection: Equatable {
    case left
    case right
    case up
    case down
}

struct UnityDTMazeGame {
    enum Phase: Equatable {
        case menu
        case playing
        case defeat
        case victory
    }

    var phase: Phase = .menu
    var option = 0
    var paths = [Int](repeating: 0, count: 15 * 12)
    var playerX = -1
    var playerY = 0
    var timeRemaining = 45
    var lastSecond = Date()
    var resultReady = false
}

private enum UnityDTJackpotReward {
    case increaseDistance(Int)
    case reduceDistance(Int)
    case punishDigimon
    case rewardDigimon
    case unlockOwnedCode
    case unlockNewCode
    case dataStorm
    case loseSpirit(Int)
    case gainSpirit(Int)
    case levelDown
    case forceLevelDown
    case levelUp
    case forceLevelUp
    case triggerBattle
}

extension UnityDTGameModel {
    var miniGameUsesHoldControls: Bool {
        guard let miniGame else { return false }
        if case .finder(let game) = miniGame {
            return game.phase != .success
        }
        if case .speedRunner(let game) = miniGame {
            return game.phase == .spawning
                || game.phase == .playing
                || game.phase == .respawning
        }
        return false
    }

    func miniGameHold(direction: Int) {
        guard let miniGame else { return }
        switch miniGame {
        case .finder(var game):
            guard direction == 0,
                  game.phase != .success else {
                return
            }
            play("button_a")
            if game.phase == .failure {
                game.phase = .idle
                game.phaseStarted = Date()
            } else {
                game.phase = .hourglass
                game.phaseStarted = Date()
                game.tries = 0
            }
            self.miniGame = .finder(game)

        case .speedRunner(var game):
            if game.phase == .spawning
                || game.phase == .playing
                || game.phase == .respawning {
                game.rocketLane = direction < 0
                    ? 0
                    : direction > 0 ? 2 : 1
                self.miniGame = .speedRunner(game)
            }

        default:
            break
        }
    }

    func miniGameReleaseHold() {
        guard let miniGame else { return }
        switch miniGame {
        case .finder(var game):
            if game.phase == .hourglass
                || game.phase == .loading {
                game.phase = .idle
                game.phaseStarted = Date()
                self.miniGame = .finder(game)
            }

        case .speedRunner(var game):
            if game.phase == .spawning
                || game.phase == .playing
                || game.phase == .respawning {
                game.rocketLane = 1
                self.miniGame = .speedRunner(game)
            }

        default:
            break
        }
    }

    var miniGameNeedsDownInput: Bool {
        guard let miniGame else { return false }
        switch miniGame {
        case .jackpot(let game):
            return game.phase == .input
        case .maze(let game):
            return game.phase == .playing
        default:
            return false
        }
    }

    func miniGameDown() {
        guard let miniGame else { return }
        switch miniGame {
        case .jackpot(var game):
            if game.phase == .input {
                jackpotInput(2, game: &game)
                self.miniGame = .jackpot(game)
            }
        case .maze(var game):
            if game.phase == .playing {
                _ = moveMazePlayer(&game, .down)
                self.miniGame = .maze(game)
            }
        default:
            break
        }
    }

    func configureQAFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-screen")
                || arguments.contains("--qa-battle-win")
                || arguments.contains("--qa-mini")
                || arguments.contains("--qa-walking")
                || arguments.contains("--qa-opening")
                || arguments.contains("--qa-cutscene")
                || arguments.contains("--qa-world")
                || arguments.contains("--qa-encounter")
                || arguments.contains("--qa-defeated")
                || arguments.contains("--qa-char")
                || arguments.contains("--qa-partner")
                || arguments.contains("--qa-battle") else {
            return
        }
        defer { save() }

        // `--qa-char N` picks the player character (0 Takuya, 1 Koji,
        // 2 Zoe, 3 JP, 4 Tommy, 5 Koichi) so a cutscene can be compared
        // against a recording of the same character.
        let qaChar: Int = {
            if let index = arguments.firstIndex(of: "--qa-char"),
               arguments.indices.contains(index + 1),
               let value = Int(arguments[index + 1]),
               (0...5).contains(value) {
                return value
            }
            return 0
        }()

        if state.playerChar == nil || arguments.contains("--qa-char") {
            state.playerChar = qaChar
            state.charIndex = qaChar
            state.spiritPower = 99
            state.currentWorld = 0
            state.currentArea = 0
            state.currentDistance = catalog.worlds.first?
                .areas.first?.distance ?? 6000
            state.completedAreas = catalog.worlds.map {
                [Bool](repeating: false, count: $0.areas.count)
            }
            let spirit = catalog.playerSpiritName(for: qaChar)
            let initial = catalog.initials.first ?? "agumon"
            state.unlocked[spirit] = 1
            state.unlocked[initial] = 1
            state.ddocks = [initial, "", "", ""]
        }

        // `--qa-world <n> [--qa-area <n>]` drops the player into a world
        // so its map, area list and bosses can be inspected before the
        // progression that leads there exists.
        if let worldIndex = arguments.firstIndex(of: "--qa-world"),
           arguments.indices.contains(worldIndex + 1),
           let number = Int(arguments[worldIndex + 1]),
           let world = catalog.worlds.first(where: { $0.number == number }) {
            var area = 0
            if let areaIndex = arguments.firstIndex(of: "--qa-area"),
               arguments.indices.contains(areaIndex + 1),
               let value = Int(arguments[areaIndex + 1]),
               world.areas.indices.contains(value) {
                area = value
            }
            state.currentWorld = number
            state.currentArea = area
            state.currentDistance = world.areas[area].distance
            state.mapDisplayMap = world.areas[area].map
            state.mapDisplayAreaIndex = 0
            state.mapPage = world.areas[area].map
        }

        // Drops the player into the defeated state: sad pose, flashing
        // defeated symbol, shake and every app but the Camp locked out.
        if arguments.contains("--qa-defeated") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 0
            state.isCharacterDefeated = true
        }

        // `--qa-partner <name>` drops a digimon into the first d-dock,
        // so a cutscene can be rendered with a specific one.
        if let index = arguments.firstIndex(of: "--qa-partner"),
           arguments.indices.contains(index + 1),
           catalog.digimonByName[arguments[index + 1]] != nil {
            let name = arguments[index + 1]
            state.unlocked[name] = 1
            state.ddocks[0] = name
        }

        // Arms the walking event so the very next tap rolls a regular
        // encounter, the way running out of steps does.
        if arguments.contains("--qa-encounter") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 1
            state.currentDistance = max(2, state.currentDistance)
            state.pendingEnemy = catalog.randomBattleDigimon(
                playerLevel: playerLevel,
                excluding: []
            ).name
            if state.ddocks.allSatisfy(\.isEmpty) {
                let initial = catalog.initials.first ?? "agumon"
                state.unlocked[initial] = 1
                state.ddocks = [initial, "", "", ""]
            }
        }

        // Hands over every Human and Animal spirit, so the FUSION
        // browser's ready state and its transformation can be reached.
        if arguments.contains("--qa-unlock-spirits") {
            for digimon in catalog.digimon
            where digimon.stage == 6
                && (digimon.spiritType == 0 || digimon.spiritType == 1) {
                state.unlocked[digimon.name] = 1
            }
        }

        if arguments.contains("--qa-walking") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 0
            return
        }

        if arguments.contains("--qa-opening")
            || arguments.contains("--qa-cutscene") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 0
            return
        }

        // Lands straight on the attack menu against an almost-dead
        // enemy, so one tap resolves the battle and plays the whole
        // victory chain.
        if arguments.contains("--qa-battle-win") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 2
            state.currentDistance = 1
            let initial = catalog.initials.first ?? "agumon"
            state.unlocked[initial] = 1
            state.ddocks = [initial, "", "", ""]
            qaFinishNextBattle = true
            return
        }

        // Deterministic battle entry: a boss call always starts a battle,
        // where a regular event only does so 85% of the time.
        if arguments.contains("--qa-battle") {
            state.screen = .character
            state.app = nil
            state.savedEvent = 2
            state.currentDistance = 1
            if state.ddocks.allSatisfy(\.isEmpty) {
                let initial = catalog.initials.first ?? "agumon"
                state.unlocked[initial] = 1
                state.ddocks = [initial, "", "", ""]
            }
            return
        }

        if let screenIndex = arguments.firstIndex(of: "--qa-screen"),
           arguments.indices.contains(screenIndex + 1) {
            let screen = arguments[screenIndex + 1]
            if screen == "map" {
                state.screen = .app
                state.app = .map
                state.mapScreen = .map
                state.mapDisplayMap = currentArea?.map ?? 0
            } else if screen == "game" {
                state.screen = .app
                state.app = .game
                state.mapPage = 0
                state.databaseIndex = 0
            } else if screen == "energy-wars" {
                state.screen = .app
                state.app = .game
                startMiniGame(.energyWars)
            } else if screen == "digi-catch" {
                state.screen = .app
                state.app = .game
                startMiniGame(.digiCatch)
            } else if screen == "pipe-monsters" {
                state.screen = .app
                state.app = .game
                startMiniGame(.pipeMonsters)
            } else if screen == "game-reward" {
                state.screen = .app
                state.app = .game
                state.mapPage = 1
                state.databaseIndex = 0
            } else if screen == "game-travel" {
                state.screen = .app
                state.app = .game
                state.mapPage = 2
                state.databaseIndex = 0
            } else if screen == "home" {
                state.screen = .character
                state.app = nil
            } else if screen == "status" {
                state.screen = .app
                state.app = .status
                state.statusPage = 0
            } else if screen == "status-reset" {
                state.screen = .app
                state.app = .status
                state.statusPage = 8
                statusResetConfirmStep = 0
            } else if screen == "database" {
                state.screen = .app
                state.app = .database
                state.databaseScreen = .menu
                state.databaseMenuIndex = 0
            } else if screen == "digits" {
                state.screen = .app
                state.app = .digits
                state.digitsCode = ""
                state.codeSelectedAscii = 0x41
                state.codeStatus = 0
            } else if screen == "camp" {
                state.screen = .app
                state.app = .camp
            } else if screen == "connect" {
                state.screen = .app
                state.app = .connect
            } else if screen == "menu" {
                state.screen = .mainMenu
                state.app = nil
                state.menuIndex = 0
            }
        }

        if let miniIndex = arguments.firstIndex(of: "--qa-mini"),
           arguments.indices.contains(miniIndex + 1) {
            state.screen = .app
            state.app = .game
            let name = arguments[miniIndex + 1]
            switch name {
            case "finder":
                state.mapPage = 0
                state.databaseIndex = 0
            case "jackpot":
                state.mapPage = 1
                state.databaseIndex = 0
            case "speed":
                state.mapPage = 2
                state.databaseIndex = 0
            case "hunter":
                state.mapPage = 2
                state.databaseIndex = 2
            case "maze":
                state.mapPage = 2
                state.databaseIndex = 3
            default:
                return
            }
            centerTap()
        }
    }

    func startMiniGame(_ kind: UnityDTMiniGameKind) {
        switch kind {
        case .energyWars:
            startEnergyWars()

        case .digiCatch:
            startDigiCatch()

        case .finder:
            miniGame = .finder(UnityDTFinderGame())

        case .jackpot:
            let friendly = state.ddocks
                .filter { !$0.isEmpty }
                .randomElement()
                ?? activePartnerName
            let length = Int.random(in: 4...10)
            let pattern = (0..<length).map { _ in
                Int.random(in: 0..<4)
            }
            miniGame = .jackpot(
                UnityDTJackpotGame(
                    friendly: friendly,
                    pattern: pattern,
                    playerSelection: [Int](
                        repeating: 0,
                        count: length
                    ),
                    delay: Double.random(in: 0.25...0.75)
                )
            )

        case .speedRunner:
            miniGame = .speedRunner(
                UnityDTSpeedRunnerGame(
                    rows: generateSpeedRunnerRows()
                )
            )
            play("Game/Speed Runner/rocket_start")

        case .digiHunter:
            miniGame = .digiHunter(UnityDTDigiHunterGame())
            play("Game/DigiHunter/digihunter_start")

        case .maze:
            miniGame = .maze(UnityDTMazeGame())

        case .pipeMonsters:
            startPipeMonsters()

        case .training:
            startTraining()
        }
    }

    func miniGameLeft() {
        if case .training(var game) = miniGame {
            trainingMove(&game, delta: -1)
            miniGame = .training(game)
            return
        }
        if case .pipeMonsters(var game) = miniGame {
            pipeMonstersMove(&game, delta: -1)
            miniGame = .pipeMonsters(game)
            return
        }
        if case .digiCatch(var game) = miniGame {
            digiCatchMove(&game, delta: -1)
            miniGame = .digiCatch(game)
            return
        }
        if case .energyWars(var game) = miniGame {
            energyWarsPush(&game)
            if miniGame != nil { miniGame = .energyWars(game) }
            return
        }
        guard let miniGame else { return }
        switch miniGame {
        case .finder:
            play("button_b")

        case .jackpot(var game):
            if game.phase == .input {
                jackpotInput(0, game: &game)
            } else {
                play("button_b")
            }
            self.miniGame = .jackpot(game)

        case .speedRunner(var game):
            if game.phase == .playing {
                game.rocketLane = 0
            }
            self.miniGame = .speedRunner(game)

        case .digiHunter(var game):
            if game.phase == .playing {
                game.playerY = (game.playerY + 1) % 3
                play("button_a")
            }
            self.miniGame = .digiHunter(game)

        case .maze(var game):
            if game.phase == .menu {
                game.option = game.option == 0 ? 1 : 0
                play("button_a")
            } else if game.phase == .playing {
                _ = moveMazePlayer(&game, .left)
            }
            self.miniGame = .maze(game)
        default:
            break
        }
    }

    func miniGameRight() {
        if case .training(var game) = miniGame {
            trainingMove(&game, delta: 1)
            miniGame = .training(game)
            return
        }
        if case .pipeMonsters(var game) = miniGame {
            pipeMonstersMove(&game, delta: 1)
            miniGame = .pipeMonsters(game)
            return
        }
        if case .digiCatch(var game) = miniGame {
            digiCatchMove(&game, delta: 1)
            miniGame = .digiCatch(game)
            return
        }
        if case .energyWars(var game) = miniGame {
            energyWarsPush(&game)
            if miniGame != nil { miniGame = .energyWars(game) }
            return
        }
        guard let miniGame else { return }
        switch miniGame {
        case .finder:
            play("button_b")

        case .jackpot(var game):
            if game.phase == .input {
                jackpotInput(1, game: &game)
            } else {
                play("button_b")
            }
            self.miniGame = .jackpot(game)

        case .speedRunner(var game):
            if game.phase == .playing {
                game.rocketLane = 2
            }
            self.miniGame = .speedRunner(game)

        case .digiHunter(var game):
            if game.phase == .playing {
                game.playerX = (game.playerX + 1) % 3
                play("button_a")
            }
            self.miniGame = .digiHunter(game)

        case .maze(var game):
            if game.phase == .menu {
                game.option = game.option == 0 ? 1 : 0
                play("button_a")
            } else if game.phase == .playing {
                _ = moveMazePlayer(&game, .right)
            }
            self.miniGame = .maze(game)
        default:
            break
        }
    }

    func miniGameA() {
        guard let miniGame else { return }
        let now = Date()
        switch miniGame {
        case .training(var game):
            trainingConfirm(&game)
            if self.miniGame != nil { self.miniGame = .training(game) }

        case .pipeMonsters(var game):
            pipeMonstersSmash(&game)
            if self.miniGame != nil {
                self.miniGame = .pipeMonsters(game)
            }

        case .energyWars(var game):
            energyWarsPush(&game)
            if self.miniGame != nil {
                self.miniGame = .energyWars(game)
            }

        case .digiCatch(var game):
            if game.phase == .intro {
                game.phase = .playing
                game.phaseStarted = now
                game.nextSpawn = now
            }
            self.miniGame = .digiCatch(game)

        case .finder(var game):
            if game.phase == .idle {
                game.phase = .hourglass
                game.phaseStarted = now
                game.tries = 0
                play("button_a")
            } else if game.phase == .failure {
                game.phase = .idle
                game.phaseStarted = now
                play("button_a")
            }
            self.miniGame = .finder(game)

        case .jackpot(var game):
            switch game.phase {
            case .menu:
                game.phase = .showingPattern
                game.phaseStarted = now
                play("button_a")
            case .input:
                jackpotInput(3, game: &game)
            case .result:
                closeMiniGame()
                return
            default:
                break
            }
            self.miniGame = .jackpot(game)

        case .speedRunner(var game):
            if game.phase == .playing {
                game.rocketLane = 1
            } else if game.phase == .gameOver
                        || game.phase == .goal {
                submitMiniGameScore(speedRunnerScore(game))
                closeMiniGame()
                return
            }
            self.miniGame = .speedRunner(game)

        case .digiHunter(var game):
            if game.phase == .playing {
                let index = game.playerY * 3 + game.playerX
                if game.faces[index].value == 1 {
                    game.score += 1
                    game.faces[index].value = -1
                    game.faces[index].explosionUntil =
                        now.addingTimeInterval(0.35)
                    play("Game/Speed Runner/rocket_asteroid")
                } else if game.faces[index].value == 2 {
                    game.score -= 1
                    game.faces[index].value = -1
                    game.faces[index].explosionUntil =
                        now.addingTimeInterval(0.35)
                    play("Game/Speed Runner/rocket_crash")
                } else {
                    play("button_a")
                }
            } else if game.phase == .end {
                submitMiniGameScore(max(0, game.score * 15))
                closeMiniGame()
                return
            }
            self.miniGame = .digiHunter(game)

        case .maze(var game):
            switch game.phase {
            case .menu:
                if game.option == 0 {
                    game.paths = generateMazePaths()
                    game.playerX = -1
                    game.playerY = 0
                    game.timeRemaining = 45
                    game.lastSecond = now
                    game.resultReady = false
                    game.phase = .playing
                    play("button_a")
                } else {
                    closeMiniGame()
                    return
                }
            case .playing:
                _ = moveMazePlayer(&game, .up)
            case .defeat:
                if game.resultReady {
                    closeMiniGame()
                    return
                }
            case .victory:
                submitMiniGameScore(
                    Int(
                        round(
                            (420.0 / 45.0)
                                * Double(game.timeRemaining)
                        )
                    )
                )
                closeMiniGame()
                return
            }
            self.miniGame = .maze(game)
        }
    }

    func miniGameB() {
        guard let miniGame else { return }
        switch miniGame {
        case .training(var game):
            if trainingBack(&game) {
                closeMiniGame()
            } else {
                self.miniGame = .training(game)
            }

        case .pipeMonsters(let game):
            if game.phase == .over {
                submitMiniGameScore(max(0, game.score * 15))
            }
            closeMiniGame()

        case .finder(let game):
            if game.phase == .idle {
                closeMiniGame()
            }

        case .jackpot:
            closeMiniGame()
            return

        case .speedRunner(let game):
            if game.phase == .gameOver || game.phase == .goal {
                submitMiniGameScore(speedRunnerScore(game))
            }
            closeMiniGame()

        case .digiHunter(let game):
            if game.phase == .end {
                submitMiniGameScore(max(0, game.score * 15))
            }
            closeMiniGame()

        case .maze:
            closeMiniGame()
        default:
            break
        }
    }

    func updateMiniGame(at now: Date) {
        guard let miniGame else { return }
        switch miniGame {
        case .training:
            break

        case .pipeMonsters(var game):
            updatePipeMonsters(&game, now: now)
            if self.miniGame != nil {
                self.miniGame = .pipeMonsters(game)
            }

        case .energyWars(var game):
            updateEnergyWars(&game, now: now)
            if self.miniGame != nil {
                self.miniGame = .energyWars(game)
            }

        case .digiCatch(var game):
            updateDigiCatch(&game, now: now)
            if self.miniGame != nil {
                self.miniGame = .digiCatch(game)
            }

        case .finder(var game):
            updateFinder(&game, now: now)
            if self.miniGame != nil {
                self.miniGame = .finder(game)
            }

        case .jackpot(var game):
            updateJackpot(&game, now: now)
            if self.miniGame != nil {
                self.miniGame = .jackpot(game)
            }

        case .speedRunner(var game):
            updateSpeedRunner(&game, now: now)
            self.miniGame = .speedRunner(game)

        case .digiHunter(var game):
            updateDigiHunter(&game, now: now)
            self.miniGame = .digiHunter(game)

        case .maze(var game):
            updateMaze(&game, now: now)
            self.miniGame = .maze(game)
        }
    }

    private func updateFinder(
        _ game: inout UnityDTFinderGame,
        now: Date
    ) {
        let elapsed = now.timeIntervalSince(game.phaseStarted)
        if game.phase == .hourglass, elapsed >= 0.5 {
            beginFinderRound(&game, now: now)
        } else if game.phase == .loading, elapsed >= 1.75 {
            game.tries += 1
            beginFinderRound(&game, now: now)
        } else if game.phase == .success,
                  elapsed >= (114.0 * 1.75 / 64.0) {
            self.miniGame = nil
            state.app = nil
            startRandomBattle()
        }
    }

    private func beginFinderRound(
        _ game: inout UnityDTFinderGame,
        now: Date
    ) {
        if game.tries == 5 {
            game.phase = .failure
        } else if Int.random(in: 0..<10) == 0 {
            game.phase = .success
        } else {
            game.phase = .loading
        }
        game.phaseStarted = now
    }

    private func updateJackpot(
        _ game: inout UnityDTJackpotGame,
        now: Date
    ) {
        let elapsed = now.timeIntervalSince(game.phaseStarted)
        if game.phase == .intro, elapsed >= 13.4 {
            game.phase = .menu
            game.phaseStarted = now
        } else if game.phase == .showingPattern {
            let total = 0.75
                + (Double(game.pattern.count) * game.delay)
                + (game.delay * 2.0)
            if elapsed >= total {
                game.phase = .input
                game.phaseStarted = now
            }
        } else if game.phase == .input, elapsed >= 12.0 {
            finishJackpot(&game, now: now)
        } else if game.phase == .result, elapsed >= 4.0 {
            closeMiniGame()
        }
    }

    private func jackpotInput(
        _ key: Int,
        game: inout UnityDTJackpotGame
    ) {
        guard game.phase == .input,
              game.currentKey < game.playerSelection.count else {
            return
        }
        game.playerSelection[game.currentKey] = key
        game.currentKey += 1
        game.flashKey = key
        game.flashUntil = Date().addingTimeInterval(0.25)
        play("button_a")
        if game.currentKey == game.playerSelection.count {
            finishJackpot(&game, now: Date())
        }
    }

    private func finishJackpot(
        _ game: inout UnityDTJackpotGame,
        now: Date
    ) {
        let correct = zip(
            game.pattern,
            game.playerSelection
        ).filter { $0.0 == $0.1 }.count
        let percentage = Double(correct)
            / Double(max(1, game.pattern.count))
        var category: Int
        if percentage < 0.26 {
            category = 0
        } else if percentage < 0.51 {
            category = 1
        } else if percentage < 0.76 {
            category = 2
        } else {
            category = 3
        }
        if percentage == 1, game.pattern.count >= 8 {
            category = 4
        }
        game.resultCategory = category
        // JackpotBox.cs plays the box's own outcome before the reward:
        // it shrugs the attack off below half marks, otherwise it blows
        // apart. `EnqueueRewardAnimation` then follows with the reward,
        // which `applyJackpotReward` records as it applies it.
        if category < 2 {
            record(.boxResists(game.friendly))
        } else {
            record(.destroyBox)
        }
        game.resultText = applyJackpotReward(
            jackpotReward(category: category),
            friendly: game.friendly
        )
        if state.screen == .battle {
            miniGame = nil
            return
        }
        game.phase = .result
        game.phaseStarted = now
        play(category < 2 ? "punishment" : "reward")
    }

    private func jackpotReward(
        category: Int
    ) -> UnityDTJackpotReward {
        let roll = Double.random(in: 0..<1)
        switch category {
        case 0:
            if roll < 0.40 { return .increaseDistance(500) }
            if roll < 0.60 { return .punishDigimon }
            if roll < 0.70 { return .dataStorm }
            if roll < 0.80 { return .loseSpirit(10) }
            if roll < 0.90 { return .forceLevelDown }
            if roll < 0.95 { return .punishDigimon }
            return .increaseDistance(2000)
        case 1:
            if roll < 0.40 { return .increaseDistance(500) }
            if roll < 0.65 { return .triggerBattle }
            if roll < 0.75 { return .punishDigimon }
            if roll < 0.85 { return .dataStorm }
            if roll < 0.95 { return .loseSpirit(10) }
            return .levelDown
        case 2:
            if roll < 0.35 { return .reduceDistance(500) }
            if roll < 0.65 { return .triggerBattle }
            if roll < 0.80 { return .increaseDistance(300) }
            if roll < 0.90 { return .gainSpirit(10) }
            return .rewardDigimon
        case 3:
            if roll < 0.30 { return .reduceDistance(500) }
            if roll < 0.55 { return .gainSpirit(10) }
            if roll < 0.80 { return .rewardDigimon }
            if roll < 0.95 { return .levelUp }
            return .unlockOwnedCode
        default:
            if roll < 0.55 { return .rewardDigimon }
            if roll < 0.65 { return .reduceDistance(1000) }
            if roll < 0.75 { return .forceLevelUp }
            if roll < 0.85 { return .gainSpirit(99) }
            if roll < 0.95 { return .unlockOwnedCode }
            return .unlockNewCode
        }
    }

    private func applyJackpotReward(
        _ reward: UnityDTJackpotReward,
        friendly: String
    ) -> String {
        switch reward {
        case .increaseDistance(let amount):
            let before = state.currentDistance
            state.currentDistance += amount
            record(
                .rewardDistance(
                    punishment: true,
                    before: before,
                    after: state.currentDistance
                )
            )
            record(.charSad)
            return "+\(amount) DIST"
        case .reduceDistance(let amount):
            let before = state.currentDistance
            state.currentDistance = max(
                1,
                state.currentDistance - amount
            )
            record(
                .rewardDistance(
                    punishment: false,
                    before: before,
                    after: state.currentDistance
                )
            )
            record(.charHappy)
            return "-\(amount) DIST"
        case .punishDigimon:
            let old = state.unlocked[friendly] ?? 1
            state.unlocked[friendly] = max(0, old - 1)
            if state.unlocked[friendly] == 0 {
                state.ddocks = state.ddocks.map {
                    $0 == friendly ? "" : $0
                }
                record(.eraseDigimon(friendly))
            } else {
                record(.levelDownDigimon(friendly))
            }
            record(.charSad)
            return "LEVEL DOWN"
        case .rewardDigimon:
            let digimon = catalog.randomBattleDigimon(
                playerLevel: playerLevel + 20,
                excluding: []
            )
            let owned = (state.unlocked[digimon.name] ?? 0) > 0
            state.unlocked[digimon.name] =
                (state.unlocked[digimon.name] ?? 0) + 1
            if let empty = state.ddocks.firstIndex(
                where: { $0.isEmpty }
            ) {
                state.ddocks[empty] = digimon.name
            }
            // GameManager: SummonDigimon, then UnlockDigimon for a new
            // one or LevelUpDigimon for one already owned.
            record(
                owned
                    ? .levelUpDigimon(digimon.name)
                    : .unlockDigimon(
                        name: digimon.name,
                        spiritForm: digimon.stage == 6
                    )
            )
            record(.charHappy)
            return digimon.displayName
        case .unlockOwnedCode:
            let owned = state.unlocked.keys.filter {
                (state.unlocked[$0] ?? 0) > 0
                    && catalog.digimonByName[$0]?.code != nil
            }
            let name = owned.randomElement() ?? friendly
            let code = catalog.digimonByName[name]?.code ?? "-----"
            record(.rewardCode(digimon: name, code: code))
            record(.charHappy)
            return code
        case .unlockNewCode:
            let locked = catalog.digimon.filter {
                (state.unlocked[$0.name] ?? 0) == 0
                    && $0.code != nil
            }
            guard let digimon = locked.randomElement() else {
                return "NO CODE"
            }
            state.unlocked[digimon.name] = 1
            let code = digimon.code ?? "-----"
            record(.rewardCode(digimon: digimon.name, code: code))
            record(
                .unlockDigimon(
                    name: digimon.name,
                    spiritForm: digimon.stage == 6
                )
            )
            record(.charHappy)
            return code
        case .dataStorm:
            let worldBefore = state.currentWorld
            let areaBefore = state.currentArea
            applyMiniGameDataStorm()
            let moved = worldBefore != state.currentWorld
                || areaBefore != state.currentArea
            record(.dataStorm(moved: moved))
            if moved {
                record(
                    .displayNewArea(
                        world: state.currentWorld,
                        area: state.currentArea,
                        distance: state.currentDistance
                    )
                )
            } else {
                record(.charHappy)
            }
            return "DIGISTORM"
        case .loseSpirit(let amount):
            let before = state.spiritPower
            state.spiritPower = max(
                0,
                state.spiritPower - amount
            )
            record(
                .rewardSpiritPower(
                    punishment: true,
                    before: before,
                    after: state.spiritPower
                )
            )
            record(.charSad)
            return "-\(amount) SP"
        case .gainSpirit(let amount):
            let before = state.spiritPower
            state.spiritPower = min(
                99,
                state.spiritPower + amount
            )
            record(
                .rewardSpiritPower(
                    punishment: false,
                    before: before,
                    after: state.spiritPower
                )
            )
            record(.charHappy)
            return "+\(amount) SP"
        case .levelDown:
            if playerLevelProgression() <= 0.5 {
                levelPlayer(down: true)
            } else {
                state.currentDistance += 500
            }
            return "LEVEL DOWN"
        case .forceLevelDown:
            if playerLevelProgression() > 0 {
                levelPlayer(down: true)
            } else {
                state.currentDistance += 500
            }
            return "LEVEL DOWN"
        case .levelUp:
            if playerLevelProgression() >= 0.5 {
                levelPlayer(down: false)
            } else {
                state.currentDistance = max(
                    1,
                    state.currentDistance - 500
                )
            }
            return "LEVEL UP"
        case .forceLevelUp:
            if playerLevelProgression() > 0 {
                levelPlayer(down: false)
            } else {
                state.currentDistance = max(
                    1,
                    state.currentDistance - 500
                )
            }
            return "LEVEL UP"
        case .triggerBattle:
            miniGame = nil
            state.app = nil
            startRandomBattle()
            return "BATTLE"
        }
    }

    private func playerLevelProgression() -> Double {
        let level = playerLevel
        let floorExperience = level * level * level
        let next = (level + 1) * (level + 1) * (level + 1)
        return Double(state.playerExperience - floorExperience)
            / Double(max(1, next - floorExperience))
    }

    private func levelPlayer(down: Bool) {
        let level = playerLevel
        if down {
            let last = max(1, level - 1)
            state.playerExperience = last * last * last
        } else {
            let next = level + 1
            state.playerExperience = next * next * next
        }
    }

    private func applyMiniGameDataStorm() {
        let uncompleted = (currentWorld?.areas ?? [])
            .map(\.number)
            .filter {
                state.completedAreas[
                    safe: state.currentWorld
                ]?[safe: $0] != true
            }
        if uncompleted.count >= 2,
           Double.random(in: 0..<1) < 0.33,
           let area = uncompleted.randomElement() {
            state.currentArea = area
            state.currentDistance += 1000
        }
    }

    private func generateSpeedRunnerRows() -> [Int] {
        var rows: [Int] = []
        while rows.count < 70 {
            var row = 0
            for _ in 0..<2 {
                row |= 1 << Int.random(in: 0..<3)
            }
            if rows.last != row {
                rows.append(row)
            }
        }
        return rows
    }

    private func updateSpeedRunner(
        _ game: inout UnityDTSpeedRunnerGame,
        now: Date
    ) {
        let elapsed = now.timeIntervalSince(game.phaseStarted)
        if game.phase == .spawning {
            if elapsed >= 3.0 {
                game.phase = .playing
                game.phaseStarted = now
                game.lastUpdate = now
            }
            return
        }
        if game.phase == .respawning {
            if elapsed >= 3.5 {
                game.phase = .playing
                game.phaseStarted = now
                game.lastUpdate = now
            }
            return
        }
        guard game.phase == .playing else { return }

        let delta = min(
            0.25,
            max(0, now.timeIntervalSince(game.lastUpdate))
        )
        game.lastUpdate = now
        let speeds = [2.0, 1.5, 1.0, 0.75]
        let pixelsPerSecond = 38.0 / speeds[game.currentSpeed]

        for index in game.activeRows.indices {
            game.activeRows[index].previousY =
                game.activeRows[index].y
            game.activeRows[index].y +=
                pixelsPerSecond * delta
        }

        if game.activeRows.isEmpty,
           game.nextRow < game.rows.count {
            game.activeRows.append(
                UnityDTSpeedRow(
                    index: game.nextRow,
                    y: -6,
                    previousY: -6
                )
            )
            game.nextRow += 1
        } else if let newest = game.activeRows.max(
            by: { $0.index < $1.index }
        ), newest.y >= 16,
           game.nextRow < game.rows.count {
            game.activeRows.append(
                UnityDTSpeedRow(
                    index: game.nextRow,
                    y: -6,
                    previousY: -6
                )
            )
            game.nextRow += 1
        }

        var didCrash = false
        for index in game.activeRows.indices {
            if game.activeRows[index].previousY < 31,
               game.activeRows[index].y >= 31 {
                game.rowsBeaten += 1
                game.roundRowsBeaten += 1
                updateSpeed(&game)
                play("Game/Speed Runner/rocket_asteroid")
            }
            if !game.activeRows[index].collided,
               game.activeRows[index].y >= 20,
               game.activeRows[index].y <= 29 {
                let row = game.rows[
                    game.activeRows[index].index
                ]
                if (row & (1 << game.rocketLane)) != 0 {
                    game.activeRows[index].collided = true
                    didCrash = true
                }
            }
        }
        game.activeRows.removeAll { $0.y > 38 }

        if didCrash {
            game.crashes += 1
            play("Game/Speed Runner/rocket_crash")
            if game.crashes < 3,
               game.nextRow < game.rows.count {
                game.rowsBeaten += 1
                game.activeRows.removeAll()
                game.currentSpeed = 0
                game.roundRowsBeaten = 0
                game.phase = .respawning
                game.phaseStarted = now
            } else {
                game.phase = .gameOver
                game.phaseStarted = now
            }
            return
        }

        if game.nextRow >= game.rows.count,
           game.activeRows.isEmpty {
            game.finishY += pixelsPerSecond * delta
            if game.finishY >= -6,
               game.finishY < -1,
               game.rocketLane != 1 {
                game.phase = .gameOver
                game.phaseStarted = now
                play("Game/Speed Runner/rocket_crash")
            } else if game.finishY >= 0 {
                game.finishY = 0
                game.rowsBeaten += 1
                game.phase = .goal
                game.phaseStarted = now
                play("Game/Speed Runner/rocket_goal")
            }
        }
    }

    private func updateSpeed(
        _ game: inout UnityDTSpeedRunnerGame
    ) {
        if game.roundRowsBeaten >= 6 {
            game.currentSpeed = 3
        } else if game.roundRowsBeaten >= 3 {
            game.currentSpeed = 2
        } else if game.roundRowsBeaten >= 1 {
            game.currentSpeed = 1
        }
    }

    private func speedRunnerScore(
        _ game: UnityDTSpeedRunnerGame
    ) -> Int {
        max(0, (game.rowsBeaten * 6) - (80 * game.crashes))
    }

    private func updateDigiHunter(
        _ game: inout UnityDTDigiHunterGame,
        now: Date
    ) {
        if game.phase == .intro {
            if now.timeIntervalSince(game.phaseStarted) >= 5.65 {
                game.phase = .playing
                game.playStarted = now
                game.nextSpawn = now
            }
            return
        }
        if game.phase == .finishing {
            if now.timeIntervalSince(game.phaseStarted) >= 1.5 {
                game.phase = .end
                game.phaseStarted = now
            }
            return
        }
        guard game.phase == .playing else { return }

        for index in game.faces.indices {
            if game.faces[index].value == -1,
               now >= game.faces[index].explosionUntil {
                game.faces[index].value = 0
            } else if game.faces[index].value > 0,
                      now >= game.faces[index].expiresAt {
                game.faces[index].value = 0
            }
        }

        let elapsed = now.timeIntervalSince(game.playStarted)
        if elapsed >= 60 {
            game.phase = .finishing
            game.phaseStarted = now
            play("Game/Speed Runner/rocket_goal")
            return
        }

        if now >= game.nextSpawn {
            let empty = game.faces.indices.filter {
                game.faces[$0].value == 0
            }
            if let index = empty.randomElement() {
                game.faces[index].value = Int.random(in: 1...2)
                game.faces[index].expiresAt = now.addingTimeInterval(
                    Double.random(in: 1.5...3.0)
                )
            }
            let progress = elapsed / 60.0
            let minimum = 0.75 - (0.5625 * progress)
            let maximum = 1.5 - (1.125 * progress)
            game.nextSpawn = now.addingTimeInterval(
                Double.random(in: minimum...maximum)
            )
        }
    }

    private func updateMaze(
        _ game: inout UnityDTMazeGame,
        now: Date
    ) {
        if game.phase == .defeat,
           now.timeIntervalSince(game.lastSecond) >= 1 {
            game.resultReady = true
            return
        }
        guard game.phase == .playing else { return }
        while now.timeIntervalSince(game.lastSecond) >= 1 {
            game.lastSecond = game.lastSecond.addingTimeInterval(1)
            if game.timeRemaining > 1 {
                game.timeRemaining -= 1
            } else {
                game.timeRemaining = 0
                game.phase = .defeat
                game.resultReady = false
                game.lastSecond = now
                play("button_b")
                break
            }
        }
    }

    private func generateMazePaths() -> [Int] {
        let width = 15
        let height = 12
        let visited = 0b10000
        var cells = [Int](repeating: 0, count: width * height)
        var stack = [(x: 0, y: 0)]
        cells[0] = visited

        while cells.filter({ ($0 & visited) != 0 }).count
                < cells.count {
            guard let current = stack.last else { break }
            var neighbors: [UnityDTMazeDirection] = []
            if current.x > 0,
               (cells[(current.x - 1) + current.y * width]
                    & visited) == 0 {
                neighbors.append(.left)
            }
            if current.x < width - 1,
               (cells[(current.x + 1) + current.y * width]
                    & visited) == 0 {
                neighbors.append(.right)
            }
            if current.y > 0,
               (cells[current.x + (current.y - 1) * width]
                    & visited) == 0 {
                neighbors.append(.up)
            }
            if current.y < height - 1,
               (cells[current.x + (current.y + 1) * width]
                    & visited) == 0 {
                neighbors.append(.down)
            }

            guard let direction = neighbors.randomElement() else {
                stack.removeLast()
                continue
            }
            let currentIndex = current.x + current.y * width
            var next = current
            switch direction {
            case .left:
                cells[currentIndex] |= 0b00010
                next.x -= 1
                cells[next.x + next.y * width] |= 0b01000
            case .right:
                cells[currentIndex] |= 0b01000
                next.x += 1
                cells[next.x + next.y * width] |= 0b00010
            case .up:
                cells[currentIndex] |= 0b00001
                next.y -= 1
                cells[next.x + next.y * width] |= 0b00100
            case .down:
                cells[currentIndex] |= 0b00100
                next.y += 1
                cells[next.x + next.y * width] |= 0b00001
            }
            cells[next.x + next.y * width] |= visited
            stack.append(next)
        }
        return cells
    }

    private func moveMazePlayer(
        _ game: inout UnityDTMazeGame,
        _ direction: UnityDTMazeDirection
    ) -> Bool {
        guard game.phase == .playing else { return false }
        if game.playerX == 14,
           game.playerY == 11,
           direction == .right {
            game.playerX = 15
            game.phase = .victory
            play("button_b")
            return true
        }
        if game.playerX == -1 {
            if direction == .right {
                game.playerX = 0
                return true
            }
            play("button_b")
            return false
        }
        let index = game.playerX + game.playerY * 15
        let bit: Int
        switch direction {
        case .left: bit = 0b00010
        case .right: bit = 0b01000
        case .up: bit = 0b00001
        case .down: bit = 0b00100
        }
        guard game.paths.indices.contains(index),
              (game.paths[index] & bit) == bit else {
            play("button_b")
            return false
        }
        switch direction {
        case .left: game.playerX -= 1
        case .right: game.playerX += 1
        case .up: game.playerY -= 1
        case .down: game.playerY += 1
        }
        return true
    }

    private func submitMiniGameScore(_ score: Int) {
        let before = state.currentDistance
        let reduction = min(
            max(0, state.currentDistance - 1),
            max(0, score)
        )
        state.currentDistance -= reduction
        state.stepsToNextEvent -= Int(
            round(Double(max(0, score)) / 5.0)
        )
        state.steps += Int(
            round(Double(max(0, score)) / 5.0)
        )
        state.banner = "SCORE \(score)"
        // GameManager plays AwardDistance here — the SCORE / DISTANCE
        // tally board — rather than just flashing a banner.
        record(
            .awardDistance(
                score: score,
                before: before,
                after: state.currentDistance
            )
        )
    }

    private func closeMiniGame() {
        miniGame = nil
        state.screen = .app
        state.app = .game
        play("button_b")
    }
}

// MARK: - Energy Wars and Digi-Catch
//
// The original reserved `App.EnergyWars` / `App.DigiCatch` in
// `AppLoader.cs` and drew their reward-menu icons, but never wrote the
// games — there is no script, prefab or sprite set to port. These two
// are built from the pieces the D-Tector already uses so they sit in
// the same visual language as the shipped mini-games.

/// A tug of war between two energy blasts, fought the way
/// `Animations.AttackCollision` looks: tap to push the impact point
/// toward the opponent before the clock runs out.
struct UnityDTEnergyWarsGame {
    enum Phase: Equatable {
        case intro
        case playing
        case won
        case lost
    }

    var phase: Phase = .intro
    var phaseStarted = Date()
    var lastUpdate = Date()
    var friendly: String
    var enemy: String
    /// Impact point in screen pixels; 16 is dead centre.
    var impact: Double = 16
    var secondsLeft: Double = 12
    var lastSecondTick = Date()
}

/// Falling data capsules caught in a pad that slides between three
/// lanes. Three misses ends the run.
struct UnityDTDigiCatchGame {
    enum Phase: Equatable {
        case intro
        case playing
        case won
        case lost
    }

    struct Capsule: Equatable {
        var lane: Int
        var y: Double
        var junk: Bool
    }

    var phase: Phase = .intro
    var phaseStarted = Date()
    var lastUpdate = Date()
    var lane = 1
    var capsules: [Capsule] = []
    var caught = 0
    var missed = 0
    var nextSpawn = Date.distantPast
    var target = 8
}

extension UnityDTGameModel {
    // MARK: Energy Wars

    func startEnergyWars() {
        let friendly = state.ddocks.first(where: { !$0.isEmpty })
            ?? activePartnerName
        let enemy = catalog.randomBattleDigimon(
            playerLevel: playerLevel,
            excluding: [friendly]
        ).name
        miniGame = .energyWars(
            UnityDTEnergyWarsGame(friendly: friendly, enemy: enemy)
        )
        play("Battle/encounter_regular")
    }

    func energyWarsPush(_ game: inout UnityDTEnergyWarsGame) {
        guard game.phase == .playing else { return }
        // Each tap shoves the impact toward the enemy; it drifts back on
        // its own, so it has to be kept up.
        game.impact = max(0, game.impact - 1.15)
        play("launch_attack")
        if game.impact <= 1 {
            game.phase = .won
            game.phaseStarted = Date()
            finishEnergyWars(won: true)
        }
    }

    func updateEnergyWars(
        _ game: inout UnityDTEnergyWarsGame,
        now: Date
    ) {
        let delta = now.timeIntervalSince(game.lastUpdate)
        guard delta >= 0.05 else { return }
        game.lastUpdate = now

        switch game.phase {
        case .intro:
            if now.timeIntervalSince(game.phaseStarted) >= 2.0 {
                game.phase = .playing
                game.phaseStarted = now
                game.lastSecondTick = now
            }

        case .playing:
            // The enemy pushes back steadily.
            game.impact = min(31, game.impact + delta * 2.6)
            if now.timeIntervalSince(game.lastSecondTick) >= 1.0 {
                game.lastSecondTick = now
                game.secondsLeft -= 1
            }
            if game.impact >= 30 || game.secondsLeft <= 0 {
                game.phase = .lost
                game.phaseStarted = now
                finishEnergyWars(won: false)
            }

        case .won, .lost:
            if now.timeIntervalSince(game.phaseStarted) >= 2.5 {
                miniGame = nil
            }
        }
    }

    private func finishEnergyWars(won: Bool) {
        if won {
            let before = state.currentDistance
            state.currentDistance = max(1, state.currentDistance - 300)
            record(.changeDistance(before: before, after: state.currentDistance))
            record(.charHappy)
        } else {
            record(.charSad)
        }
        save()
    }

    // MARK: Digi-Catch

    func startDigiCatch() {
        miniGame = .digiCatch(UnityDTDigiCatchGame())
        play("button_a")
    }

    func digiCatchMove(_ game: inout UnityDTDigiCatchGame, delta: Int) {
        guard game.phase == .playing else { return }
        game.lane = min(2, max(0, game.lane + delta))
        play("button_a")
    }

    func updateDigiCatch(
        _ game: inout UnityDTDigiCatchGame,
        now: Date
    ) {
        let delta = now.timeIntervalSince(game.lastUpdate)
        guard delta >= 0.05 else { return }
        game.lastUpdate = now

        switch game.phase {
        case .intro:
            if now.timeIntervalSince(game.phaseStarted) >= 1.5 {
                game.phase = .playing
                game.phaseStarted = now
                game.nextSpawn = now
            }

        case .playing:
            if now >= game.nextSpawn {
                game.capsules.append(
                    .init(
                        lane: Int.random(in: 0..<3),
                        y: -6,
                        // Some capsules are corrupted and cost a life.
                        junk: Int.random(in: 0..<5) == 0
                    )
                )
                game.nextSpawn = now.addingTimeInterval(
                    Double.random(in: 0.7...1.2)
                )
            }

            let padTop = 24.0
            var survivors: [UnityDTDigiCatchGame.Capsule] = []
            for var capsule in game.capsules {
                capsule.y += delta * 13
                if capsule.y >= padTop {
                    if capsule.lane == game.lane {
                        if capsule.junk {
                            game.missed += 1
                            play("button_b")
                        } else {
                            game.caught += 1
                            play("reward")
                        }
                    } else if !capsule.junk {
                        game.missed += 1
                        play("button_b")
                    }
                } else {
                    survivors.append(capsule)
                }
            }
            game.capsules = survivors

            if game.caught >= game.target {
                game.phase = .won
                game.phaseStarted = now
                finishDigiCatch(won: true)
            } else if game.missed >= 3 {
                game.phase = .lost
                game.phaseStarted = now
                finishDigiCatch(won: false)
            }

        case .won, .lost:
            if now.timeIntervalSince(game.phaseStarted) >= 2.5 {
                miniGame = nil
            }
        }
    }

    private func finishDigiCatch(won: Bool) {
        if won {
            let before = state.spiritPower
            state.spiritPower = min(99, state.spiritPower + 15)
            record(
                .awardSpiritPower(before: before, after: state.spiritPower)
            )
            record(.charHappy)
        } else {
            record(.charSad)
        }
        save()
    }
}

// MARK: - Fusion Lab
//
// Original work — a browser, not a port. Two things the game already
// knows but never shows: where a digimon sits in its evolution line,
// and exactly which spirits are still missing for each fusion. Tapping
// through EVOLVE walks a chain a step at a time and plays the game's own
// RegularEvolution cutscene on the way.

extension UnityDTGameModel {
    func isUnlockedName(_ name: String) -> Bool {
        (state.unlocked[name] ?? 0) > 0
    }

    /// Every digimon that is part of an evolution line, in game order.
    var evolveBrowseList: [UnityDTDigimon] {
        catalog.digimon.filter { digimon in
            guard !digimon.isPseudo else { return false }
            if digimon.evolution?.isEmpty == false { return true }
            return catalog.digimon.contains { other in
                other.evolution == digimon.name
                    || (other.extraEvolutions ?? [])
                        .contains(digimon.name)
            }
        }
    }

    /// The straight line a digimon sits on: walk back to the root by the
    /// primary evolution, then forward again. `extraEvolutions` branches
    /// are deliberately left out — this is the spine, not the whole
    /// tree. The visited sets guard the handful that evolve in a loop.
    func evolveChain(for digimon: UnityDTDigimon) -> [String] {
        var root = digimon
        var seen: Set<String> = [digimon.name]
        while let previous = catalog.digimon.first(
            where: { $0.evolution == root.name }
        ), !seen.contains(previous.name), seen.count < 8 {
            seen.insert(previous.name)
            root = previous
        }

        var chain = [root.name]
        var cursor = root
        while let next = cursor.evolution,
              !next.isEmpty,
              !chain.contains(next),
              chain.count < 8,
              let entry = catalog.digimonByName[next] {
            chain.append(next)
            cursor = entry
        }
        return chain
    }

    /// Fusion targets in the order the app pages through them: the three
    /// true Fusion forms first, then the ten Hybrids.
    var fusionTargets: [UnityDTDigimon] {
        let fusion = catalog.digimon
            .filter { $0.stage == 6 && $0.spiritType == 4 }
            .sorted { $0.order < $1.order }
        let hybrid = catalog.digimon
            .filter { $0.stage == 6 && $0.spiritType == 2 }
            .sorted { $0.element < $1.element }
        return fusion + hybrid
    }

    /// What `GameManager.HasAllSpiritsForFusion` / `HasBothFormsOfSpirit`
    /// check, spelled out as the list of spirits needed.
    func fusionRequirements(for digimon: UnityDTDigimon) -> [String] {
        // Element ints: 0 fire, 1 light, 2 thunder, 3 wind, 4 ice,
        // 5 dark, 6 earth, 7 wood, 8 metal, 9 water.
        let elements: [Int]
        switch digimon.name {
        case "kaisergreymon":
            elements = [0, 3, 4, 6, 7]
        case "magnagarurumon":
            elements = [1, 2, 5, 8, 9]
        case "susanoomon":
            elements = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        default:
            // A Hybrid needs the Human and Animal of its own element.
            elements = [digimon.element]
        }
        return catalog.digimon
            .filter {
                $0.stage == 6
                    && ($0.spiritType == 0 || $0.spiritType == 1)
                    && elements.contains($0.element)
            }
            .sorted {
                $0.element == $1.element
                    ? $0.spiritType < $1.spiritType
                    : $0.element < $1.element
            }
            .map(\.name)
    }

    func fusionIsReady(_ digimon: UnityDTDigimon) -> Bool {
        let required = fusionRequirements(for: digimon)
        return !required.isEmpty
            && required.allSatisfy(isUnlockedName)
    }

    // MARK: EVOLVE app

    /// Opens on whatever is in the first d-dock, if it has a line.
    func openEvolveApp() {
        let list = evolveBrowseList
        if let partner = state.ddocks.first(where: { !$0.isEmpty }),
           let index = list.firstIndex(where: { $0.name == partner }) {
            evolveIndex = index
        } else if evolveIndex >= list.count {
            evolveIndex = 0
        }
    }

    func evolveBrowse(_ delta: Int) {
        let count = max(1, evolveBrowseList.count)
        evolveIndex = ((evolveIndex + delta) % count + count) % count
        play("button_a")
    }

    func evolveConfirm() {
        let list = evolveBrowseList
        guard let current = list[safe: evolveIndex],
              let next = current.evolution,
              !next.isEmpty,
              let index = list.firstIndex(where: { $0.name == next })
        else {
            play("button_b")
            return
        }
        // Play the game's own evolution cutscene on the way up.
        record(.previewEvolution(before: current.name, after: next))
        evolveIndex = index
    }

    // MARK: FUSION app

    func openFusionApp() {
        if fusionIndex >= fusionTargets.count { fusionIndex = 0 }
        fusionPage = 0
    }

    func fusionBrowse(_ delta: Int) {
        let targets = fusionTargets
        guard let target = targets[safe: fusionIndex] else { return }
        if fusionPage == 0 {
            let count = max(1, targets.count)
            fusionIndex = ((fusionIndex + delta) % count + count) % count
        } else {
            let count = max(1, fusionRequirements(for: target).count)
            let page = fusionPage - 1
            fusionPage = ((page + delta) % count + count) % count + 1
        }
        play("button_a")
    }

    /// On the overview: fuse if every spirit is in hand, otherwise open
    /// the checklist so the missing ones are visible. On the checklist:
    /// page back out to the overview.
    func fusionConfirm() {
        let targets = fusionTargets
        guard let target = targets[safe: fusionIndex] else { return }
        guard fusionPage == 0 else {
            fusionPage = 0
            play("button_b")
            return
        }
        guard fusionIsReady(target) else {
            fusionPage = 1
            play("button_b")
            return
        }
        if !isUnlockedName(target.name) {
            state.unlocked[target.name] = 1
        }
        record(.previewTransform(digimon: target.name))
        state.banner = target.displayName
        save()
    }
}

// MARK: - Pipe Monsters
//
// Version 4's exclusive game. Nothing of it exists in the Unity project
// — no script, no prefab, no enum slot, not even a menu icon — so this
// is original work in the same vein as Energy Wars and Digi-Catch, not a
// port. It sits on a fourth reward-menu entry the original never had,
// which leaves every shipped menu index exactly where it was.
//
// Four pipes; monsters climb out of them and dive back. It is a
// whack-a-mole, but the beat is timing rather than the grid hunting that
// DigiHunter already does: a monster is only worth full marks at full
// height, letting one dive back costs a life, and a swing at an empty
// pipe leaves the hammer stuck for a moment so the pipes cannot simply
// be mashed.

struct UnityDTPipeMonstersGame {
    enum Phase: Equatable {
        case intro
        case playing
        case over
    }

    struct Pipe: Equatable {
        enum Occupant: Equatable {
            case empty
            case rising
            case out
            case sinking
            case smashed
        }

        var occupant: Occupant = .empty
        var changed = Date.distantPast
        /// How long this one waits at full height before diving back.
        var hold: Double = 0.75
    }

    /// Three pipes at a pitch of 10 leaves two clear columns between
    /// neighbours; at four the 8x8 monsters touch and read as one blob.
    static let laneCount = 3
    static let riseTime = 0.32
    static let lives = 3

    var phase: Phase = .intro
    var phaseStarted = Date()
    var lastUpdate = Date()
    var pipes = [Pipe](
        repeating: Pipe(),
        count: UnityDTPipeMonstersGame.laneCount
    )
    var lane = 1
    var score = 0
    var escaped = 0
    var nextSpawn = Date.distantPast
    /// A whiffed swing leaves the hammer down until this moment.
    var stuckUntil = Date.distantPast
    var swingUntil = Date.distantPast

    /// 0 while hidden, 1 at full height.
    func emergence(_ pipe: Pipe, at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(pipe.changed)
        switch pipe.occupant {
        case .empty:
            return 0
        case .rising:
            return min(1, elapsed / Self.riseTime)
        case .out, .smashed:
            return 1
        case .sinking:
            return max(0, 1 - elapsed / Self.riseTime)
        }
    }

    var livesLeft: Int { max(0, Self.lives - escaped) }
}

extension UnityDTGameModel {
    func startPipeMonsters() {
        miniGame = .pipeMonsters(UnityDTPipeMonstersGame())
        play("Game/DigiHunter/digihunter_start")
    }

    func pipeMonstersMove(
        _ game: inout UnityDTPipeMonstersGame,
        delta: Int
    ) {
        guard game.phase == .playing else { return }
        let count = UnityDTPipeMonstersGame.laneCount
        game.lane = ((game.lane + delta) % count + count) % count
        play("button_a")
    }

    func pipeMonstersSmash(_ game: inout UnityDTPipeMonstersGame) {
        let now = Date()
        switch game.phase {
        case .intro:
            game.phase = .playing
            game.phaseStarted = now
            game.nextSpawn = now.addingTimeInterval(0.4)

        case .over:
            submitMiniGameScore(max(0, game.score * 15))
            closeMiniGame()

        case .playing:
            guard now >= game.stuckUntil else { return }
            game.swingUntil = now.addingTimeInterval(0.12)
            var pipe = game.pipes[game.lane]
            switch pipe.occupant {
            case .out:
                game.score += 2
                pipe.occupant = .smashed
                pipe.changed = now
                game.pipes[game.lane] = pipe
                play("Game/Speed Runner/rocket_asteroid")
            case .rising, .sinking:
                // Clipped on the way up or down: still a hit, half the
                // points.
                game.score += 1
                pipe.occupant = .smashed
                pipe.changed = now
                game.pipes[game.lane] = pipe
                play("Game/Speed Runner/rocket_asteroid")
            case .empty, .smashed:
                game.stuckUntil = now.addingTimeInterval(0.45)
                play("button_b")
            }
        }
    }

    func updatePipeMonsters(
        _ game: inout UnityDTPipeMonstersGame,
        now: Date
    ) {
        guard now.timeIntervalSince(game.lastUpdate) >= 0.05 else {
            return
        }
        game.lastUpdate = now

        switch game.phase {
        case .intro:
            if now.timeIntervalSince(game.phaseStarted) >= 2.4 {
                game.phase = .playing
                game.phaseStarted = now
                game.nextSpawn = now.addingTimeInterval(0.4)
            }

        case .playing:
            for index in game.pipes.indices {
                var pipe = game.pipes[index]
                let elapsed = now.timeIntervalSince(pipe.changed)
                switch pipe.occupant {
                case .rising:
                    if elapsed >= UnityDTPipeMonstersGame.riseTime {
                        pipe.occupant = .out
                        pipe.changed = now
                    }
                case .out:
                    if elapsed >= pipe.hold {
                        pipe.occupant = .sinking
                        pipe.changed = now
                    }
                case .sinking:
                    if elapsed >= UnityDTPipeMonstersGame.riseTime {
                        pipe.occupant = .empty
                        pipe.changed = now
                        game.escaped += 1
                        play("Game/Speed Runner/rocket_crash")
                    }
                case .smashed:
                    if elapsed >= 0.3 {
                        pipe.occupant = .empty
                        pipe.changed = now
                    }
                case .empty:
                    break
                }
                game.pipes[index] = pipe
            }

            if game.escaped >= UnityDTPipeMonstersGame.lives {
                game.phase = .over
                game.phaseStarted = now
                finishPipeMonsters(score: game.score)
                return
            }

            if now >= game.nextSpawn {
                let free = game.pipes.indices.filter {
                    game.pipes[$0].occupant == .empty
                }
                if let lane = free.randomElement() {
                    // Both the gap between monsters and the time they
                    // stay out tighten as the run goes on.
                    let pace = min(1.0, Double(game.score) / 30.0)
                    game.pipes[lane].occupant = .rising
                    game.pipes[lane].changed = now
                    game.pipes[lane].hold = Double.random(
                        in: (0.85 - 0.45 * pace)...(1.30 - 0.60 * pace)
                    )
                    game.nextSpawn = now.addingTimeInterval(
                        Double.random(
                            in: (0.85 - 0.45 * pace)...(1.35 - 0.70 * pace)
                        )
                    )
                }
            }

        case .over:
            if now.timeIntervalSince(game.phaseStarted) >= 3.0 {
                submitMiniGameScore(max(0, game.score * 15))
                closeMiniGame()
            }
        }
    }

    private func finishPipeMonsters(score: Int) {
        if score > 0 {
            record(.charHappy)
        } else {
            record(.charSad)
        }
        save()
    }
}


// MARK: - Training
//
// Original work: a sparring ground for the battle system. Pick one of
// the three attacks, the partner picks one back, and the real
// `ChooseWinner` rules decide it — energy beats ability, crush beats
// energy, ability beats crush, and a mirror match is settled on damage
// (or on energy rank when both fire energy). The turn plays through the
// game's own DisplayTurn cutscene, so this doubles as a way to exercise
// every attack pairing without hunting for a real battle.

struct UnityDTTrainingGame {
    enum Phase: Equatable {
        case pickFriendly
        case pickEnemy
        case fight
    }

    var phase: Phase = .pickFriendly
    var friendlyIndex = 0
    var enemyIndex = 0
    var attackIndex = 0
    var friendly = ""
    var enemy = ""
    var friendlyStats = UnityDTMutableStats(
        UnityDTStats(HP: 1, EN: 1, CR: 1, AB: 1)
    )
    var enemyStats = UnityDTMutableStats(
        UnityDTStats(HP: 1, EN: 1, CR: 1, AB: 1)
    )
    var playerHP = 1
    var playerMaxHP = 1
    var enemyHP = 1
    var enemyMaxHP = 1
    var rounds = 0
    var wins = 0
}

extension UnityDTGameModel {
    /// Everything that can spar. Spirit-stage forms come first —
    /// Fusion, then Hybrid, Ancient, Human, Animal, Child — because the
    /// roster is nearly 600 long and stepping through it one at a time
    /// left the headline forms effectively unreachable. Everything else
    /// follows in game order.
    var trainingRoster: [UnityDTDigimon] {
        let all = catalog.digimon.filter { !$0.isPseudo }
        let spiritOrder = [4, 2, 3, 0, 1, 5]
        let spirits = all
            .filter { $0.stage == 6 }
            .sorted {
                let a = spiritOrder.firstIndex(of: $0.spiritType) ?? 9
                let b = spiritOrder.firstIndex(of: $1.spiritType) ?? 9
                return a == b ? $0.order < $1.order : a < b
            }
        return spirits + all.filter { $0.stage != 6 }
    }

    func startTraining() {
        var game = UnityDTTrainingGame()
        // Opens on the roster head, which is KaiserGreymon — the whole
        // spirit line, fusions included, is a tap or two either way.
        game.friendlyIndex = 0
        game.enemyIndex = trainingRoster.count > 1 ? 1 : 0
        miniGame = .training(game)
        play("button_a")
    }

    /// Locks in the two fighters and rolls their stats.
    private func trainingBeginFight(_ game: inout UnityDTTrainingGame) {
        let roster = trainingRoster
        guard let friendly = roster[safe: game.friendlyIndex],
              let enemy = roster[safe: game.enemyIndex] else {
            return
        }
        let fStats = UnityDTMutableStats(friendly.stats)
        let eStats = UnityDTMutableStats(enemy.stats)
        game.friendly = friendly.name
        game.enemy = enemy.name
        game.friendlyStats = fStats
        game.enemyStats = eStats
        game.playerHP = fStats.HP
        game.playerMaxHP = fStats.maxHP
        game.enemyHP = eStats.HP
        game.enemyMaxHP = eStats.maxHP
        game.rounds = 0
        game.wins = 0
        game.attackIndex = 0
        game.phase = .fight
    }

    /// A on a picker advances to the next one; a long press steps back
    /// out, and only closes the app from the first picker.
    func trainingConfirm(_ game: inout UnityDTTrainingGame) {
        switch game.phase {
        case .pickFriendly:
            game.phase = .pickEnemy
            play("button_a")
        case .pickEnemy:
            trainingBeginFight(&game)
            play("button_a")
        case .fight:
            trainingFire(&game)
        }
    }

    func trainingBack(_ game: inout UnityDTTrainingGame) -> Bool {
        switch game.phase {
        case .pickFriendly:
            return true
        case .pickEnemy:
            game.phase = .pickFriendly
        case .fight:
            game.phase = .pickEnemy
        }
        play("button_b")
        return false
    }

    func trainingMove(_ game: inout UnityDTTrainingGame, delta: Int) {
        let count = max(1, trainingRoster.count)
        func step(_ value: Int, _ limit: Int) -> Int {
            ((value + delta) % limit + limit) % limit
        }
        switch game.phase {
        case .pickFriendly:
            game.friendlyIndex = step(game.friendlyIndex, count)
        case .pickEnemy:
            game.enemyIndex = step(game.enemyIndex, count)
        case .fight:
            game.attackIndex = step(game.attackIndex, 3)
        }
        play("button_a")
    }

    /// One sparring round: both sides commit an attack, the real rules
    /// pick the winner, and the turn is handed to the cutscene queue.
    func trainingFire(_ game: inout UnityDTTrainingGame) {
        let friendlyAttack = game.attackIndex
        let enemyAttack = Int.random(in: 0..<3)
        let outcome = chooseWinner(
            friendlyAttack: friendlyAttack,
            enemyAttack: enemyAttack,
            friendlyStats: game.friendlyStats,
            enemyStats: game.enemyStats
        )

        let playerBefore = game.playerHP
        let enemyBefore = game.enemyHP
        if outcome.winner == 0 {
            game.enemyHP = max(0, game.enemyHP - outcome.damage)
            game.wins += 1
        } else if outcome.winner == 1 {
            game.playerHP = max(0, game.playerHP - outcome.damage)
        }
        game.rounds += 1
        // A win banks points, a loss takes some back, a tie is worth a
        // little. Held at or above zero — a negative reads badly on a
        // 1-bit panel.
        let banked = state.trainingScore ?? 0
        if outcome.winner == 0 {
            state.trainingScore = banked + 10
        } else if outcome.winner == 1 {
            state.trainingScore = max(0, banked - 5)
        } else {
            state.trainingScore = banked + 2
        }
        save()

        record(
            .previewBattleTurn(
                friendly: game.friendly,
                enemy: game.enemy,
                friendlyAttack: friendlyAttack,
                enemyAttack: enemyAttack,
                playerHPBefore: playerBefore,
                playerHPAfter: game.playerHP,
                enemyHPBefore: enemyBefore,
                enemyHPAfter: game.enemyHP
            )
        )

        // Training never costs anything: a downed sparring partner is
        // replaced, and the trainee is patched up rather than punished.
        if game.enemyHP <= 0 {
            let next = catalog.randomBattleDigimon(
                playerLevel: playerLevel,
                excluding: [game.friendly]
            )
            let stats = UnityDTMutableStats(next.stats)
            game.enemy = next.name
            game.enemyStats = stats
            game.enemyHP = stats.HP
            game.enemyMaxHP = stats.maxHP
            // Queued after the turn, so the round plays out and then the
            // next partner is introduced with the game's own encounter
            // cutscene — name hold and all.
            record(.previewEncounter(enemy: next.name))
        }
        if game.playerHP <= 0 {
            game.playerHP = game.playerMaxHP
        }
    }
}
