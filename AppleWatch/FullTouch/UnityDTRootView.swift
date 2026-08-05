import SwiftUI
import UIKit

struct UnityDTRootView: View {
    @EnvironmentObject private var game: UnityDTGameModel
    @StateObject private var motion = UnityWatchMotionBridge()
    @State private var presentation: UnityDTPresentation?
    @State private var pendingPresentations:
        [(kind: UnityDTPresentation.Kind, duration: TimeInterval)] = []
    @State private var presentationProgress = 0.0
    @State private var presentationTask: Task<Void, Never>?
    @State private var didQueueInitialPresentation = false
    @State private var walkingUntil: Date?
    @State private var lastHomeWalkAt = Date()
    @State private var characterSpriteFrame = 0
    @State private var characterUsedAltSprite = false
    @State private var characterLastIdleFrame = 0
    @State private var characterAnimationTask: Task<Void, Never>?
    @State private var heldTouchInput: TouchInput?
    @State private var touchLongPressTask: Task<Void, Never>?
    @State private var didTriggerLongBack = false
    @State private var tripleTapCount = 0
    @State private var lastTapAt: Date?
    @State private var presentationAudioTask: Task<Void, Never>?
    @State private var walkingProgress = 1.0
    @State private var walkingLeadFrame = 0
    @State private var homeCutsceneActive = false
    /// Camera parked on the enemy after the pan, waiting on the player.
    @State private var homeStandoff = false
    @State private var homeCutsceneStartFrame = 0
    @State private var homeCutsceneTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                UnityDTLCD {
                    stage
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

                touchSurface

                if let presentation {
                    UnityDTLCD {
                        UnityDTAnimationStage(
                            presentation: presentation,
                            progress: presentationProgress
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
                    .transition(.opacity)
                    .zIndex(2)
                }

            }
            .ignoresSafeArea()
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains(
                    "--qa-walking"
                ) {
                    walkingUntil = Date().addingTimeInterval(60)
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 4.0
                    ) {
                        triggerWalkingAnimation()
                    }
                }
                scheduleQAInputsIfNeeded()
                // `--qa-encounter` seeds pendingEnemy before this view
                // ever mounts, so the nil -> value onChange never fires.
                if game.state.screen == .character,
                   game.state.pendingEnemy != nil {
                    startHomeEncounterCutscene()
                }
                    motion.start {
                        guard presentation == nil else { return }
                        game.takeStep(source: "shake")
                        lastHomeWalkAt = Date()
                        walkingUntil = Date().addingTimeInterval(2.5)
                        triggerWalkingAnimation()
                    }
                startCharacterAnimation()
                if ProcessInfo.processInfo.arguments.contains(
                    "--qa-opening"
                ) {
                    queueOpeningPresentationForQA()
                } else if ProcessInfo.processInfo.arguments.contains(
                    "--qa-cutscene"
                ) {
                    queueCutscenePresentationForQA()
                } else {
                    queueInitialPresentationIfNeeded()
                }
            }
            // Events recorded off the back of a tick rather than an
            // input — a jackpot that ran out of clock, a mini-game that
            // finished on its own — still need queueing.
            .onChange(of: game.recordedEventTick) { _ in
                guard !ProcessInfo.processInfo.arguments.contains(
                    "--qa-cutscene"
                ) else { return }
                enqueueRecordedEvents()
            }
            .onChange(of: game.state.pendingEnemy) { newValue in
                guard newValue != nil else {
                    // Consumed by the battle that just started.
                    homeCutsceneTask?.cancel()
                    homeCutsceneTask = nil
                    homeCutsceneActive = false
                    homeStandoff = false
                    return
                }
                guard game.state.screen == .character,
                      presentation == nil else { return }
                startHomeEncounterCutscene()
            }
            .onDisappear {
                motion.stop()
                characterAnimationTask?.cancel()
                characterAnimationTask = nil
                touchLongPressTask?.cancel()
                touchLongPressTask = nil
                presentationAudioTask?.cancel()
                presentationAudioTask = nil
                presentationTask?.cancel()
                presentationTask = nil
                homeCutsceneTask?.cancel()
                homeCutsceneTask = nil
                game.save()
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch game.state.screen {
        case .charSelection:
            characterSelect
        case .character:
            characterHome
        case .mainMenu:
            mainMenu
        case .app:
            appScreen
        case .battle:
            battleScreen
        case .result:
            resultScreen
        }
    }

    private var touchSurface: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard heldTouchInput == nil,
                              presentation == nil,
                              !homeCutsceneActive else {
                            return
                        }
                        beginTouch(
                            input: touchInput(
                                at: value.startLocation,
                                in: proxy.size
                            )
                        )
                    }
                    .onEnded { _ in
                        endTouch()
                    }
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(presentation == nil && !homeCutsceneActive)
        }
    }

    private func touchInput(
        at location: CGPoint,
        in size: CGSize
    ) -> TouchInput {
        let third = size.width / 3
        if location.x < third {
            return .left
        }
        if location.x > third * 2 {
            return .right
        }
        if game.miniGameNeedsDownInput,
           location.y > size.height / 2 {
            return .down
        }
        return .center
    }

    private func beginTouch(input: TouchInput) {
        heldTouchInput = input
        didTriggerLongBack = false
        setHeldMiniGameInput(input, pressed: true)
        touchLongPressTask?.cancel()

        // Mini-games that are played by holding cannot also use a hold
        // for back — the press would quit instead of playing. On those
        // screens back is three quick taps instead.
        guard !game.miniGameUsesHoldControls else { return }

        touchLongPressTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: 480_000_000
            )
            guard !Task.isCancelled,
                  heldTouchInput != nil,
                  presentation == nil,
                  !homeCutsceneActive else {
                return
            }
            didTriggerLongBack = true
            game.miniGameReleaseHold()
            game.longBack()
        }
    }

    /// Counts quick taps while a hold-controlled mini-game is on screen
    /// and backs out on the third one.
    private func registerTripleTapBack() -> Bool {
        let now = Date()
        if let last = lastTapAt, now.timeIntervalSince(last) > 0.6 {
            tripleTapCount = 0
        }
        lastTapAt = now
        tripleTapCount += 1
        guard tripleTapCount >= 3 else { return false }
        tripleTapCount = 0
        lastTapAt = nil
        game.miniGameReleaseHold()
        game.longBack()
        return true
    }

    private func endTouch() {
        touchLongPressTask?.cancel()
        touchLongPressTask = nil
        guard let input = heldTouchInput else { return }
        heldTouchInput = nil
        game.miniGameReleaseHold()

        if didTriggerLongBack {
            didTriggerLongBack = false
            return
        }
        if game.miniGameUsesHoldControls {
            // The hold itself was the move; three quick taps back out.
            _ = registerTripleTapBack()
            return
        }
        tripleTapCount = 0
        performInput(input)
    }

    private func setHeldMiniGameInput(
        _ input: TouchInput,
        pressed: Bool
    ) {
        guard pressed else {
            game.miniGameReleaseHold()
            return
        }
        switch input {
        case .left:
            game.miniGameHold(direction: -1)
        case .right:
            game.miniGameHold(direction: 1)
        default:
            game.miniGameHold(direction: 0)
        }
    }

    private enum TouchInput {
        case left
        case center
        case down
        case right
    }

    private func performInput(_ input: TouchInput) {
        guard presentation == nil, !homeCutsceneActive else { return }
        let oldScreen = game.state.screen
        let oldBattle = game.state.battle
        let oldApp = game.state.app
        let oldSavedEvent = game.state.savedEvent
        let oldWorld = game.state.currentWorld
        let oldArea = game.state.currentArea
        let oldMap = game.state.mapDisplayMap
        let oldMapScreen = game.state.mapScreen
        let oldDatabaseScreen = game.state.databaseScreen
        let oldDDocks = game.state.ddocks
        let oldUnlocked = game.state.unlocked
        let oldCode = game.state.digitsCode
        let oldCodeStatus = game.state.codeStatus
        let selectedCharacter = game.state.charIndex

        switch input {
        case .left:
            game.left()
        case .center:
            game.centerTap()
            // Staying on the character screen with nothing pending means
            // the tap was a step. This must not test `oldBattle`: the
            // finished battle is kept around so its last turn can still
            // animate, so that check silently stopped walking for good
            // after the player's first fight.
            if oldScreen == .character,
               game.state.screen == .character,
               game.state.savedEvent == 0 {
                lastHomeWalkAt = Date()
                walkingUntil = Date().addingTimeInterval(2.5)
                triggerWalkingAnimation()
            }
        case .down:
            game.miniGameDown()
        case .right:
            game.right()
        }

        if oldScreen == .charSelection,
           game.state.screen == .character {
            enqueuePresentation(
                .gameStart(
                    character: selectedCharacter,
                    spirit: game.catalog.playerSpiritName(
                        for: selectedCharacter
                    ),
                    initial: game.state.ddocks.first(where: {
                        !$0.isEmpty
                    }) ?? "agumon"
                ),
                duration: 52.78125
            )
            return
        }

        enqueueRecordedEvents(leading: true)
        presentTransition(
            from: oldScreen,
            oldBattle: oldBattle,
            oldApp: oldApp,
            oldSavedEvent: oldSavedEvent,
            oldWorld: oldWorld,
            oldArea: oldArea,
            oldMap: oldMap,
            oldMapScreen: oldMapScreen,
            oldDatabaseScreen: oldDatabaseScreen,
            oldDDocks: oldDDocks,
            oldUnlocked: oldUnlocked,
            oldCode: oldCode,
            oldCodeStatus: oldCodeStatus
        )
        enqueueRecordedEvents()
    }

    /// Turns everything the model recorded during this input into queued
    /// cutscenes, in the order the original enqueues them.
    private func enqueueRecordedEvents(leading: Bool = false) {
        for event in game.drainEvents(leading: leading) {
            let kind: UnityDTPresentation.Kind
            switch event {
            case .spendCallPoints(let before, let after):
                kind = .spendCallPoints(before: before, after: after)
            case .awardSpiritPower(let before, let after):
                kind = .spiritPower(
                    before: before,
                    after: after,
                    spending: false
                )
            case .paySpiritPower(let before, let after):
                kind = .spiritPower(
                    before: before,
                    after: after,
                    spending: true
                )
            case .levelUp(let before, let after):
                kind = .levelUp(before: before, after: after)
            case .levelDown(let before, let after):
                kind = .levelDown(before: before, after: after)
            case .levelUpDigimon(let name):
                kind = .levelUpDigimon(digimon: name)
            case .levelDownDigimon(let name):
                kind = .levelDownDigimon(digimon: name)
            case .eraseDigimon(let name):
                kind = .eraseDigimon(digimon: name)
            case .unlockDigimon(let name, let spiritForm):
                kind = .unlockDigimon(
                    digimon: name,
                    spiritForm: spiritForm
                )
            case .receiveSpirit(let name):
                kind = .receiveSpirit(digimon: name)
            case .loseSpirit(let spirit, let enemy):
                kind = .loseSpirit(spirit: spirit, enemy: enemy)
            case .changeDistance(let before, let after):
                kind = .changeDistance(before: before, after: after)
            case .charHappy:
                kind = .charMood(
                    character: game.state.playerChar ?? 0,
                    happy: true
                )
            case .charSad:
                kind = .charMood(
                    character: game.state.playerChar ?? 0,
                    happy: false
                )
            case .enemyEscapes(let enemy, let friendly):
                kind = .enemyEscapes(enemy: enemy, friendly: friendly)
            case .deportSpirit(let name):
                kind = .deportSpirit(
                    digimon: name,
                    character: game.state.playerChar ?? 0
                )
            case .deportDigimon(let name):
                kind = .deport(digimon: name)
            case .awardDistance(let score, let before, let after):
                kind = .awardDistance(
                    score: score,
                    before: before,
                    after: after
                )
            case .forcedTravel(
                let world,
                let areaBefore,
                let areaAfter,
                let distance
            ):
                kind = .forcedTravel(
                    world: world,
                    areaBefore: areaBefore,
                    areaAfter: areaAfter,
                    distance: distance
                )
            case .displayNewArea(let world, let area, let distance):
                kind = .displayNewArea(
                    world: world,
                    area: area,
                    distance: distance
                )
            case .destroyBox:
                kind = .destroyBox
            case .boxResists(let friendly):
                kind = .boxResists(friendly: friendly)
            case .rewardEmpty:
                kind = .rewardEmpty
            case .rewardDistance(let punishment, let before, let after):
                kind = .rewardDistance(
                    punishment: punishment,
                    before: before,
                    after: after
                )
            case .rewardSpiritPower(
                let punishment,
                let before,
                let after
            ):
                kind = .rewardSpiritPower(
                    punishment: punishment,
                    before: before,
                    after: after
                )
            case .rewardCode(let digimon, let code):
                kind = .rewardCode(digimon: digimon, code: code)
            case .previewEvolution(let before, let after):
                kind = .regularEvolution(before: before, after: after)
            case .previewBattleTurn(
                let friendly,
                let enemy,
                let friendlyAttack,
                let enemyAttack,
                let playerHPBefore,
                let playerHPAfter,
                let enemyHPBefore,
                let enemyHPAfter
            ):
                kind = .battleTurn(
                    friendly: friendly,
                    enemy: enemy,
                    friendlyAttack: friendlyAttack,
                    enemyAttack: enemyAttack,
                    playerHPBefore: playerHPBefore,
                    playerHPAfter: playerHPAfter,
                    enemyHPBefore: enemyHPBefore,
                    enemyHPAfter: enemyHPAfter,
                    unlocked: nil,
                    character: game.state.playerChar ?? 0
                )
            case .previewEncounter(let enemy):
                kind = .encounter(enemy: enemy, boss: false)
            case .previewTransform(let name):
                // Battle.cs picks the scene by spirit type; the FUSION
                // browser reuses exactly that mapping.
                let character = game.state.playerChar ?? 0
                let entry = game.catalog.digimonByName[name]
                if name == "susanoomon" {
                    kind = .susanoomonEvolution(character: character)
                } else if entry?.spiritType == 4 {
                    kind = .fusionEvolution(
                        character: character,
                        digimon: name
                    )
                } else {
                    kind = .spiritEvolution(
                        character: character,
                        digimon: name
                    )
                }
            case .dataStorm(let moved):
                let escapeTicks = Int.random(in: 0..<40)
                enqueuePresentation(
                    .dataStorm(
                        character: game.state.playerChar ?? 0,
                        moved: moved,
                        escapeTicks: escapeTicks
                    ),
                    duration: (moved ? 16.9 : 14.65)
                        + (Double(escapeTicks) * 0.1)
                )
                continue
            }
            enqueuePresentation(
                kind,
                duration: UnityDTPresentation.length(of: kind)
            )
        }
    }

    private func presentTransition(
        from oldScreen: UnityDTScreen,
        oldBattle: UnityDTBattleState?,
        oldApp: UnityDTApp?,
        oldSavedEvent: Int,
        oldWorld: Int,
        oldArea: Int,
        oldMap: Int,
        oldMapScreen: UnityDTMapScreen,
        oldDatabaseScreen: UnityDTDatabaseScreen,
        oldDDocks: [String],
        oldUnlocked: [String: Int],
        oldCode: String,
        oldCodeStatus: Int
    ) {
        if oldScreen == .character,
           game.state.screen == .battle,
           let battle = game.state.battle {
            enqueuePresentation(
                .encounter(
                    enemy: battle.enemyName,
                    boss: battle.boss
                ),
                duration: battle.boss
                    ? UnityDTPresentation.encounterBossLength
                    : UnityDTPresentation.encounterLength
            )
            return
        }

        if oldScreen == .character,
           game.state.screen == .character,
           oldSavedEvent == 1,
           game.state.savedEvent == 0,
           game.state.banner == "DIGISTORM" {
            let escapeTicks = Int.random(in: 0..<40)
            let moved = oldWorld != game.state.currentWorld
                || oldArea != game.state.currentArea
            enqueuePresentation(
                .dataStorm(
                    character: game.state.playerChar ?? 0,
                    moved: moved,
                    escapeTicks: escapeTicks
                ),
                duration: (moved ? 16.9 : 14.65)
                    + (Double(escapeTicks) * 0.1)
            )
            return
        }

        if oldScreen == .mainMenu,
           game.state.screen == .app,
           game.state.app == .camp {
            enqueuePresentation(
                .campOpen(character: game.state.playerChar ?? 0),
                duration: 7.2
            )
            return
        }

        if oldScreen == .app,
           oldApp == .camp,
           game.state.screen == .character {
            enqueuePresentation(
                .campClose(character: game.state.playerChar ?? 0),
                duration: 7.2
            )
            return
        }

        if oldScreen == .app,
           oldApp == .map,
           oldMapScreen == .map,
           game.state.screen == .app,
           game.state.app == .map,
           oldMap != game.state.mapDisplayMap {
            enqueuePresentation(
                .mapTravel(
                    worldSprite: game.currentWorld?.worldSprite
                        ?? "frontier_initial",
                    before: oldMap,
                    after: game.state.mapDisplayMap
                ),
                duration: 1.5
            )
            return
        }

        if oldScreen == .app,
           oldApp == .map,
           oldMapScreen == .distance,
           game.state.screen == .character,
           oldArea != game.state.currentArea {
            let beforeMap = game.catalog.worlds[
                safe: oldWorld
            ]?.areas[safe: oldArea]?.map ?? oldMap
            let afterMap = game.currentArea?.map
                ?? game.state.mapDisplayMap
            enqueuePresentation(
                .mapTravel(
                    worldSprite: game.currentWorld?.worldSprite
                        ?? "frontier_initial",
                    before: beforeMap,
                    after: afterMap
                ),
                duration: 1.5
            )
            return
        }

        if oldScreen == .app,
           oldApp == .database,
           oldDatabaseScreen == .ddockDisplay,
           let changedDock = oldDDocks.indices.first(where: {
               oldDDocks[$0] != game.state.ddocks[safe: $0]
           }),
           let newDigimon = game.state.ddocks[safe: changedDock],
           !newDigimon.isEmpty {
            enqueuePresentation(
                .swapDock(
                    index: changedDock,
                    oldDigimon: oldDDocks[changedDock],
                    digimon: newDigimon
                ),
                duration: 7.25
            )
            return
        }

        if oldScreen == .app,
           oldApp == .digits,
           oldCodeStatus == 1,
           game.state.screen == .mainMenu,
           let unlocked = game.catalog.digimon.first(where: {
               $0.code?.lowercased() == oldCode.lowercased()
           })?.name
            ?? game.state.unlocked.keys.first(where: {
                oldUnlocked[$0] == nil
                    && (game.state.unlocked[$0] ?? 0) > 0
            }) {
            enqueuePresentation(
                .summonUnlock(
                    character: game.state.playerChar ?? 0,
                    digimon: unlocked
                ),
                duration: 15.4
            )
            return
        }

        guard oldScreen == .battle,
              let before = oldBattle,
              let after = game.state.battle else {
            return
        }

        if before.playerName != after.playerName {
            if after.playerName.isEmpty {
                // Battle.cs routes every deport through
                // PlayAnimationDeportDigimon, which plays DeportSpirit
                // for a Spirit-stage form and DeportDigimon otherwise.
                let wasSpirit = game.catalog
                    .digimonByName[before.playerName]?.stage == 6
                enqueuePresentation(
                    wasSpirit
                        ? .deportSpirit(
                            digimon: before.playerName,
                            character: game.state.playerChar ?? 0
                        )
                        : .deport(digimon: before.playerName),
                    duration: wasSpirit ? 7.6 : 3.45
                )
            } else if before.playerName.isEmpty {
                if after.playerName == "susanoomon" {
                    enqueuePresentation(
                        .susanoomonEvolution(
                            character: game.state.playerChar ?? 0
                        ),
                        duration: 20.0
                    )
                    return
                }
                let entry = game.catalog.digimonByName[after.playerName]
                let spirit = entry?.stage == 6
                // Battle.cs ChooseSpiritFromGallery: Human and Animal
                // spirits play SpiritEvolution, the two non-Susanoomon
                // Fusion forms play FusionSpiritEvolution.
                let fusion = spirit && entry?.spiritType == 4
                enqueuePresentation(
                    fusion
                        ? .fusionEvolution(
                            character: game.state.playerChar ?? 0,
                            digimon: after.playerName
                        )
                        : spirit
                            ? .spiritEvolution(
                                character: game.state.playerChar ?? 0,
                                digimon: after.playerName
                            )
                            : .summon(digimon: after.playerName),
                    duration: spirit ? 20.3 : 7.20
                )
            } else {
                enqueuePresentation(
                    .regularEvolution(
                        before: before.playerName,
                        after: after.playerName
                    ),
                    duration: 4.8
                )
            }
            return
        }

        if after.turn > before.turn {
            let unlockedAfterTurn = game.state.unlocked.keys.first(where: {
                oldUnlocked[$0] == nil
                    && (game.state.unlocked[$0] ?? 0) > 0
            })
            let friendlyAttack = after.lastFriendlyAttack
                ?? before.attackIndex
            let enemyAttack = after.lastEnemyAttack ?? 0
            let turnLength = UnityDTBattleTiming.turn(
                friendlyAttack: friendlyAttack,
                enemyAttack: enemyAttack,
                winner: UnityDTBattleTiming.winner(
                    playerHPBefore: before.playerHP,
                    playerHPAfter: after.playerHP,
                    enemyHPBefore: before.enemyHP,
                    enemyHPAfter: after.enemyHP
                )
            )
            enqueuePresentation(
                .battleTurn(
                    friendly: before.playerName,
                    enemy: before.enemyName,
                    friendlyAttack: friendlyAttack,
                    enemyAttack: enemyAttack,
                    playerHPBefore: before.playerHP,
                    playerHPAfter: after.playerHP,
                    enemyHPBefore: before.enemyHP,
                    enemyHPAfter: after.enemyHP,
                    unlocked: unlockedAfterTurn,
                    character: game.state.playerChar ?? 0
                ),
                duration: turnLength
                    + (unlockedAfterTurn == nil ? 0 : 8.25)
            )
        } else if after.message == "FAILED",
                  before.message != after.message {
            // A failed digivolve is RegularEvolution with the same
            // digimon on both sides — it blinks and stays. The port used
            // to invent a black "FAILED" screen that is nowhere in the
            // original.
            enqueuePresentation(
                .regularEvolution(
                    before: after.playerName,
                    after: after.playerName
                ),
                duration: 4.8
            )
        } else if after.message == "BOOSTED",
                  before.message != after.message {
            // Battle.cs AttemptBoost: the sacrifice was already cleared
            // from the d-dock by the time `after` is observed, so the
            // name has to come from the pre-input snapshot.
            let sacrifice = oldDDocks[safe: before.ddockIndex] ?? ""
            enqueuePresentation(
                .boostSucceed(
                    friendly: after.playerName,
                    sacrifice: sacrifice
                ),
                duration: 12.1
            )
        } else if after.message == "BOOST FAIL",
                  before.message != after.message {
            let sacrifice = oldDDocks[safe: before.ddockIndex] ?? ""
            enqueuePresentation(
                .boostFailed(sacrifice: sacrifice),
                duration: 6.7
            )
        }
    }

    private func queueInitialPresentationIfNeeded() {
        guard !didQueueInitialPresentation else { return }
        didQueueInitialPresentation = true
        guard game.state.playerChar == nil,
              game.state.screen == .charSelection else {
            return
        }
        enqueuePresentation(
            .characterSelection(character: game.state.charIndex),
            duration: 5.0
        )
    }

    private func queueOpeningPresentationForQA() {
        guard !didQueueInitialPresentation else { return }
        didQueueInitialPresentation = true
        let character = game.state.playerChar
            ?? game.state.charIndex
        let arguments = ProcessInfo.processInfo.arguments
        let offset: TimeInterval
        if let index = arguments.firstIndex(
            of: "--qa-opening-offset"
        ),
        arguments.indices.contains(index + 1) {
            offset = TimeInterval(arguments[index + 1]) ?? 0
        } else {
            offset = 0
        }
        beginPresentation(
            .gameStart(
                character: character,
                spirit: game.catalog.playerSpiritName(
                    for: character
                ),
                initial: game.state.ddocks.first(where: {
                    !$0.isEmpty
                }) ?? "agumon"
            ),
            duration: 52.78125,
            elapsedOffset: min(52.75, max(0, offset))
        )
    }

    /// QA-only: play a single cutscene in isolation, selected by
    /// `--qa-cutscene <name>` and optionally seeked with
    /// `--qa-cutscene-offset <seconds>`.
    private func queueCutscenePresentationForQA() {
        guard !didQueueInitialPresentation else { return }
        didQueueInitialPresentation = true

        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--qa-cutscene"),
              arguments.indices.contains(flagIndex + 1) else {
            return
        }
        let name = arguments[flagIndex + 1]
        let offset: TimeInterval
        if let offsetIndex = arguments.firstIndex(
            of: "--qa-cutscene-offset"
        ),
        arguments.indices.contains(offsetIndex + 1) {
            offset = TimeInterval(arguments[offsetIndex + 1]) ?? 0
        } else {
            offset = 0
        }

        let character = game.state.playerChar ?? 0
        let spirit = game.catalog.playerSpiritName(for: character)
        let partner = game.state.ddocks.first(where: { !$0.isEmpty })
            ?? "agumon"

        let selected: (UnityDTPresentation.Kind, TimeInterval)?
        switch name {
        case "encounter":
            selected = (
                .encounter(enemy: "kokuwamon", boss: false),
                UnityDTPresentation.encounterLength
            )
        case "encounter-boss":
            selected = (
                .encounter(enemy: "cerberusmon", boss: true),
                UnityDTPresentation.encounterBossLength
            )
        case "summon":
            selected = (.summon(digimon: partner), 7.20)
        case "regular-evolution":
            selected = (
                .regularEvolution(before: partner, after: "greymon"),
                4.8
            )
        case "susanoomon":
            selected = (
                .susanoomonEvolution(character: character),
                20.0
            )
        case "fusion":
            selected = (
                .fusionEvolution(
                    character: character,
                    digimon: "kaisergreymon"
                ),
                20.3
            )
        case "fusion-magna":
            selected = (
                .fusionEvolution(
                    character: character,
                    digimon: "magnagarurumon"
                ),
                20.3
            )
        case "spirit-evolution":
            selected = (
                .spiritEvolution(character: character, digimon: spirit),
                20.3
            )
        case "battle-turn":
            selected = (
                .battleTurn(
                    friendly: spirit,
                    enemy: "kokuwamon",
                    friendlyAttack: 0,
                    enemyAttack: 0,
                    playerHPBefore: 40,
                    playerHPAfter: 40,
                    enemyHPBefore: 30,
                    enemyHPAfter: 12,
                    unlocked: nil,
                    character: character
                ),
                UnityDTBattleTiming.turn(
                    friendlyAttack: 0,
                    enemyAttack: 0,
                    winner: 0
                )
            )
        case "battle-turn-ability":
            selected = (
                .battleTurn(
                    friendly: spirit,
                    enemy: "kokuwamon",
                    friendlyAttack: 2,
                    enemyAttack: 1,
                    playerHPBefore: 40,
                    playerHPAfter: 40,
                    enemyHPBefore: 30,
                    enemyHPAfter: 5,
                    unlocked: nil,
                    character: character
                ),
                UnityDTBattleTiming.turn(
                    friendlyAttack: 2,
                    enemyAttack: 1,
                    winner: 0
                )
            )
        case "battle-turn-crush":
            selected = (
                .battleTurn(
                    friendly: spirit,
                    enemy: "kokuwamon",
                    friendlyAttack: 1,
                    enemyAttack: 2,
                    playerHPBefore: 40,
                    playerHPAfter: 22,
                    enemyHPBefore: 30,
                    enemyHPAfter: 30,
                    unlocked: nil,
                    character: character
                ),
                UnityDTBattleTiming.turn(
                    friendlyAttack: 1,
                    enemyAttack: 2,
                    winner: 1
                )
            )
        case "deport":
            selected = (.deport(digimon: "kokuwamon"), 3.45)
        case "failed-evolution":
            selected = (.failedEvolution, 2.4)
        case "boost-succeed":
            selected = (
                .boostSucceed(friendly: spirit, sacrifice: "kokuwamon"),
                12.1
            )
        case "boost-failed":
            selected = (.boostFailed(sacrifice: "kokuwamon"), 6.7)
        case "data-storm":
            selected = (
                .dataStorm(
                    character: character,
                    moved: true,
                    escapeTicks: 3
                ),
                16.9 + 0.3
            )
        case "camp-open":
            selected = (.campOpen(character: character), 7.2)
        case "camp-close":
            selected = (.campClose(character: character), 7.2)
        case "map-travel":
            selected = (
                .mapTravel(
                    worldSprite: game.currentWorld?.worldSprite
                        ?? "frontier_initial",
                    before: 0,
                    after: 1
                ),
                1.5
            )
        case "swap-dock":
            selected = (
                .swapDock(index: 0, oldDigimon: partner, digimon: "greymon"),
                7.25
            )
        case "summon-unlock":
            selected = (
                .summonUnlock(character: character, digimon: "greymon"),
                15.4
            )

        // The scenes below are queued by `record(_:)` as gameplay
        // resolves rather than by a screen transition, so they had no
        // way of being inspected on their own until now.
        case "character-selection":
            selected = (.characterSelection(character: character), 5.0)
        case "level-up":
            selected = (.levelUp(before: 12, after: 13), 5.5)
        case "level-down":
            selected = (.levelDown(before: 13, after: 12), 5.5)
        case "level-up-digimon":
            selected = (.levelUpDigimon(digimon: partner), 6.15)
        case "level-down-digimon":
            selected = (.levelDownDigimon(digimon: partner), 6.15)
        case "erase-digimon":
            selected = (.eraseDigimon(digimon: partner), 5.4)
        case "unlock-digimon":
            selected = (
                .unlockDigimon(digimon: "greymon", spiritForm: false),
                5.15
            )
        case "unlock-spirit":
            selected = (
                .unlockDigimon(digimon: spirit, spiritForm: true),
                5.15
            )
        case "receive-spirit":
            selected = (.receiveSpirit(digimon: spirit), 4.15)
        case "lose-spirit":
            selected = (
                .loseSpirit(spirit: spirit, enemy: "cerberusmon"),
                8.35
            )
        case "change-distance":
            selected = (.changeDistance(before: 6000, after: 4200), 2.0)
        case "char-happy":
            selected = (.charMood(character: character, happy: true), 2.0)
        case "char-sad":
            selected = (.charMood(character: character, happy: false), 2.0)
        case "enemy-escapes":
            selected = (
                .enemyEscapes(enemy: "kokuwamon", friendly: spirit),
                4.0
            )
        case "deport-spirit":
            selected = (
                .deportSpirit(digimon: spirit, character: character),
                7.6
            )
        case "spend-call-points":
            selected = (.spendCallPoints(before: 5, after: 2), 2.0)
        case "spirit-power-pay":
            selected = (
                .spiritPower(before: 60, after: 45, spending: true),
                3.0
            )
        case "spirit-power-award":
            selected = (
                .spiritPower(before: 45, after: 48, spending: false),
                2.2
            )

        // Map, reward and world-transition scenes.
        case "award-distance":
            selected = (
                .awardDistance(score: 420, before: 6000, after: 5580),
                6.0
            )
        case "display-new-area":
            selected = (
                .displayNewArea(
                    world: game.state.currentWorld,
                    area: 3,
                    distance: 9000
                ),
                UnityDTPresentation.displayNewAreaLength
            )
        case "forced-travel":
            selected = (
                .forcedTravel(
                    world: game.state.currentWorld,
                    areaBefore: 0,
                    areaAfter: 5,
                    distance: 11000
                ),
                UnityDTPresentation.forcedTravelMapLength
                    + UnityDTPresentation.displayNewAreaLength
            )
        case "destroy-box":
            selected = (.destroyBox, 3.5)
        case "box-resists":
            selected = (.boxResists(friendly: partner), 4.15)
        case "reward-empty":
            selected = (.rewardEmpty, 2.0)
        case "reward-distance":
            selected = (
                .rewardDistance(
                    punishment: false,
                    before: 6000,
                    after: 5000
                ),
                7.0
            )
        case "reward-distance-punish":
            selected = (
                .rewardDistance(
                    punishment: true,
                    before: 6000,
                    after: 8000
                ),
                7.0
            )
        case "reward-spirit-power":
            selected = (
                .rewardSpiritPower(
                    punishment: false,
                    before: 45,
                    after: 55
                ),
                7.0
            )
        case "reward-code":
            selected = (
                .rewardCode(digimon: "greymon", code: "PFHT2"),
                14.25
            )
        case "transition-map1":
            selected = (
                .transitionToMap1(
                    character: character,
                    world: game.state.currentWorld,
                    area: 0,
                    distance: 15000
                ),
                15.7 + UnityDTPresentation.displayNewAreaLength
            )
        case "transition-map3":
            let stolen = [
                "agunimon", "lobomon", "kazemon", "beetlemon",
                "kumamon", "loweemon", "burninggreymon",
                "kendogarurumon", "zephyrmon", "korikakumon"
            ]
            selected = (
                .transitionToMap3(
                    character: character,
                    enemy: "cerberusmon",
                    spirits: stolen
                ),
                UnityDTPresentation.transitionToMap3Length(
                    spirits: stolen.count
                )
            )

        default:
            selected = nil
        }

        guard let (kind, duration) = selected else { return }
        let seek = min(duration - 0.01, max(0, offset))

        // `--qa-freeze` holds the scene at exactly `seek` seconds so a
        // screenshot captures a known frame instead of racing playback.
        if arguments.contains("--qa-freeze") {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                presentationProgress = seek / duration
                presentation = UnityDTPresentation(
                    kind: kind,
                    startedAt: Date().addingTimeInterval(-seek),
                    duration: duration
                )
            }
            return
        }

        beginPresentation(kind, duration: duration, elapsedOffset: seek)
    }

    /// Appends a cutscene to the queue, matching Unity's
    /// `GameManager.EnqueueAnimation`. A game action can queue several in
    /// a row and they play back to back, which is how the original
    /// chains — say — spirit power, level up and the happy character
    /// after a won battle.
    private func enqueuePresentation(
        _ kind: UnityDTPresentation.Kind,
        duration: TimeInterval
    ) {
        guard duration > 0 else { return }
        if presentation == nil {
            beginPresentation(kind, duration: duration)
        } else {
            pendingPresentations.append((kind, duration))
        }
    }

    /// Plays the next queued cutscene, or clears the stage when the
    /// queue empties. Mirrors `ScreenManager.ConsumeQueue`.
    private func advancePresentationQueue() {
        presentationAudioTask?.cancel()
        presentationAudioTask = nil
        presentationTask = nil

        guard !pendingPresentations.isEmpty else {
            withAnimation(.linear(duration: 0.08)) {
                presentation = nil
            }
            return
        }
        let next = pendingPresentations.removeFirst()
        beginPresentation(next.kind, duration: next.duration)
    }

    private func beginPresentation(
        _ kind: UnityDTPresentation.Kind,
        duration: TimeInterval,
        elapsedOffset: TimeInterval = 0
    ) {
        presentationTask?.cancel()
        presentationAudioTask?.cancel()
        let item = UnityDTPresentation(
            kind: kind,
            startedAt: Date().addingTimeInterval(
                -elapsedOffset
            ),
            duration: duration
        )
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            presentationProgress = min(
                1,
                max(0, elapsedOffset / duration)
            )
            presentation = item
        }
        DispatchQueue.main.async {
            withAnimation(
                .linear(
                    duration: max(
                        0.001,
                        duration - elapsedOffset
                    )
                )
            ) {
                presentationProgress = 1
            }
        }
        let cues = UnityDTPresentation.cues(for: kind)
        if !cues.isEmpty {
            presentationAudioTask = Task { @MainActor in
                var previous = elapsedOffset
                for (offset, sound) in cues
                    where offset >= elapsedOffset {
                    try? await Task.sleep(
                        nanoseconds: UInt64(
                            max(0, offset - previous)
                                * 1_000_000_000
                        )
                    )
                    guard !Task.isCancelled,
                          presentation?.id == item.id else {
                        return
                    }
                    if sound.isEmpty {
                        game.stopSound()
                    } else {
                        game.play(sound)
                    }
                    previous = offset
                }
            }
        }
        presentationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    max(0, duration - elapsedOffset)
                        * 1_000_000_000
                )
            )
            guard !Task.isCancelled,
                  presentation?.id == item.id else {
                return
            }
            advancePresentationQueue()
        }
    }

    private var characterSelect: some View {
        return ZStack {
            UnityDTSprite(
                key: characterSpriteKey(
                    game.state.charIndex,
                    0
                ),
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
            UnityDTSprite(
                key: game.catalog.spriteDBKey("arrows")
                    ?? "sliced:menus_16",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        }
    }

    /// Cutscene frame budget: startle in place, then pan the camera over
    /// to the enemy. 30fps: 3.0s startle, 3.0s pan. After that the view
    /// stays parked on the enemy until the player presses on.
    private static let cutsceneStartleFrames = 90
    private static let cutscenePanFrames = 90
    private static let cutsceneDuration: TimeInterval = 6.0

    /// Eases into the stop instead of snapping, so the pan visibly
    /// settles on the enemy rather than just ending mid-slide.
    private static func easeOutCubic(_ t: Double) -> Double {
        let clamped = min(1, max(0, t))
        return 1 - pow(1 - clamped, 3)
    }

    private func startHomeEncounterCutscene() {
        homeCutsceneTask?.cancel()
        homeCutsceneStartFrame = game.animationFrame
        homeCutsceneActive = true
        homeStandoff = false
        homeCutsceneTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.cutsceneDuration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            homeCutsceneActive = false
            // The camera does not swing back: it holds on the enemy,
            // READY on screen, and the next press walks into the fight.
            homeStandoff = true
        }
    }

    private var characterHome: some View {
        let event = game.state.savedEvent != 0
            || game.state.currentDistance == 1
        let phase = game.animationFrame / 15

        // Five seconds without a step and the character sits down.
        let resting = walkingUntil
            .map { Date().timeIntervalSince($0) > 2.5 } ?? true
        let sleeping = Date().timeIntervalSince(lastHomeWalkAt) > 10
            && resting
            && !event
            && !homeStandoff

        let cutsceneElapsed = homeCutsceneActive
            ? game.animationFrame - homeCutsceneStartFrame
            : nil
        // 0 through the startle, then 0->1 as the pan runs. The standoff
        // that follows holds it parked at the far end.
        let panFraction: Double = {
            if homeStandoff { return 1 }
            guard let elapsed = cutsceneElapsed else { return 0 }
            let intoPan = elapsed - Self.cutsceneStartleFrames
            guard intoPan > 0 else { return 0 }
            return Self.easeOutCubic(
                Double(intoPan) / Double(Self.cutscenePanFrames)
            )
        }()
        // The character exits off the right edge — the direction it
        // faces — as the camera swings past it toward the enemy.
        let characterPanX = 34.0 * panFraction
        // A quick "!" during the startle only, in place of the game's
        // full-screen shock-line flash.
        let startled = cutsceneElapsed.map { $0 < Self.cutsceneStartleFrames }
            ?? false

        return ZStack {
            // The digimon the pending event will actually spawn. It
            // enters from the left as the camera swings onto it and then
            // stands its ground for the whole standoff.
            if let waiting = game.state.pendingEnemy,
               panFraction > 0 {
                let enemyX = -30.0 + 33.0 * panFraction
                // Opaque behind it, the way the game layers its own
                // sprites, so it never tangles with what it crosses.
                // Sized to land its feet on the ground line at y 29.
                UnityDTSolidRect(x: enemyX, y: 5, w: 26, h: 24)
                UnityDTSprite(
                    key: "digimon:\(waiting)",
                    x: enemyX,
                    y: 5,
                    w: 26,
                    h: 24,
                    mirrored: true
                )
            }
            UnityDTCharacterMotionStage(
            character: game.state.playerChar
                ?? game.state.charIndex,
            idleFrame: characterSpriteFrame,
            event: event || cutsceneElapsed != nil,
            eventPhase: cutsceneElapsed.map { $0 / 10 } ?? phase,
            showEyes: game.currentWorld?.showEyes == true,
            defeated: game.state.isCharacterDefeated == true,
            resting: resting,
            walkProgress: walkingProgress,
            walkLeadFrame: walkingLeadFrame,
            panX: characterPanX,
            showEventOverlay: cutsceneElapsed == nil && !homeStandoff
            )
            // A small startled mark in front of the character, rather
            // than the game's full-screen shock-line flash. Drawn as
            // cells rather than a label: the big pixel font has no "!"
            // glyph, so a label silently rendered nothing at all.
            if startled, let elapsed = cutsceneElapsed {
                // Bobs a cell on the same beat the character twitches,
                // so the mark reads as a reaction and not a decal.
                let bob = Double((elapsed / 10) % 2)
                UnityDTPixelRect(
                    x: 24,
                    y: 3 + bob,
                    w: 2,
                    h: 4,
                    color: .black
                )
                UnityDTPixelRect(
                    x: 24,
                    y: 8 + bob,
                    w: 2,
                    h: 1,
                    color: .black
                )
            }
            if sleeping {
                UnityDTSolidRect(x: 3, y: 8, w: 6, h: 6)
                sleepZMark(frame: game.animationFrame)
            }
            if homeStandoff {
                // Opaque strip, so the word cuts cleanly out of whatever
                // it lands over rather than blending into it. Along the
                // top, leaving the enemy stood on the ground line clear.
                UnityDTSolidRect(x: 0, y: 0, w: 32, h: 6)
                UnityDTLabel(
                    "READY",
                    x: 0,
                    y: 1,
                    w: 32,
                    h: 5,
                    size: 2.8
                )
            }
        }
    }

    /// QA-only: replay a timed input sequence passed as
    /// `--qa-input c@1,l@2,r@3,b@4` (l/c/r/d = taps, b = long back;
    /// `@seconds` is the absolute delay from launch).
    private func scheduleQAInputsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        // `--qa-autotap <interval>` keeps tapping centre forever, so a
        // run cannot stall just because a tap landed during a cutscene
        // and was ignored.
        if let autoIndex = arguments.firstIndex(of: "--qa-autotap"),
           arguments.indices.contains(autoIndex + 1),
           let interval = Double(arguments[autoIndex + 1]) {
            Timer.scheduledTimer(
                withTimeInterval: max(0.2, interval),
                repeats: true
            ) { _ in
                Task { @MainActor in performInput(.center) }
            }
        }

        guard let flagIndex = arguments.firstIndex(of: "--qa-input"),
              arguments.indices.contains(flagIndex + 1) else {
            return
        }
        for token in arguments[flagIndex + 1].split(separator: ",") {
            let parts = token.split(separator: "@")
            guard let name = parts.first,
                  let delay = parts.count > 1
                    ? Double(parts[1])
                    : nil else {
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch name {
                case "l": performInput(.left)
                case "c": performInput(.center)
                case "r": performInput(.right)
                case "d": performInput(.down)
                case "b": game.longBack()
                default: break
                }
            }
        }
    }

    private func triggerWalkingAnimation() {
        walkingLeadFrame = walkingLeadFrame == 0 ? 1 : 0
        var resetTransaction = Transaction()
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            walkingProgress = 0
        }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: 2.5)) {
                walkingProgress = 1
            }
        }
    }

    @ViewBuilder
    private func sleepZMark(frame: Int) -> some View {
        let bob = Double((frame / 30) % 2)
        let x = 4.0
        let y = 9.0 - bob
        UnityDTPixelRect(x: x, y: y, w: 4, h: 1, color: .black)
        UnityDTPixelRect(x: x + 2, y: y + 1, w: 1, h: 1, color: .black)
        UnityDTPixelRect(x: x + 1, y: y + 2, w: 1, h: 1, color: .black)
        UnityDTPixelRect(x: x, y: y + 3, w: 4, h: 1, color: .black)
    }

    private func startCharacterAnimation() {
        characterAnimationTask?.cancel()
        characterAnimationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: 500_000_000
                )
                guard !Task.isCancelled else { return }
                updateCharacterSprite()
            }
        }
    }

    private func updateCharacterSprite() {
        let event = game.state.savedEvent != 0
            || game.state.currentDistance == 1
        let walking = walkingUntil.map { Date() < $0 } ?? false

        if event {
            characterUsedAltSprite.toggle()
            characterSpriteFrame =
                characterUsedAltSprite ? 8 : 0
        } else if walking {
            characterUsedAltSprite.toggle()
            characterSpriteFrame =
                characterUsedAltSprite ? 5 : 4
        } else {
            if characterUsedAltSprite {
                characterUsedAltSprite = false
                return
            }
            characterUsedAltSprite = true
            guard Int.random(in: 0..<4) != 0 else {
                return
            }
            characterLastIdleFrame = Int.random(in: 0..<4)
            characterSpriteFrame = characterLastIdleFrame
        }
    }

    private var mainMenu: some View {
        ZStack {
            let spriteIndex = game.menuApp.mainMenuSpriteIndex
            UnityDTSprite(
                key: game.catalog.spriteDBKey("mainMenu", spriteIndex)
                    ?? "sliced:menus_\(spriteIndex)",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private var appScreen: some View {
        switch game.state.app {
        case .map:
            mapScreen
        case .status:
            statusScreen
        case .game:
            gameMenuScreen
        case .database:
            databaseScreen
        case .digits:
            digitsScreen
        case .camp:
            campScreen
        case .connect:
            connectScreen
        case .evolve:
            evolveScreen
        case .fusion:
            fusionScreen
        case .none:
            mainMenu
        }
    }

    private func scrollingName(_ text: String, y: Double) -> some View {
        UnityDTScrollingName(text: text, y: y)
    }

    /// EVOLVE: one digimon at a time with its line laid out underneath.
    /// Tapping walks a step up the line and plays the game's own
    /// evolution cutscene on the way.
    private var evolveScreen: some View {
        let list = game.evolveBrowseList
        let current = list[safe: game.evolveIndex]
        return ZStack {
            if let current {
                let chain = game.evolveChain(for: current)
                let position = chain.firstIndex(of: current.name) ?? 0
                UnityDTIdleDigimon(
                    name: current.name,
                    x: 7,
                    y: 4,
                    w: 18,
                    h: 18
                )
                // One line of text only. The step along the line rides
                // in front of the name rather than taking its own row —
                // the pixel font has no "/", so "OF" separates.
                scrollingName(
                    "\(position + 1)OF\(max(1, chain.count)) "
                        + current.displayName,
                    y: 25
                )
            }
        }
    }

    /// FUSION: the target and how far off it is, or the checklist of the
    /// spirits it still needs.
    private var fusionScreen: some View {
        let targets = game.fusionTargets
        let target = targets[safe: game.fusionIndex]
        return ZStack {
            if let target {
                let required = game.fusionRequirements(for: target)
                let owned = required.filter(game.isUnlockedName).count
                if game.fusionPage == 0 {
                    UnityDTSprite(
                        key: "digimon:\(target.name)_sp",
                        x: 7,
                        y: 4,
                        w: 18,
                        h: 18
                    )
                    let state = owned >= required.count
                        ? "READY"
                        : "\(owned)OF\(required.count)"
                    scrollingName(
                        state + " " + target.displayName,
                        y: 25
                    )
                } else if let name = required[safe: game.fusionPage - 1] {
                    let have = game.isUnlockedName(name)
                    UnityDTSprite(
                        key: "digimon:\(name)_sp",
                        x: 7,
                        y: 4,
                        w: 18,
                        h: 18
                    )
                    scrollingName(
                        (have ? "OK " : "NEED ") + name.uppercased(),
                        y: 25
                    )
                }
            }
        }
    }

    private var mapScreen: some View {
        let world = game.currentWorld
        let displayedMap = game.state.mapDisplayMap
        let shownAreas = (world?.areas ?? []).filter { $0.map == displayedMap }.sorted { $0.number < $1.number }
        let selectedArea = shownAreas[safe: game.state.mapDisplayAreaIndex] ?? game.currentArea
        let mapKey = "map:\(world?.worldSprite ?? "frontier_initial")_\(displayedMap)"
        return ZStack {
            UnityDTSprite(key: mapKey, x: 0, y: 0, w: 32, h: 32)
            ForEach(shownAreas, id: \.number) { area in
                if game.state.completedAreas[safe: game.state.currentWorld]?[safe: area.number] == true {
                    UnityDTPixelRect(x: Double(area.coords.x), y: Double(area.coords.y), w: 2, h: 2, color: .black)
                }
                if area.number == game.state.currentArea && game.state.mapScreen != .areaSelection {
                    UnityDTPixelRect(x: Double(area.coords.x), y: Double(area.coords.y), w: 2, h: 2, color: .black.opacity((game.frame / 2) % 2 == 0 ? 1 : 0.1))
                }
            }
            if game.state.mapScreen == .areaSelection, let selectedArea {
                UnityDTPixelRect(x: Double(selectedArea.coords.x), y: Double(selectedArea.coords.y), w: 2, h: 2, color: .black.opacity((game.frame / 2) % 2 == 0 ? 1 : 0.1))
                let top = displayedMap == 0 || displayedMap == 3
                // Unity's TextBox prefab is a 32x5 box with an opaque
                // LCD-background fill, so it hides the "MAP N" caption
                // baked into the map sprite behind it.
                UnityDTSolidRect(x: 2, y: top ? 1 : 26, w: 30, h: 5)
                UnityDTLabel(String(format: "area%02d", selectedArea.number + 1), x: 2, y: top ? 1 : 26, w: 30, h: 5, size: 2.8, alignment: .leading)
            }
            if game.state.mapScreen == .distance, let selectedArea {
                let distance = selectedArea.number == game.state.currentArea ? game.state.currentDistance : selectedArea.distance
                // Unity builds the distance screen as an opaque sprite,
                // so it hides the map and its "MAP N" caption rather
                // than letting them show through behind the number.
                UnityDTSolidRect(x: 0, y: 0, w: 32, h: 32)
                UnityDTSprite(key: game.catalog.spriteDBKey("map_distanceScreen") ?? "sliced:menus_210", x: 0, y: 0, w: 32, h: 32)
                UnityDTLabel("\(distance)", x: 6, y: 25, w: 25, h: 5, size: 3.2, alignment: .trailing)
            }
        }
    }

    private var statusScreen: some View {
        let unlocked = game.state.unlocked.filter { $0.value > 0 }.count
        let pages = [
            ("DISTANCE", "\(game.state.currentDistance)"),
            ("LEVEL", "LV \(game.playerLevel) XP \(game.state.playerExperience)"),
            ("COLLECT", "\(unlocked)/\(game.catalog.digimon.count)")
        ]
        let page = pages[safe: game.state.statusPage] ?? pages[0]
        return ZStack {
            if game.state.statusPage == 8 {
                statusResetScreen
            } else {
                UnityDTSprite(key: statusBackgroundKey(game.state.statusPage), x: 0, y: 0, w: 32, h: 32)
            }
            if game.state.statusPage == 7 {
                // Training points. `games_score` is the same 32x5 SCORE
                // strip the mini-game reward board uses.
                UnityDTSprite(
                    key: game.catalog.spriteDBKey("games_score")
                        ?? "sliced:misc_17",
                    x: 0,
                    y: 4,
                    w: 32,
                    h: 5
                )
                UnityDTLabel(
                    "\(game.state.trainingScore ?? 0)",
                    x: 0,
                    y: 16,
                    w: 31,
                    h: 5,
                    size: 3.2
                )
            } else if game.state.statusPage <= 2 {
                UnityDTLabel(page.1, x: 0, y: game.state.statusPage == 2 ? 10 : 10, w: game.state.statusPage == 2 ? 24 : 31, h: 5, size: 3.2)
                if game.state.statusPage == 0 {
                    UnityDTLabel("\(game.state.steps)", x: 0, y: 26, w: 31, h: 5, size: 3.2)
                } else if game.state.statusPage == 1 {
                    UnityDTLabel("\(game.state.spiritPower)", x: 0, y: 26, w: 31, h: 5, size: 3.2)
                }
            } else if game.state.statusPage < 8 {
                let index = game.state.statusPage - 3
                let docked = game.state.ddocks[safe: index] ?? ""
                if !docked.isEmpty {
                    UnityDTIdleDigimon(name: docked, x: 4, y: 8, w: 24, h: 24)
                } else {
                    UnityDTSprite(key: game.catalog.spriteDBKey("status_ddockEmpty") ?? "sliced:misc_2", x: 4, y: 8, w: 24, h: 24)
                }
            }
        }
    }

    private var statusResetScreen: some View {
        let prompts = ["RESET?", "SURE?", "REALLY", "ERASE?"]
        let step = min(game.statusResetConfirmStep, prompts.count - 1)
        return ZStack {
            // Nothing is erased until all four prompts are confirmed.
            UnityDTPixelRect(x: 9, y: 9, w: 14, h: 2, color: .black)
            UnityDTPixelRect(x: 12, y: 7, w: 8, h: 2, color: .black)
            UnityDTPixelRect(x: 11, y: 11, w: 10, h: 10, color: .black)
            UnityDTSolidRect(x: 13, y: 13, w: 2, h: 6)
            UnityDTSolidRect(x: 17, y: 13, w: 2, h: 6)
            UnityDTPixelRect(x: 25, y: 10, w: 2, h: 7, color: .black)
            UnityDTPixelRect(x: 25, y: 19, w: 2, h: 2, color: .black)
            ForEach(0..<4, id: \.self) { index in
                UnityDTPixelRect(
                    x: Double(7 + index * 5),
                    y: 23,
                    w: 3,
                    h: 2,
                    color: .black.opacity(index <= step ? 1 : 0.18)
                )
            }
            UnityDTLabel(
                prompts[step],
                x: 0,
                y: 26,
                w: 32,
                h: 6,
                size: 2.8
            )
        }
    }

    private var databaseScreen: some View {
        ZStack {
            switch game.state.databaseScreen {
            case .menu:
                UnityDTSprite(key: game.catalog.spriteDBKey("database_sections", game.state.databaseMenuIndex) ?? "sliced:menus_150", x: 0, y: 0, w: 32, h: 32)
            case .spiritMenu:
                let element = game.databaseAvailableElements()[safe: game.state.databaseElementIndex] ?? 0
                UnityDTSprite(key: element < 10 ? (game.catalog.spriteDBKey("elements", element) ?? "sliced:menus_165") : (game.catalog.spriteDBKey("database_spirit_fusion") ?? "sliced:menus_157"), x: 0, y: 0, w: 32, h: 32)
            case .gallery:
                let name = game.databaseGalleryList[safe: game.state.databaseGalleryIndex] ?? "numemon"
                let inDock = game.state.ddocks.contains(name)
                UnityDTSprite(key: game.catalog.spriteDBKey(inDock ? "invertedArrowsSmall" : "arrowsSmall") ?? (game.catalog.spriteDBKey("arrowsSmall") ?? "sliced:menus_18"), x: 0, y: 0, w: 32, h: 32)
                UnityDTIdleDigimon(name: name, x: 4, y: 4, w: 24, h: 24)
            case .pages:
                databasePageView
            case .ddockList:
                UnityDTSprite(key: game.catalog.spriteDBKey("database_ddocks", game.state.databaseDockIndex) ?? "sliced:menus_37", x: 0, y: 0, w: 32, h: 32)
            case .ddockDisplay:
                UnityDTSprite(key: game.catalog.spriteDBKey("status_ddock", game.state.databaseDockIndex) ?? "sliced:menus_33", x: 0, y: 0, w: 32, h: 32)
                let docked = game.state.ddocks[safe: game.state.databaseDockIndex] ?? ""
                if !docked.isEmpty {
                    UnityDTIdleDigimon(name: docked, x: 4, y: 8, w: 24, h: 24)
                } else {
                    UnityDTSprite(key: game.catalog.spriteDBKey("status_ddockEmpty") ?? "sliced:misc_2", x: 4, y: 8, w: 24, h: 24)
                }
            }
        }
    }

    @ViewBuilder
    private var databasePageView: some View {
        if let digimon = game.databasePageDigimon {
            let page = game.state.databasePageIndex
            UnityDTSprite(key: game.catalog.spriteDBKey("database_pages", page) ?? "sliced:menus_191", x: 0, y: 0, w: 32, h: 32)
            UnityDTLabel(String(format: "%03d %@", digimon.number, digimon.name), x: 0, y: 0, w: 32, h: 7, size: 2.4)
            if page == 0 {
                UnityDTLabel("\(digimon.baseLevel)", x: 16, y: 9, w: 15, h: 5, size: 3.2, alignment: .trailing)
                UnityDTLabel("\(digimon.stats.HP)", x: 16, y: 17, w: 15, h: 5, size: 3.2, alignment: .trailing)
                UnityDTSprite(key: game.catalog.spriteDBKey("elementNames", digimon.element) ?? "sliced:misc_7", x: 1, y: 25, w: 30, h: 5)
            } else if page == 1 {
                UnityDTLabel("\(digimon.stats.EN)", x: 16, y: 9, w: 15, h: 5, size: 3.2, alignment: .trailing)
                UnityDTLabel("\(digimon.stats.CR)", x: 16, y: 17, w: 15, h: 5, size: 3.2, alignment: .trailing)
                UnityDTLabel("\(digimon.stats.AB)", x: 16, y: 25, w: 15, h: 5, size: 3.2, alignment: .trailing)
            } else {
                UnityDTLabel(digimon.code ?? "-----", x: 2, y: 23, w: 30, h: 8, size: 4.2, alignment: .trailing)
            }
        }
    }

    private var digitsScreen: some View {
        codeInputScreen(
            code: game.state.digitsCode,
            selectedAscii: game.state.codeSelectedAscii,
            status: game.state.codeStatus
        )
    }

    @ViewBuilder
    private var gameMenuScreen: some View {
        if let miniGame = game.miniGame {
            miniGameView(miniGame)
        } else {
            let selectedIndex = game.state.mapPage == 0
                ? min(game.state.databaseIndex, 2)
                : game.state.databaseIndex
            let field = game.state.mapPage == 1
                ? "games_reward"
                : game.state.mapPage == 2
                    ? "games_travel"
                    : "game_sections"
            // PIPE MONSTERS has no icon in the sprite database — it is
            // not in the original at all — so it ships its own, drawn on
            // the same frame the shipped icons use.
            let pipeMonsters = game.state.mapPage == 1
                && selectedIndex == 3
            UnityDTSprite(
                key: pipeMonsters
                    ? "game:pipemonsters_icon"
                    : game.catalog.spriteDBKey(
                        field,
                        selectedIndex
                    ) ?? "sliced:menus_45",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func miniGameView(
        _ miniGame: UnityDTMiniGame
    ) -> some View {
        switch miniGame {
        case .finder(let finder):
            finderView(finder)
        case .jackpot(let jackpot):
            jackpotView(jackpot)
        case .speedRunner(let speedRunner):
            speedRunnerView(speedRunner)
        case .digiHunter(let hunter):
            digiHunterView(hunter)
        case .maze(let maze):
            mazeView(maze)
        case .energyWars(let war):
            energyWarsView(war)
        case .digiCatch(let catcher):
            digiCatchView(catcher)
        case .pipeMonsters(let pipes):
            pipeMonstersView(pipes)
        case .training(let training):
            trainingView(training)
        }
    }

    /// Training: two pickers for the fighters, then the battle attack
    /// menu with the sparring partner's remaining life along the bottom.
    @ViewBuilder
    private func trainingView(
        _ training: UnityDTTrainingGame
    ) -> some View {
        switch training.phase {
        case .pickFriendly, .pickEnemy:
            let roster = game.trainingRoster
            let isEnemy = training.phase == .pickEnemy
            let index = isEnemy
                ? training.enemyIndex
                : training.friendlyIndex
            if let pick = roster[safe: index] {
                // The opponent is shown mirrored, the way an enemy is
                // drawn in a real battle, so which side is being picked
                // reads without a caption.
                UnityDTIdleDigimon(
                    name: pick.name,
                    x: 7,
                    y: 3,
                    w: 18,
                    h: 18,
                    mirrored: isEnemy
                )
                // Which side is being picked reads from the facing
                // alone — no marker needed.
                scrollingName(pick.displayName, y: 25)
            }

        case .fight:
            UnityDTSprite(
                key: game.catalog.spriteDBKey(
                    "battle_attackMenu",
                    training.attackIndex
                ) ?? "sliced:menus_105",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func pipeMonstersView(
        _ game: UnityDTPipeMonstersGame
    ) -> some View {
        let now = Date()
        switch game.phase {
        case .intro:
            pipeMonstersIntro(game, now: now)

        case .playing:
            UnityDTLabel(
                "\(game.score)",
                x: 1,
                y: 0,
                w: 12,
                h: 5,
                size: 2.8,
                alignment: .leading
            )
            // Lives, as one cell per monster still allowed to escape.
            ForEach(0..<3, id: \.self) { index in
                if index < game.livesLeft {
                    UnityDTPixelRect(
                        x: Double(25 + index * 2),
                        y: 1,
                        w: 1,
                        h: 3,
                        color: .black
                    )
                }
            }
            pipeMonstersField(game, now: now)
            pipeMonstersHammer(game, now: now)

        case .over:
            UnityDTLabel(
                "END",
                x: 6,
                y: 9,
                w: 20,
                h: 5,
                size: 3.2
            )
            UnityDTLabel(
                "\(game.score)",
                x: 6,
                y: 19,
                w: 20,
                h: 5,
                size: 2.8
            )
        }
    }

    @ViewBuilder
    private func pipeMonstersIntro(
        _ game: UnityDTPipeMonstersGame,
        now: Date
    ) -> some View {
        let elapsed = now.timeIntervalSince(game.phaseStarted)
        // The four pipes draw themselves in one after another, then the
        // press-the-button prompt takes over the middle of the screen.
        ForEach(0..<UnityDTPipeMonstersGame.laneCount, id: \.self) {
            lane in
            if elapsed >= 0.35 + Double(lane) * 0.3 {
                pipeMonstersPipe(lane: lane)
            }
        }
        if elapsed < 1.5 {
            UnityDTLabel(
                "PIPE",
                x: 0,
                y: 8,
                w: 32,
                h: 5,
                size: 3.2
            )
        } else {
            UnityDTSprite(
                key: self.game.catalog.spriteDBKey(
                    "pressAButton",
                    Int((elapsed - 1.5) / 0.35).isMultiple(of: 2) ? 0 : 1
                ) ?? "sliced:animations_60",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func pipeMonstersField(
        _ game: UnityDTPipeMonstersGame,
        now: Date
    ) -> some View {
        // Monsters first, clipped to the mouth of the pipe so they read
        // as climbing out of it, then the pipes on top.
        UnityDTClip(x: 0, y: 5, w: 32, h: 17) {
            ForEach(0..<UnityDTPipeMonstersGame.laneCount, id: \.self) {
                lane in
                let pipe = game.pipes[lane]
                if pipe.occupant != .empty {
                    let out = game.emergence(pipe, at: now)
                    UnityDTSprite(
                        key: pipe.occupant == .smashed
                            ? (self.game.catalog.spriteDBKey(
                                "digiHunter_explosion"
                            ) ?? "sliced:misc_50")
                            : (self.game.catalog.spriteDBKey(
                                "digiHunter_faces",
                                1
                            ) ?? "sliced:misc_46"),
                        x: Double(pipeMonstersX(lane)),
                        y: 22 - 8 * out,
                        w: 8,
                        h: 8
                    )
                }
            }
        }
        ForEach(0..<UnityDTPipeMonstersGame.laneCount, id: \.self) {
            lane in
            pipeMonstersPipe(lane: lane)
        }
    }

    /// Left edge of a lane. Three 8-wide pipes at a pitch of 10, with
    /// the spare column split either side of the screen.
    private func pipeMonstersX(_ lane: Int) -> Int {
        1 + lane * 10
    }

    @ViewBuilder
    private func pipeMonstersPipe(lane: Int) -> some View {
        // Rim, then the two walls running off the bottom of the screen.
        UnityDTPixelRect(
            x: Double(pipeMonstersX(lane)),
            y: 22,
            w: 8,
            h: 2,
            color: .black
        )
        UnityDTPixelRect(
            x: Double(pipeMonstersX(lane) + 1),
            y: 24,
            w: 1,
            h: 8,
            color: .black
        )
        UnityDTPixelRect(
            x: Double(pipeMonstersX(lane) + 6),
            y: 24,
            w: 1,
            h: 8,
            color: .black
        )
    }

    @ViewBuilder
    private func pipeMonstersHammer(
        _ game: UnityDTPipeMonstersGame,
        now: Date
    ) -> some View {
        let stuck = now < game.stuckUntil
        let swinging = now < game.swingUntil
        // The marker drops on a swing and stays down while the hammer is
        // stuck after a whiff. The LCD has no half-tone, so a stuck
        // hammer blinks rather than dimming.
        let hidden = stuck && Int(
            now.timeIntervalSince1970 * 8
        ).isMultiple(of: 2)
        if !hidden {
            UnityDTSprite(
                key: self.game.catalog.spriteDBKey(
                    "digiHunter_arrows",
                    1
                ) ?? "sliced:misc_49",
                x: Double(pipeMonstersX(game.lane) + 1),
                y: (swinging || stuck) ? 9 : 6,
                w: 6,
                h: 3
            )
        }
    }

    private func warDigimon(_ name: String, attack: Bool) -> some View {
        UnityDTSprite(
            key: "digimon:\(name)\(attack ? "_at" : "")",
            x: 4,
            y: 4,
            w: 24,
            h: 24
        )
    }

    private func warEnergyKey(_ name: String) -> String {
        let rank = self.game.catalog.digimonByName[name]
            .map { min(15, max(0, $0.stats.EN / 18)) } ?? 0
        return "energy:energy_\(rank)"
    }

    /// Energy Wars: the two blasts meet at `impact`, drawn the same way
    /// a battle collision is, with the clock along the bottom.
    @ViewBuilder
    private func energyWarsView(
        _ game: UnityDTEnergyWarsGame
    ) -> some View {
        switch game.phase {
        case .intro:
            warDigimon(game.enemy, attack: true)
            UnityDTLabel(
                "ENERGY",
                x: 0,
                y: 26,
                w: 32,
                h: 5,
                size: 2.8
            )

        case .playing:
            // Player's blast fills from the left up to the impact point,
            // the enemy's from the right.
            UnityDTSprite(
                key: warEnergyKey(game.friendly),
                x: game.impact - 24,
                y: 3,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: warEnergyKey(game.enemy),
                x: game.impact,
                y: 3,
                w: 24,
                h: 24,
                mirrored: true
            )
            UnityDTSprite(
                key: self.game.catalog
                    .spriteDBKey("battle_attackCollision")
                    ?? "sliced:menus_20",
                x: game.impact - 3.5,
                y: 3,
                w: 7,
                h: 24
            )
            UnityDTLabel(
                "\(max(0, Int(game.secondsLeft)))",
                x: 0,
                y: 27,
                w: 32,
                h: 5,
                size: 2.8
            )

        case .won:
            warDigimon(game.friendly, attack: true)
            UnityDTLabel("WIN", x: 0, y: 26, w: 32, h: 5, size: 2.8)

        case .lost:
            warDigimon(game.enemy, attack: true)
            UnityDTLabel("LOSE", x: 0, y: 26, w: 32, h: 5, size: 2.8)
        }
    }

    /// Digi-Catch: capsules drop down three lanes into a sliding pad.
    @ViewBuilder
    private func digiCatchView(
        _ game: UnityDTDigiCatchGame
    ) -> some View {
        switch game.phase {
        case .intro:
            UnityDTLabel(
                "DIGI\nCATCH",
                x: 0,
                y: 11,
                w: 32,
                h: 12,
                size: 2.8
            )

        case .playing:
            ForEach(Array(game.capsules.enumerated()), id: \.offset) {
                _, capsule in
                UnityDTPixelRect(
                    x: Double(3 + capsule.lane * 11),
                    y: capsule.y,
                    // Corrupted data is a hollow-looking single row.
                    w: capsule.junk ? 6 : 6,
                    h: capsule.junk ? 2 : 5,
                    color: .black
                )
            }
            // The catching pad.
            UnityDTPixelRect(
                x: Double(2 + game.lane * 11),
                y: 27,
                w: 8,
                h: 2,
                color: .black
            )
            UnityDTLabel(
                "\(game.caught)OF\(game.target)",
                x: 0,
                y: 0,
                w: 32,
                h: 4,
                size: 2.8
            )

        case .won:
            UnityDTLabel("WIN", x: 0, y: 13, w: 32, h: 5, size: 2.8)

        case .lost:
            UnityDTLabel("MISS", x: 0, y: 13, w: 32, h: 5, size: 2.8)
        }
    }

    @ViewBuilder
    private func finderView(
        _ finder: UnityDTFinderGame
    ) -> some View {
        let elapsed = Date().timeIntervalSince(
            finder.phaseStarted
        )
        switch finder.phase {
        case .idle:
            UnityDTSprite(
                key: game.catalog.spriteDBKey(
                    "pressAButton",
                    (game.frame / 6).isMultiple(of: 2) ? 0 : 1
                ) ?? "sliced:animations_60",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        case .hourglass:
            UnityDTSprite(
                key: game.catalog.spriteDBKey("hourglass")
                    ?? "sliced:animations_63",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        case .loading:
            let step = min(
                64,
                Int(elapsed / (1.75 / 64.0)) + 1
            )
            UnityDTPixelRect(
                x: 0,
                y: 0,
                w: 32,
                h: 32,
                color: .black
            )
            // The loading bar is a filled block with its dashes punched
            // out, and Unity builds it on an opaque SpriteBuilder.
            // Without that backing it is black on black and nothing
            // shows while the button is held.
            UnityDTSolidRect(
                x: 0,
                y: Double(-32 + step),
                w: 32,
                h: 32
            )
            UnityDTSprite(
                key: game.catalog.spriteDBKey("loading")
                    ?? "sliced:misc_28",
                x: 0,
                y: Double(-32 + step),
                w: 32,
                h: 32
            )
        case .failure:
            UnityDTSprite(
                key: game.catalog.spriteDBKey("error")
                    ?? "sliced:animations_62",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        case .success:
            let step = min(
                114,
                Int(elapsed / (1.75 / 64.0)) + 1
            )
            UnityDTSolidRect(
                x: 0,
                y: Double(-82 + step),
                w: 32,
                h: 82
            )
            UnityDTSprite(
                key: game.catalog.spriteDBKey("loadingComplete")
                    ?? "sliced:misc_29",
                x: 0,
                y: Double(-82 + step),
                w: 32,
                h: 82
            )
        }
    }

    @ViewBuilder
    private func jackpotView(
        _ jackpot: UnityDTJackpotGame
    ) -> some View {
        let elapsed = Date().timeIntervalSince(
            jackpot.phaseStarted
        )
        switch jackpot.phase {
        case .intro:
            if elapsed < 6.25 {
                if elapsed < 3.75 {
                    if elapsed.truncatingRemainder(
                        dividingBy: 0.60
                    ) >= 0.48 {
                        UnityDTSprite(
                            key: game.catalog.spriteDBKey(
                                "givePower"
                            ) ?? "sliced:animations_0",
                            x: 0,
                            y: 0,
                            w: 32,
                            h: 32
                        )
                    }
                } else {
                    UnityDTSprite(
                        key: "digimon:jackpot\(Int(elapsed / 0.55).isMultiple(of: 2) ? "" : "_at")",
                        x: 4,
                        y: 4,
                        w: 24,
                        h: 24,
                        mirrored: true
                    )
                }
            } else {
                miniSummonView(
                    digimon: jackpot.friendly,
                    elapsed: elapsed - 6.25
                )
            }
        case .menu:
            UnityDTSprite(
                key: game.catalog.spriteDBKey(
                    "battle_combatMenu",
                    0
                ) ?? "sliced:menus_90",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        case .showingPattern:
            jackpotPad(
                jackpot,
                yOffset: 0,
                elapsed: elapsed
            )
        case .input:
            jackpotPad(
                jackpot,
                yOffset: 4,
                elapsed: elapsed
            )
            UnityDTLabel(
                "TIME",
                x: 1,
                y: 1,
                w: 18,
                h: 5,
                size: 2.8
            )
            UnityDTLabel(
                "\(max(0, 12 - Int(elapsed)))",
                x: 22,
                y: 1,
                w: 9,
                h: 5,
                size: 2.8,
                alignment: .trailing
            )
        case .result:
            if jackpot.resultCategory < 2 {
                UnityDTSprite(
                    key: "digimon:jackpot_cr",
                    x: 4,
                    y: 4,
                    w: 24,
                    h: 24
                )
            } else {
                UnityDTSprite(
                    key: game.catalog.spriteDBKey(
                        "battle_explosion",
                        Int(elapsed / 0.25) % 2
                    ) ?? "sliced:animations_53",
                    x: 4,
                    y: 4,
                    w: 24,
                    h: 24
                )
            }
            UnityDTLabel(
                jackpot.resultText,
                x: 0,
                y: 27,
                w: 32,
                h: 4,
                size: 2.2
            )
        }
    }

    @ViewBuilder
    private func jackpotPad(
        _ jackpot: UnityDTJackpotGame,
        yOffset: Double,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: game.catalog.spriteDBKey("jackpot_pad")
                ?? "sliced:misc_34",
            x: 4,
            y: 4 + yOffset,
            w: 24,
            h: 24
        )

        let patternStart = 0.75
        let patternEnd = patternStart
            + Double(jackpot.pattern.count) * jackpot.delay
        let activeKey: Int? = {
            if jackpot.phase == .showingPattern,
               elapsed >= patternStart,
               elapsed < patternEnd {
                let index = Int(
                    (elapsed - patternStart) / jackpot.delay
                )
                return jackpot.pattern[safe: index]
            }
            if jackpot.phase == .input,
               Date() < jackpot.flashUntil {
                return jackpot.flashKey
            }
            return nil
        }()

        if let activeKey {
            jackpotKey(activeKey, yOffset: yOffset)
        }

        if jackpot.phase == .showingPattern,
           elapsed < 0.75 {
            UnityDTSprite(
                key: game.catalog.spriteDBKey("hourglass")
                    ?? "sliced:animations_63",
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        } else if jackpot.phase == .showingPattern,
                  elapsed >= patternEnd {
            let progress = min(
                64,
                Int(
                    (elapsed - patternEnd)
                        / ((jackpot.delay * 2) / 64)
                ) + 1
            )
            UnityDTPixelRect(
                x: 0,
                y: 0,
                w: 32,
                h: 32,
                color: .black
            )
            UnityDTSprite(
                key: game.catalog.spriteDBKey("loading")
                    ?? "sliced:misc_28",
                x: 0,
                y: Double(-32 + progress),
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func jackpotKey(
        _ key: Int,
        yOffset: Double
    ) -> some View {
        let positions: [(Double, Double, Double, Double)] = [
            (4, 10, 8, 12),
            (20, 10, 8, 12),
            (10, 4, 12, 8),
            (10, 20, 12, 8)
        ]
        let position = positions[safe: key] ?? positions[0]
        UnityDTSprite(
            key: game.catalog.spriteDBKey(
                "jackpot_keys",
                key
            ) ?? "sliced:misc_37",
            x: position.0,
            y: position.1 + yOffset,
            w: position.2,
            h: position.3
        )
    }

    @ViewBuilder
    private func miniSummonView(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 2.4 {
            if Int(elapsed / 0.15).isMultiple(of: 2) {
                UnityDTSprite(
                    key: game.catalog.spriteDBKey(
                        elapsed < 1.2
                            ? "blackScreen"
                            : "givePowerInverted"
                    ) ?? "sliced:animations_0",
                    x: 0,
                    y: 0,
                    w: 32,
                    h: 32
                )
            }
        } else {
            UnityDTSprite(
                key: "digimon:\(digimon)\(elapsed >= 5.9 && elapsed < 6.65 ? "_cr" : "")",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
            if elapsed < 5.9,
               Int((elapsed - 2.4) / 0.20)
                    .isMultiple(of: 2) {
                UnityDTSprite(
                    key: game.catalog.spriteDBKey("givePower")
                        ?? "sliced:animations_0",
                    x: 0,
                    y: 0,
                    w: 32,
                    h: 32
                )
            }
        }
    }

    @ViewBuilder
    private func speedRunnerView(
        _ runner: UnityDTSpeedRunnerGame
    ) -> some View {
        let elapsed = Date().timeIntervalSince(
            runner.phaseStarted
        )
        UnityDTPixelRect(
            x: 6,
            y: 0,
            w: 1,
            h: 32,
            color: .black
        )

        ForEach(runner.activeRows, id: \.index) { row in
            ForEach(0..<3, id: \.self) { lane in
                if (runner.rows[row.index] & (1 << lane)) != 0 {
                    UnityDTSprite(
                        key: game.catalog.spriteDBKey(
                            "speedRunner_rocketAsteroid"
                        ) ?? "sliced:misc_21",
                        x: 7 + Double(lane * 8),
                        y: floor(row.y),
                        w: 7,
                        h: 6
                    )
                }
            }
        }

        if runner.nextRow >= runner.rows.count {
            ForEach(0..<2, id: \.self) { index in
                UnityDTSprite(
                    key: game.catalog.spriteDBKey(
                        "speedRunner_rocketFinish"
                    ) ?? "sliced:misc_23",
                    x: Double(8 + index * 17),
                    y: floor(runner.finishY),
                    w: 6,
                    h: 32
                )
            }
        }

        ForEach(0...runner.currentSpeed, id: \.self) { mark in
            UnityDTSprite(
                key: game.catalog.spriteDBKey(
                    "speedRunner_rocketSpeedMark"
                ) ?? "sliced:misc_22",
                x: 2,
                y: Double(26 - mark * 6),
                w: 3,
                h: 5
            )
        }

        let spawnProgress = min(
            1,
            elapsed
                / (runner.phase == .respawning ? 1.0 : 1.0)
        )
        let rocketY = runner.phase == .spawning
            || runner.phase == .respawning
            ? floor(32 - 8 * spawnProgress)
            : runner.phase == .goal
                ? floor(24 - min(32, elapsed * 21.3))
                : 24
        UnityDTSprite(
            key: game.catalog.spriteDBKey(
                runner.phase == .gameOver
                    ? "speedRunner_rocketExplosion"
                    : "speedRunner_rocket"
            ) ?? "sliced:misc_19",
            x: Double(8 * (runner.rocketLane + 1) - 1),
            y: rocketY,
            w: 8,
            h: 8
        )

        if runner.phase == .spawning
            || runner.phase == .respawning {
            if elapsed >= 1,
               Int((elapsed - 1) / 0.5).isMultiple(of: 2) {
                UnityDTLabel(
                    "START",
                    x: 9,
                    y: 8,
                    w: 23,
                    h: 5,
                    size: 2.8
                )
            }
        } else if runner.phase == .gameOver {
            UnityDTLabel(
                "GAME\nOVER",
                x: 9,
                y: 8,
                w: 23,
                h: 11,
                size: 2.8
            )
        } else if runner.phase == .goal,
                  Int(elapsed / 0.5).isMultiple(of: 2) {
            UnityDTLabel(
                "GOAL!",
                x: 9,
                y: 8,
                w: 23,
                h: 5,
                size: 2.8
            )
        }
    }

    @ViewBuilder
    private func digiHunterView(
        _ hunter: UnityDTDigiHunterGame
    ) -> some View {
        let elapsed = Date().timeIntervalSince(
            hunter.phaseStarted
        )
        if hunter.phase == .intro {
            digiHunterIntro(elapsed: elapsed)
        } else if hunter.phase == .end {
            UnityDTLabel(
                "END",
                x: 6,
                y: 17,
                w: 20,
                h: 5,
                size: 3.2
            )
        } else {
            let remaining = max(
                0,
                60 - Int(
                    Date().timeIntervalSince(hunter.playStarted)
                )
            )
            UnityDTLabel(
                "TIME",
                x: 1,
                y: 0,
                w: 18,
                h: 5,
                size: 2.8
            )
            UnityDTLabel(
                "\(remaining)",
                x: 22,
                y: 0,
                w: 9,
                h: 5,
                size: 2.8,
                alignment: .trailing
            )
            hunterGrid(hunter)
        }
    }

    @ViewBuilder
    private func digiHunterIntro(
        elapsed: TimeInterval
    ) -> some View {
        if elapsed >= 0.5, elapsed < 1.75 {
            let progress = min(
                29,
                Int((elapsed - 0.5) / (1.25 / 29.0)) + 1
            )
            UnityDTPixelRect(
                x: Double(30 - progress),
                y: 0,
                w: Double(1 + progress),
                h: 4,
                color: .black
            )
        } else if elapsed >= 1.75, elapsed < 2.95 {
            if Int((elapsed - 1.75) / 0.2)
                .isMultiple(of: 2) {
                ForEach(0..<3, id: \.self) { index in
                    hunterArrowPair(x: index, y: index)
                }
            }
        } else if elapsed >= 2.95, elapsed < 4.15 {
            let showWhite = Int((elapsed - 2.95) / 0.2)
                .isMultiple(of: 2)
            ForEach(0..<9, id: \.self) { index in
                if (index.isMultiple(of: 2) && !showWhite)
                    || (!index.isMultiple(of: 2) && showWhite) {
                    UnityDTSprite(
                        key: game.catalog.spriteDBKey(
                            "digiHunter_faces",
                            showWhite ? 0 : 1
                        ) ?? "sliced:misc_47",
                        x: Double(5 + (index % 3) * 8),
                        y: Double(8 + (index / 3) * 8),
                        w: 8,
                        h: 8
                    )
                }
            }
        } else if elapsed >= 4.15 {
            hunterArrowPair(x: 0, y: 0)
            if Int((elapsed - 4.15) / 0.5)
                .isMultiple(of: 2) {
                UnityDTLabel(
                    "START",
                    x: 6,
                    y: 17,
                    w: 20,
                    h: 5,
                    size: 3.2
                )
            }
        }
    }

    @ViewBuilder
    private func hunterGrid(
        _ hunter: UnityDTDigiHunterGame
    ) -> some View {
        hunterArrowPair(
            x: hunter.playerX,
            y: hunter.playerY
        )
        ForEach(0..<9, id: \.self) { index in
            let face = hunter.faces[index]
            if face.value != 0 {
                UnityDTSprite(
                    key: face.value == -1
                        ? (game.catalog.spriteDBKey(
                            "digiHunter_explosion"
                        ) ?? "sliced:misc_50")
                        : (game.catalog.spriteDBKey(
                            "digiHunter_faces",
                            face.value - 1
                        ) ?? "sliced:misc_47"),
                    x: Double(5 + (index % 3) * 8),
                    y: Double(8 + (index / 3) * 8),
                    w: 8,
                    h: 8
                )
            }
        }
    }

    @ViewBuilder
    private func hunterArrowPair(
        x: Int,
        y: Int
    ) -> some View {
        UnityDTSprite(
            key: game.catalog.spriteDBKey(
                "digiHunter_arrows",
                0
            ) ?? "sliced:misc_48",
            x: 2,
            y: Double(9 + y * 8),
            w: 3,
            h: 6
        )
        UnityDTSprite(
            key: game.catalog.spriteDBKey(
                "digiHunter_arrows",
                1
            ) ?? "sliced:misc_49",
            x: Double(6 + x * 8),
            y: 5,
            w: 6,
            h: 3
        )
    }

    @ViewBuilder
    private func mazeView(
        _ maze: UnityDTMazeGame
    ) -> some View {
        if maze.phase == .menu {
            if maze.option == 0 {
                UnityDTPixelRect(
                    x: 2,
                    y: 8,
                    w: 28,
                    h: 7,
                    color: .black
                )
            } else {
                UnityDTPixelRect(
                    x: 2,
                    y: 16,
                    w: 28,
                    h: 7,
                    color: .black
                )
            }
            UnityDTLabel(
                maze.option == 0 ? "> START <" : "START",
                x: 2,
                y: 8,
                w: 28,
                h: 7,
                size: 3.0,
                color: maze.option == 0 ? .white : .black
            )
            UnityDTLabel(
                maze.option == 1 ? "> CANCEL <" : "CANCEL",
                x: 2,
                y: 16,
                w: 28,
                h: 7,
                size: 3.0,
                color: maze.option == 1 ? .white : .black
            )
        } else {
            UnityDTMazePixels(
                paths: maze.paths,
                playerX: maze.playerX,
                playerY: maze.playerY,
                showPlayer: (game.frame / 2).isMultiple(of: 2)
                    || maze.phase != .playing
            )
            UnityDTLabel(
                "TIME",
                x: 1,
                y: 1,
                w: 18,
                h: 5,
                size: 2.8
            )
            UnityDTLabel(
                "\(maze.timeRemaining)",
                x: 22,
                y: 1,
                w: 9,
                h: 5,
                size: 2.8,
                alignment: .trailing
            )
            if maze.phase == .defeat {
                UnityDTLabel(
                    "DEFEAT",
                    x: 0,
                    y: 14,
                    w: 32,
                    h: 7,
                    size: 3.0
                )
            } else if maze.phase == .victory {
                UnityDTLabel(
                    "WIN!",
                    x: 0,
                    y: 14,
                    w: 32,
                    h: 7,
                    size: 3.0
                )
            }
        }
    }

    private var campScreen: some View {
        UnityDTSprite(
            key: game.catalog.spriteDBKey(
                "camp",
                (game.frame / 5).isMultiple(of: 2) ? 0 : 1
            ) ?? "sliced:misc_43",
            x: 4,
            y: 4,
            w: 24,
            h: 24
        )
    }

    private var connectScreen: some View {
        UnityDTSprite(
            key: game.catalog.spriteDBKey("mainMenu", 6)
                ?? "sliced:menus_6",
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
    }

    private var battleScreen: some View {
        guard let battle = game.state.battle else {
            return AnyView(characterHome)
        }
        let key: String
        switch battle.screen {
        case .mainMenu:
            key = game.catalog.spriteDBKey("battle_mainMenu", battle.menuIndex) ?? "sliced:menus_75"
        case .ddocks:
            key = game.catalog.spriteDBKey("status_ddock", battle.ddockIndex) ?? "sliced:menus_33"
        case .spiritElements:
            let element = game.battleAvailableSpiritElements()[safe: battle.spiritElementIndex] ?? 0
            key = element < 10 ? (game.catalog.spriteDBKey("elements", element) ?? "sliced:menus_165") : (game.catalog.spriteDBKey("database_spirit_fusion") ?? "sliced:menus_157")
        case .spiritGallery:
            key = game.catalog.spriteDBKey("arrowsSmall") ?? "sliced:menus_18"
        case .digits:
            key = game.catalog.spriteDBKey("arrows") ?? "sliced:menus_16"
        case .combatMenu:
            let selected = battle.availableCombatOptions[safe: battle.combatMenuIndex] ?? 0
            key = game.catalog.spriteDBKey("battle_combatMenu", selected) ?? "sliced:menus_90"
        case .attackMenu:
            key = game.catalog.spriteDBKey("battle_attackMenu", battle.attackIndex) ?? "sliced:menus_105"
        case .regularEvolve:
            key = game.catalog.spriteDBKey("battle_callPoints_chooser") ?? "sliced:menus_114"
        }
        return AnyView(
            ZStack {
                UnityDTSprite(key: key, x: 0, y: 0, w: 32, h: 32)
                if battle.screen == .ddocks {
                    let docked = game.state.ddocks[safe: battle.ddockIndex] ?? ""
                    if !docked.isEmpty {
                        UnityDTSprite(key: "digimon:\(docked)", x: 4, y: 8, w: 24, h: 24)
                    } else {
                        UnityDTSprite(key: game.catalog.spriteDBKey("status_ddockEmpty") ?? "sliced:misc_2", x: 4, y: 8, w: 24, h: 24)
                    }
                }
                if battle.screen == .spiritGallery {
                    let name = game.battleSpiritGallery()[safe: battle.spiritGalleryIndex] ?? "flamemon"
                    UnityDTIdleDigimon(name: name, x: 4, y: 4, w: 24, h: 24)
                }
                if battle.screen == .digits {
                    codeInputScreen(code: battle.codeInput, selectedAscii: battle.codeSelectedAscii, status: battle.codeStatus)
                }
                if battle.screen == .regularEvolve {
                    UnityDTPixelRect(x: 1, y: 27, w: Double(3 * battle.callPointsForEvolution), h: 3, color: .black)
                }
                // Battle.cs DrawScreen paints only the menu sprite for
                // the combat and attack menus — no call-point readout.
            }
        )
    }

    private func codeInputScreen(code: String, selectedAscii: Int, status: Int) -> some View {
        ZStack {
            UnityDTSprite(
                key: status == 1
                    ? (game.catalog.spriteDBKey("digits_ok") ?? "sliced:menus_41")
                    : status == 2
                        ? (game.catalog.spriteDBKey("digits_error") ?? "sliced:menus_42")
                        : (game.catalog.spriteDBKey("arrows") ?? "sliced:menus_16"),
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
            ForEach(0..<5, id: \.self) { i in
                UnityDTPixelRect(
                    x: Double(2 + (6 * i)),
                    y: 25,
                    w: 5,
                    h: 1,
                    color: .black.opacity(i == code.count && status == 0 && (game.frame / 3) % 2 == 0 ? 0.15 : 1)
                )
            }
            if code.count < 5 {
                UnityDTLabel(String(Character(UnicodeScalar(selectedAscii)!)), x: 14, y: 8, w: 6, h: 8, size: 5)
            }
            UnityDTLabel(code, x: 2, y: 17, w: 30, h: 8, size: 4.7)
        }
    }

    private var resultScreen: some View {
        let victory = game.state.battle?.victory ?? false
        let jump = victory ? Double([0, -2, -4, -2, 0, 1][safe: (game.frame / 2) % 6]!) : 0
        let spriteFrame = victory ? ((game.frame / 4) % 2) : 0
        return ZStack {
            UnityDTSprite(key: characterSpriteKey(game.state.playerChar ?? 0, spriteFrame), x: 9, y: 7 + jump, w: 14, h: 20)
            UnityDTLabel(victory ? "WIN!" : game.state.banner, x: 0, y: 2, w: 32, h: 5, size: 3.2)
        }
    }

    private func characterSpriteKey(_ character: Int, _ frame: Int) -> String {
        let fields = ["takuya", "koji", "zoe", "jp", "tommy", "koichi"]
        return game.catalog.spriteDBKey(fields[safe: character] ?? "takuya", frame) ?? "sliced:characters_0"
    }

    private func statusBackgroundKey(_ page: Int) -> String {
        switch page {
        case 0: return game.catalog.spriteDBKey("status_distance") ?? "sliced:menus_30"
        case 1: return game.catalog.spriteDBKey("status_level") ?? "sliced:menus_31"
        case 2: return game.catalog.spriteDBKey("status_victories") ?? "sliced:menus_32"
        case 7:
            // No shipped background for a page the original never had;
            // the blank screen keeps the SCORE strip readable.
            return game.catalog.spriteDBKey("emptySprite") ?? ""
        default: return game.catalog.spriteDBKey("status_ddock", max(0, page - 3)) ?? "sliced:menus_33"
        }
    }
}

/// Phase lengths of `Animations.DisplayTurn`.
///
/// A battle turn is four consecutive Unity coroutines: the player
/// launches, the enemy launches, the two attacks collide, and the loser
/// is destroyed. Each length below is the summed `WaitForSeconds` of the
/// matching coroutine, so watch playback lines up with the original beat
/// for beat. The screen that renders a turn and the code that decides how
/// long to show it both read from here.
private enum UnityDTBattleTiming {
    /// One pixel step of a travelling attack, `0.6f / 16f` in Unity.
    static let attackStep: TimeInterval = 0.6 / 16.0

    /// `Animations.LaunchAttack` total length for one attack value.
    static func launch(_ attack: Int) -> TimeInterval {
        switch attack {
        case 1:
            // 7 crush after-images, then a hold.
            return 0.2 + 0.9 + 1.5
        case 3:
            // A disobeying digimon just turns on the spot, twice.
            return 4 * 0.65
        default:
            return 0.2 + 38 * (1.7 / 32.0) + 0.3
        }
    }

    /// `Animations.AttackCollision` total length, including the 0.6s in
    /// which the two attacks close on the middle of the screen.
    static func collision(
        friendlyAttack: Int,
        enemyAttack: Int,
        winner: Int
    ) -> TimeInterval {
        let pair = [friendlyAttack, enemyAttack].sorted()
        let impact: TimeInterval
        if pair == [0, 1] {
            impact = 16 * attackStep
        } else if pair == [0, 2] {
            impact = 32 * attackStep
        } else if winner == 2 && (pair == [0, 0] || pair == [2, 2]) {
            impact = 0.15
        } else {
            impact = 40 * attackStep
        }
        return 0.6 + impact
    }

    /// `Animations.DestroyLoser` total length. The trailing 2.5s is the
    /// LIFE sign counting the loser's HP down.
    static func destroy(winningAttack: Int) -> TimeInterval {
        let lifeSign: TimeInterval = 2.5
        switch winningAttack {
        case 0:
            return 0.5 + 2.25 + lifeSign
        case 1:
            return 64 * attackStep + 2.25 + lifeSign
        case 2:
            return 64 * 0.05 + lifeSign
        default:
            return lifeSign
        }
    }

    /// 0 when the player's attack won, 1 when the enemy's won, 2 on a tie.
    static func winner(
        playerHPBefore: Int,
        playerHPAfter: Int,
        enemyHPBefore: Int,
        enemyHPAfter: Int
    ) -> Int {
        if enemyHPAfter < enemyHPBefore { return 0 }
        if playerHPAfter < playerHPBefore { return 1 }
        return 2
    }

    static func turn(
        friendlyAttack: Int,
        enemyAttack: Int,
        winner: Int
    ) -> TimeInterval {
        let total = launch(friendlyAttack)
            + launch(enemyAttack)
            + collision(
                friendlyAttack: friendlyAttack,
                enemyAttack: enemyAttack,
                winner: winner
            )
        guard winner != 2 else { return total }
        return total
            + destroy(
                winningAttack: winner == 0 ? friendlyAttack : enemyAttack
            )
    }
}

private struct UnityDTPresentation: Identifiable {
    enum Kind {
        case characterSelection(character: Int)
        case gameStart(character: Int, spirit: String, initial: String)
        case encounter(enemy: String, boss: Bool)
        case summon(digimon: String)
        case regularEvolution(before: String, after: String)
        case spiritEvolution(character: Int, digimon: String)
        case battleTurn(
            friendly: String,
            enemy: String,
            friendlyAttack: Int,
            enemyAttack: Int,
            playerHPBefore: Int,
            playerHPAfter: Int,
            enemyHPBefore: Int,
            enemyHPAfter: Int,
            unlocked: String?,
            character: Int
        )
        case deport(digimon: String)
        case failedEvolution
        case dataStorm(
            character: Int,
            moved: Bool,
            escapeTicks: Int
        )
        case campOpen(character: Int)
        case campClose(character: Int)
        case mapTravel(
            worldSprite: String,
            before: Int,
            after: Int
        )
        case swapDock(
            index: Int,
            oldDigimon: String,
            digimon: String
        )
        case summonUnlock(character: Int, digimon: String)
        case susanoomonEvolution(character: Int)
        case fusionEvolution(character: Int, digimon: String)
        case spendCallPoints(before: Int, after: Int)
        case spiritPower(before: Int, after: Int, spending: Bool)
        case levelUp(before: Int, after: Int)
        case levelDown(before: Int, after: Int)
        case levelUpDigimon(digimon: String)
        case levelDownDigimon(digimon: String)
        case eraseDigimon(digimon: String)
        case unlockDigimon(digimon: String, spiritForm: Bool)
        case receiveSpirit(digimon: String)
        case loseSpirit(spirit: String, enemy: String)
        case changeDistance(before: Int, after: Int)
        case charMood(character: Int, happy: Bool)
        case enemyEscapes(enemy: String, friendly: String)
        case deportSpirit(digimon: String, character: Int)
        case boostSucceed(friendly: String, sacrifice: String)
        case boostFailed(sacrifice: String)
        case awardDistance(score: Int, before: Int, after: Int)
        case displayNewArea(world: Int, area: Int, distance: Int)
        case forcedTravel(
            world: Int,
            areaBefore: Int,
            areaAfter: Int,
            distance: Int
        )
        case destroyBox
        case boxResists(friendly: String)
        case rewardEmpty
        case rewardDistance(punishment: Bool, before: Int, after: Int)
        case rewardSpiritPower(
            punishment: Bool,
            before: Int,
            after: Int
        )
        case rewardCode(digimon: String, code: String)
        case transitionToMap1(
            character: Int,
            world: Int,
            area: Int,
            distance: Int
        )
        case transitionToMap3(
            character: Int,
            enemy: String,
            spirits: [String]
        )
    }

    /// The transcribed encounter scenes run 6.25s / 5.75s. The port
    /// holds each one two seconds longer to name the enemy — an
    /// addition, the original never shows the name.
    static let encounterNameHold: TimeInterval = 2.0
    static let encounterBodyLength: TimeInterval = 6.25
    static let encounterBossBodyLength: TimeInterval = 5.75
    static let encounterLength: TimeInterval = 6.25 + 2.0
    static let encounterBossLength: TimeInterval = 5.75 + 2.0

    /// `Animations.DisplayNewArea` — the tail of both ForcedTravelMap
    /// and TransitionToMap1.
    static let displayNewAreaLength: TimeInterval = 2.25 + 2.5
    /// `Animations.TravelMap` is called with animDuration 3.5 from
    /// ForcedTravelMap, where the map app's own travel uses 1.5.
    static let forcedTravelMapLength: TimeInterval = 3.5

    static func transitionToMap3Length(spirits: Int) -> TimeInterval {
        // Everything except the per-group spirit explosions, which run
        // four spirits at a time.
        let fixed: TimeInterval = 2.5 + 3.5 + 1.0 + 9.0 + 0.35
            + 1.5 + 1.5 + 0.25 + 0.1 + 0.4 + 0.25 + 0.8 + 0.5
        let groups = Int(ceil(Double(max(1, spirits)) / 4.0))
        return fixed + Double(groups) * (0.4 + 4 * 0.2)
    }

    /// Sound cues for a cutscene, as `(offset, clip)` pairs taken from
    /// the `audioMgr` calls in the matching `Animations.cs` coroutine.
    /// An empty clip name means Unity's `StopSound`.
    static func cues(for kind: Kind) -> [(TimeInterval, String)] {
        switch kind {
        case .gameStart:
            return [
                (2.0, "char_happy"),
                (4.0, "char_happy"),
                (6.0, "game_start"),
                (48.78125, "char_happy"),
                (50.78125, "char_happy")
            ]
        case .encounter(_, let boss):
            // EncounterBoss plays on the first flash, EncounterEnemy
            // only once the digimon is revealed.
            return boss
                ? [(0.6, "encounter_boss")]
                : [(3.70, "encounter_regular")]
        case .summon:
            return [(0, "summon_digimon")]
        case .regularEvolution:
            return [(0, "evolve_regular")]
        case .spiritEvolution, .susanoomonEvolution, .fusionEvolution:
            return [(0, "evolve_spirit")]
        case .battleTurn(
            _,
            _,
            let friendlyAttack,
            let enemyAttack,
            let playerHPBefore,
            let playerHPAfter,
            let enemyHPBefore,
            let enemyHPAfter,
            _,
            _
        ):
            var cues: [(TimeInterval, String)] = []
            // Each LaunchAttack fires its own launch clip.
            cues.append((0.2, friendlyAttack == 2
                ? "launch_attack_long"
                : "launch_attack"))
            let secondLaunch = UnityDTBattleTiming.launch(friendlyAttack)
            cues.append((secondLaunch + 0.2, enemyAttack == 2
                ? "launch_attack_long"
                : "launch_attack"))
            // AttackCollision starts the long travel loop.
            let winner = UnityDTBattleTiming.winner(
                playerHPBefore: playerHPBefore,
                playerHPAfter: playerHPAfter,
                enemyHPBefore: enemyHPBefore,
                enemyHPAfter: enemyHPAfter
            )
            let collisionAt = secondLaunch
                + UnityDTBattleTiming.launch(enemyAttack)
            cues.append((collisionAt, "attack_travel_eternal"))

            guard winner != 2 else { return cues }
            // DestroyLoser: the loop is cut, the loser explodes, and the
            // LIFE counter beeps once per value.
            let winningAttack = winner == 0 ? friendlyAttack : enemyAttack
            let destroyAt = collisionAt
                + UnityDTBattleTiming.collision(
                    friendlyAttack: friendlyAttack,
                    enemyAttack: enemyAttack,
                    winner: winner
                )
            cues.append((destroyAt, ""))
            let impact = UnityDTBattleTiming.destroy(
                winningAttack: winningAttack
            ) - 2.5
            if winningAttack == 0 || winningAttack == 1 {
                cues.append((destroyAt + impact - 2.25, "explode"))
            }
            cues.append((destroyAt + impact + 1.0, "button_a"))
            cues.append((destroyAt + impact + 1.75, "button_a"))
            return cues
        case .deport:
            return [(0, "deport_digimon")]
        case .deportSpirit:
            return [(0, "deport_spirit")]
        case .dataStorm:
            return [(0, "digistorm")]
        case .mapTravel:
            return [(0, "map_travel")]
        case .swapDock:
            return [(0, "change_dock"), (3.5, "char_happy")]
        case .unlockDigimon, .levelUpDigimon, .summonUnlock:
            return [(0, "unlock_digimon")]
        case .eraseDigimon:
            return [(0, "lose_digimon")]
        case .levelDownDigimon:
            return [(0, "level_down_digimon")]
        case .receiveSpirit:
            return [(0, "unpleasant_beep")]
        case .loseSpirit:
            return [(0, "attack_travel_eternal")]
        case .levelUp:
            return [(0, "level_up"), (5.0, "button_a"), (6.0, "button_a")]
        case .levelDown:
            return [
                (0, "level_down_alt"),
                (5.0, "button_a"),
                (6.0, "button_a")
            ]
        case .charMood(_, let happy):
            // CharHappy is CharHappyShort twice, each with its own cue.
            return happy
                ? [(0, "char_happy"), (2.0, "char_happy")]
                : [(0, "char_sad"), (1.9, "char_sad")]
        case .changeDistance, .spendCallPoints:
            return [(0, "button_a"), (1.0, "button_a")]
        case .spiritPower(_, _, let spending):
            return spending
                ? [(1.0, "button_a"), (2.0, "button_a")]
                : []
        case .enemyEscapes:
            return [(0, "launch_attack")]
        case .characterSelection:
            return [(0, "button_a")]
        case .failedEvolution:
            return [(0, "digipower_failed")]
        case .campOpen, .campClose:
            return [(0, "button_a")]
        case .boostSucceed:
            return [(0, "digipower_succeed")]
        case .boostFailed:
            return [(0, "digipower_failed")]
        case .awardDistance:
            // One beep as each of the four rows lands, then the happy
            // chirp when the distance ticks down.
            return [
                (0, "button_a"),
                (1.0, "button_a"),
                (2.0, "button_a"),
                (3.0, "button_a"),
                (4.0, "char_happy")
            ]
        case .displayNewArea:
            return []
        case .forcedTravel:
            return [(0, "map_travel")]
        case .destroyBox:
            // StopSound, then the box blows apart.
            return [(0, ""), (0.5, "explode")]
        case .boxResists(_):
            return [
                (0, ""),
                (1.75, "attack_travel_eternal"),
                (4.15, "")
            ]
        case .rewardEmpty:
            return []
        case .rewardDistance(let punishment, _, _),
             .rewardSpiritPower(let punishment, _, _):
            return [
                (0, punishment ? "punishment" : "reward"),
                (5.0, "button_a"),
                (6.0, "button_a")
            ]
        case .rewardCode:
            return [(0, "unlock_code"), (11.0, "button_a")]
        case .transitionToMap1:
            return [(2.7, "unpleasant_beep")]
        case .transitionToMap3(_, _, let spirits):
            var cues: [(TimeInterval, String)] = [(2.5, "steal_all_spirits")]
            // One destroy cue per group of four spirits.
            let explodeStart: TimeInterval = 2.5 + 3.5 + 1.0 + 9.0
                + 0.35 + 1.5 + 1.5 + 0.25
            let groups = Int(ceil(Double(max(1, spirits.count)) / 4.0))
            for group in 0..<groups {
                cues.append(
                    (explodeStart + Double(group) * 1.2 + 0.4,
                     "destroy_spirits")
                )
            }
            return cues
        }
    }

    /// Lengths of the cutscenes above, summed from the matching
    /// coroutine in `Animations.cs`.
    static func length(of kind: Kind) -> TimeInterval {
        switch kind {
        case .deport: return 3.45
        case .spendCallPoints: return 2.0
        case .spiritPower(_, _, let spending): return spending ? 3.0 : 2.2
        case .levelUp, .levelDown: return 5.5
        case .levelUpDigimon: return 6.15
        case .levelDownDigimon: return 6.15
        case .eraseDigimon: return 5.4
        case .unlockDigimon: return 5.15
        case .receiveSpirit: return 4.15
        case .loseSpirit: return 8.35
        case .changeDistance: return 2.0
        case .charMood: return 2.0
        case .enemyEscapes: return 4.0
        case .deportSpirit: return 7.6
        // These are normally enqueued with an explicit duration by
        // presentTransition; the browsers queue them through
        // `record(_:)`, which looks the length up here instead.
        case .encounter(_, let boss):
            return boss ? encounterBossLength : encounterLength
        case .battleTurn(
            _, _,
            let friendlyAttack,
            let enemyAttack,
            let playerHPBefore,
            let playerHPAfter,
            let enemyHPBefore,
            let enemyHPAfter,
            _, _
        ):
            return UnityDTBattleTiming.turn(
                friendlyAttack: friendlyAttack,
                enemyAttack: enemyAttack,
                winner: UnityDTBattleTiming.winner(
                    playerHPBefore: playerHPBefore,
                    playerHPAfter: playerHPAfter,
                    enemyHPBefore: enemyHPBefore,
                    enemyHPAfter: enemyHPAfter
                )
            )
        case .regularEvolution: return 4.8
        case .spiritEvolution: return 20.3
        case .susanoomonEvolution: return 20.0
        case .summon: return 7.20
        case .fusionEvolution: return 20.3
        case .boostSucceed: return 12.1
        case .boostFailed: return 6.7
        case .awardDistance: return 6.0
        case .displayNewArea: return displayNewAreaLength
        case .forcedTravel:
            return forcedTravelMapLength + displayNewAreaLength
        case .destroyBox: return 3.5
        case .boxResists: return 4.15
        case .rewardEmpty: return 2.0
        case .rewardDistance, .rewardSpiritPower: return 7.0
        case .rewardCode: return 14.25
        case .transitionToMap1: return 15.7 + displayNewAreaLength
        case .transitionToMap3(_, _, let spirits):
            return transitionToMap3Length(spirits: spirits.count)
        default: return 0
        }
    }

    let id = UUID()
    let kind: Kind
    let startedAt: Date
    let duration: TimeInterval
}

private struct UnityDTCharacterMotionStage: View, Animatable {
    @EnvironmentObject private var game: UnityDTGameModel
    let character: Int
    let idleFrame: Int
    let event: Bool
    let eventPhase: Int
    let showEyes: Bool
    let defeated: Bool
    let resting: Bool
    var walkProgress: Double
    let walkLeadFrame: Int
    var panX: Double = 0
    var showEventOverlay: Bool = true

    var animatableData: Double {
        get { walkProgress }
        set { walkProgress = newValue }
    }

    var body: some View {
        let fields = [
            "takuya", "koji", "zoe",
            "jp", "tommy", "koichi"
        ]
        let step = min(
            4,
            max(0, Int(floor(walkProgress * 5)))
        )
        let walking = walkProgress < 0.999
        // PlayerCharacter.UpdateSprite tests defeated before anything
        // else: a beaten character just slumps, it does not walk or
        // react to the pending event.
        // Standing about for more than five seconds and the character
        // sits down; frame 7 is the game's own slumped pose, which is
        // also what a defeated character uses.
        let frame = defeated
            ? 7
            : event
            ? (eventPhase.isMultiple(of: 2) ? 0 : 8)
            : resting && !walking
            ? 7
            : walking
                ? ((step + walkLeadFrame).isMultiple(of: 2)
                    ? 4
                    : 5)
                : idleFrame
        let field = fields[safe: character] ?? "takuya"
        let spriteKey = game.catalog.spriteDBKey(field, frame)
            ?? "sliced:characters_0"
        let spriteX = panX - 1.0
        let spriteY = -1.0
        let spriteSize = 34.0

        return ZStack {
            UnityDTSprite(
                key: spriteKey,
                x: spriteX,
                y: spriteY,
                w: spriteSize,
                h: spriteSize
            )

            if defeated {
                // PAFlashDefeatedEffect: 0.5s on, 0.5s off. Unity builds
                // this layer as a 6x7 badge at (1,1), not a full-screen
                // overlay like the event and eyes layers.
                if (eventPhase / 2).isMultiple(of: 2) {
                    UnityDTSprite(
                        key: game.catalog.spriteDBKey("defeatedSymbol")
                            ?? "sliced:misc_45",
                        x: 1 + panX,
                        y: 1,
                        w: 6,
                        h: 7
                    )
                }
            } else if event,
               showEventOverlay,
               eventPhase.isMultiple(of: 2) {
                UnityDTSprite(
                    key: game.catalog.spriteDBKey("triggerEvent")
                        ?? "sliced:animations_6",
                    x: panX,
                    y: 0,
                    w: 32,
                    h: 32
                )
            } else if showEyes && !walking {
                UnityDTSprite(
                    key: game.catalog.spriteDBKey(
                        "eyes",
                        (eventPhase / 2) % 2
                    ) ?? "sliced:animations_7",
                    x: panX,
                    y: 0,
                    w: 32,
                    h: 32
                )
            }
        }
    }
}

private struct UnityDTAnimationStage: View, Animatable {
    @EnvironmentObject private var game: UnityDTGameModel
    let presentation: UnityDTPresentation
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let elapsed = min(
            presentation.duration,
            max(0, presentation.duration * progress)
        )

        return ZStack {
            UnityDTLCDColor.background
            animationScene(elapsed: elapsed)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func animationScene(elapsed: TimeInterval) -> some View {
        switch presentation.kind {
        case .characterSelection(let character):
            characterSelectionScene(
                character: character,
                elapsed: elapsed
            )

        case .gameStart(let character, let spirit, let initial):
            gameStartScene(
                character: character,
                spirit: spirit,
                initial: initial,
                elapsed: elapsed
            )

        case .encounter(let enemy, let boss):
            encounterScene(
                enemy: enemy,
                boss: boss,
                elapsed: elapsed
            )

        case .summon(let digimon):
            summonScene(digimon: digimon, elapsed: elapsed)

        case .regularEvolution(let before, let after):
            regularEvolutionScene(
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .spiritEvolution(let character, let digimon):
            spiritEvolutionScene(
                character: character,
                digimon: digimon,
                elapsed: elapsed
            )

        case .battleTurn(
            let friendly,
            let enemy,
            let friendlyAttack,
            let enemyAttack,
            let playerHPBefore,
            let playerHPAfter,
            let enemyHPBefore,
            let enemyHPAfter,
            let unlocked,
            let character
        ):
            if elapsed < 9.5 || unlocked == nil {
                battleTurnScene(
                    friendly: friendly,
                    enemy: enemy,
                    friendlyAttack: friendlyAttack,
                    enemyAttack: enemyAttack,
                    playerHPBefore: playerHPBefore,
                    playerHPAfter: playerHPAfter,
                    enemyHPBefore: enemyHPBefore,
                    enemyHPAfter: enemyHPAfter,
                    elapsed: elapsed
                )
            } else if let unlocked,
                      elapsed < 15.65 {
                unlockScene(
                    digimon: unlocked,
                    useSpiritForm: game.catalog
                        .digimonByName[unlocked]?.stage == 6,
                    elapsed: elapsed - 9.5
                )
            } else {
                fullCharacter(
                    character,
                    frame: Int((elapsed - 15.65) / 0.30)
                        .isMultiple(of: 2) ? 0 : 6
                )
            }

        case .deport(let digimon):
            deportScene(digimon: digimon, elapsed: elapsed)

        case .failedEvolution:
            failedEvolutionScene(elapsed: elapsed)

        case .boostSucceed(let friendly, let sacrifice):
            boostSucceedScene(
                friendly: friendly,
                sacrifice: sacrifice,
                elapsed: elapsed
            )

        case .boostFailed(let sacrifice):
            boostFailedScene(sacrifice: sacrifice, elapsed: elapsed)

        case .fusionEvolution(let character, let digimon):
            fusionEvolutionScene(
                character: character,
                digimon: digimon,
                elapsed: elapsed
            )

        case .awardDistance(let score, let before, let after):
            awardDistanceScene(
                score: score,
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .displayNewArea(let world, let area, let distance):
            displayNewAreaScene(
                world: world,
                area: area,
                distance: distance,
                elapsed: elapsed
            )

        case .forcedTravel(
            let world,
            let areaBefore,
            let areaAfter,
            let distance
        ):
            forcedTravelScene(
                world: world,
                areaBefore: areaBefore,
                areaAfter: areaAfter,
                distance: distance,
                elapsed: elapsed
            )

        case .destroyBox:
            destroyBoxScene(elapsed: elapsed)

        case .boxResists(let friendly):
            boxResistsScene(friendly: friendly, elapsed: elapsed)

        case .rewardEmpty:
            UnityDTSprite(
                key: spriteDB("status_ddockEmpty"),
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )

        case .rewardDistance(let punishment, let before, let after):
            rewardPanelScene(
                // rewards[2] is the distance-up icon, [1] distance-down;
                // a punishment pushes the distance up.
                iconField: "rewards",
                iconIndex: punishment ? 2 : 1,
                caption: "DISTANCE",
                captionX: 0,
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .rewardSpiritPower(_, let before, let after):
            rewardPanelScene(
                iconField: "rewards",
                iconIndex: 3,
                caption: "SPIRITS",
                captionX: 1,
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .rewardCode(let digimon, let code):
            rewardCodeScene(
                digimon: digimon,
                code: code,
                elapsed: elapsed
            )

        case .transitionToMap1(
            let character,
            let world,
            let area,
            let distance
        ):
            transitionToMap1Scene(
                character: character,
                world: world,
                area: area,
                distance: distance,
                elapsed: elapsed
            )

        case .transitionToMap3(
            let character,
            let enemy,
            let spirits
        ):
            transitionToMap3Scene(
                character: character,
                enemy: enemy,
                spirits: spirits,
                elapsed: elapsed
            )

        case .dataStorm(
            let character,
            let moved,
            let escapeTicks
        ):
            dataStormScene(
                character: character,
                moved: moved,
                escapeTicks: escapeTicks,
                elapsed: elapsed
            )

        case .campOpen(let character):
            campOpenScene(character: character, elapsed: elapsed)

        case .campClose(let character):
            campCloseScene(character: character, elapsed: elapsed)

        case .mapTravel(
            let worldSprite,
            let before,
            let after
        ):
            mapTravelScene(
                worldSprite: worldSprite,
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .swapDock(let index, let oldDigimon, let digimon):
            swapDockScene(
                index: index,
                oldDigimon: oldDigimon,
                digimon: digimon,
                elapsed: elapsed
            )

        case .summonUnlock(let character, let digimon):
            summonUnlockScene(
                character: character,
                digimon: digimon,
                elapsed: elapsed
            )

        case .susanoomonEvolution(let character):
            susanoomonEvolutionScene(
                character: character,
                elapsed: elapsed
            )

        case .spendCallPoints(let before, let after):
            spendCallPointsScene(
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .spiritPower(let before, let after, let spending):
            spiritPowerScene(
                before: before,
                after: after,
                spending: spending,
                elapsed: elapsed
            )

        case .levelUp(let before, let after):
            levelChangeScene(
                before: before,
                after: after,
                rising: true,
                elapsed: elapsed
            )

        case .levelDown(let before, let after):
            levelChangeScene(
                before: before,
                after: after,
                rising: false,
                elapsed: elapsed
            )

        case .levelUpDigimon(let digimon):
            levelUpDigimonScene(digimon: digimon, elapsed: elapsed)

        case .levelDownDigimon(let digimon):
            levelDownDigimonScene(digimon: digimon, elapsed: elapsed)

        case .eraseDigimon(let digimon):
            eraseDigimonScene(digimon: digimon, elapsed: elapsed)

        case .unlockDigimon(let digimon, let spiritForm):
            unlockDigimonScene(
                digimon: digimon,
                spiritForm: spiritForm,
                elapsed: elapsed
            )

        case .receiveSpirit(let digimon):
            receiveSpiritScene(digimon: digimon, elapsed: elapsed)

        case .loseSpirit(let spirit, let enemy):
            loseSpiritScene(
                spirit: spirit,
                enemy: enemy,
                elapsed: elapsed
            )

        case .changeDistance(let before, let after):
            statSignScene(
                caption: "DISTANCE",
                before: before,
                after: after,
                elapsed: elapsed
            )

        case .charMood(let character, let happy):
            charMoodScene(
                character: character,
                happy: happy,
                elapsed: elapsed
            )

        case .enemyEscapes(let enemy, let friendly):
            enemyEscapesScene(
                enemy: enemy,
                friendly: friendly,
                elapsed: elapsed
            )

        case .deportSpirit(let digimon, let character):
            deportSpiritScene(
                digimon: digimon,
                character: character,
                elapsed: elapsed
            )
        }
    }

    // MARK: - Reward and status cutscenes
    //
    // Each of these is a step-for-step transcription of the matching
    // coroutine in `Animations.cs`.

    /// `Animations.SpendCallPoints`: the call-point bar loses the points
    /// the summon cost.
    @ViewBuilder
    private func spendCallPointsScene(
        before: Int,
        after: Int,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: spriteDB("battle_callPoints_screen"),
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
        let shown = elapsed < 1.0 ? before : after
        ForEach(0..<max(0, shown), id: \.self) { index in
            UnityDTPixelRect(
                x: Double(1 + 3 * index),
                y: 25,
                w: 2,
                h: 5,
                color: .black
            )
        }
    }

    /// The spirit power reading for a given moment, or nil while the
    /// counter has not appeared yet.
    private func spiritPowerAmount(
        before: Int,
        after: Int,
        spending: Bool,
        elapsed: TimeInterval
    ) -> Int? {
        if spending {
            guard elapsed >= 1.0 else { return nil }
            return elapsed < 2.0 ? before : after
        }
        guard elapsed >= 0.4 else { return nil }
        let ticks = min(
            max(0, after - before),
            Int(max(0, elapsed - 0.6) / 0.4)
        )
        return min(99, before + ticks)
    }

    /// `Animations.PaySpiritPower` / `AWardSpiritPower`: the spirit
    /// power screen flickers while the amount counts to its new value.
    @ViewBuilder
    private func spiritPowerScene(
        before: Int,
        after: Int,
        spending: Bool,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: spriteDB(
                "battle_gainingSP",
                index: Int(elapsed / 0.2) % 2
            ),
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
        // Paying shows the old amount for a beat then the new one;
        // awarding ticks up one point at a time.
        let shown = spiritPowerAmount(
            before: before,
            after: after,
            spending: spending,
            elapsed: elapsed
        )
        if let shown {
            UnityDTPixelRect(x: 0, y: 21, w: 32, h: 11, color: .black)
            UnityDTLabel(
                "\(shown)",
                x: 2,
                y: 24,
                w: 28,
                h: 5,
                size: 2.8,
                alignment: .trailing,
                color: UnityDTLCDColor.background
            )
        }
    }


    /// The ten human spirits, in the order `Animations.SusanoomonEvolution`
    /// lists them: KaiserGreymon's five, then MagnaGarurumon's five.
    private static let susanoomonHumanSpirits = [
        "agunimon", "kazemon", "kumamon", "grumblemon", "arbormon",
        "lobomon", "beetlemon", "loweemon", "mercurymon", "lanamon"
    ]
    private static let susanoomonBeastSpirits = [
        "burninggreymon", "zephyrmon", "korikakumon", "gigasmon",
        "petaldramon", "kendogarurumon", "metalkabuterimon",
        "kaiserleomon", "sephirothmon", "calmaramon"
    ]
    /// Where each small spirit sits while it flashes over the
    /// transcendent form.
    private static let susanoomonSpiritSlots: [(Double, Double)] = [
        (9, 0), (0, 7), (18, 7), (2, 16), (16, 16)
    ]

    /// `Animations.SusanoomonEvolution` — the twenty spirits gather and
    /// fuse. Version 4 of the real D-Tector is the only one that has it.
    @ViewBuilder
    private func susanoomonEvolutionScene(
        character: Int,
        elapsed: TimeInterval
    ) -> some View {
        let charge = 3.2          // shared opening with spirit evolution
        let kaiser = charge + 3.1
        let magna = kaiser + 3.1
        let sweep = magna + 1.0
        let gather = sweep + 6.0
        let curtain = gather + 2.2

        if elapsed < charge {
            let step = segment(
                elapsed,
                [0.5, 0.2, 0.4, 0.2, 0.4, 0.2, 0.4,
                 0.2, 0.3, 0.2, 0.2]
            )
            fullCharacter(character, frame: step >= 7 ? 9 : 0)
            if [1, 3, 5, 7, 9].contains(step) {
                fullSprite("giveMassivePowerInverted")
            }
        } else if elapsed < magna {
            // Each transcendent form blinks, then five of its spirits
            // flash in turn over it.
            let kaiserHalf = elapsed < kaiser
            let local = elapsed - (kaiserHalf ? charge : kaiser)
            let form = kaiserHalf ? "kaisergreymon" : "magnagarurumon"
            let base = kaiserHalf ? 0 : 5
            let step = segment(
                local,
                [0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.15, 0.15]
                    + Array(repeating: 0.0, count: 0)
                    + [0.1, 0.28, 0.1, 0.28, 0.1, 0.28,
                       0.1, 0.28, 0.1, 0.28]
            )
            if step < 8 {
                if step.isMultiple(of: 2) {
                    centeredDigimon(form, spirit: true)
                }
            } else {
                let index = (step - 8) / 2
                if (step - 8).isMultiple(of: 2) {
                    // The gap where the form is hidden and the spirit
                    // has not appeared yet.
                    EmptyView()
                } else {
                    let slot = Self.susanoomonSpiritSlots[
                        min(4, index)
                    ]
                    UnityDTSprite(
                        key: "digimon:"
                            + Self.susanoomonHumanSpirits[
                                base + min(4, index)
                            ] + "_sm",
                        x: slot.0,
                        y: slot.1,
                        w: 14,
                        h: 16
                    )
                }
            }
        } else if elapsed < sweep {
            // The kid rushes up through the screen.
            let local = (elapsed - magna) / 1.0
            UnityDTSprite(
                key: characterKey(character, frame: 0),
                x: 0,
                y: 32 - 72 * local,
                w: 32,
                h: 32
            )
        } else if elapsed < gather {
            // Ten pairs of spirits sweep in from the sides and rise.
            let local = elapsed - sweep
            let pair = min(9, Int(local / 0.6))
            let within = local - Double(pair) * 0.6
            let across = min(1.0, within / 0.24)
            let rise = within <= 0.24
                ? 0.0
                : min(1.0, (within - 0.24) / 0.36)
            let x = 16 * across
            let y = 16 - 24 * rise
            UnityDTSprite(
                key: "digimon:"
                    + Self.susanoomonHumanSpirits[pair] + "_sm",
                x: -14 + x,
                y: y,
                w: 14,
                h: 16
            )
            UnityDTSprite(
                key: "digimon:"
                    + Self.susanoomonBeastSpirits[pair] + "_sm",
                x: 32 - x,
                y: y,
                w: 14,
                h: 16
            )
        } else {
            centeredDigimon(
                "susanoomon",
                attack: elapsed >= curtain && elapsed < curtain + 0.8
            )
            if elapsed < curtain {
                UnityDTSprite(
                    key: game.catalog
                        .spriteDBKey("curtainSpecial", 1)
                        ?? "sliced:animations_34",
                    x: 0,
                    y: 32 - 64 * ((elapsed - gather) / 2.2),
                    w: 32,
                    h: 32
                )
            }
        }
    }

    /// `Animations.LevelUp` / `LevelDown`: the reward background cycles,
    /// the icon rises, then the LEVEL sign counts.
    @ViewBuilder
    private func levelChangeScene(
        before: Int,
        after: Int,
        rising: Bool,
        elapsed: TimeInterval
    ) -> some View {
        // 2 background cycles, 4 blinking frames, 4 more cycles, a 0.5s
        // rise, then two 1s counter beats.
        let cycling = 10 * 4 * 0.125
        if elapsed < cycling {
            let frame = Int(elapsed / 0.125) % 4
            // LevelDown runs the same frames in reverse.
            let index = rising ? frame : [0, 3, 2, 1][frame]
            UnityDTSprite(
                key: spriteDB("rewardBackground", index: index),
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
            // The icon starts blinking after the first two cycles.
            let blinkStart = 2 * 4 * 0.125
            if elapsed >= blinkStart + 4 * 0.125
                || (elapsed >= blinkStart && frame.isMultiple(of: 2)) {
                UnityDTSprite(
                    key: spriteDB("rewards", index: 0),
                    x: 8,
                    y: 8,
                    w: 16,
                    h: 16
                )
            }
        } else if elapsed < cycling + 0.5 {
            let risen = (elapsed - cycling) / 0.5 * 9
            UnityDTSprite(
                key: spriteDB("rewards", index: 0),
                x: 8,
                y: 8 - risen,
                w: 16,
                h: 16
            )
        } else {
            UnityDTSprite(
                key: spriteDB("rewards", index: 0),
                x: 8,
                y: -1,
                w: 16,
                h: 16
            )
            UnityDTLabel(
                "LEVEL",
                x: 0,
                y: 17,
                w: 32,
                h: 5,
                size: 3.2
            )
            UnityDTLabel(
                "\(elapsed < cycling + 1.5 ? before : after)",
                x: 2,
                y: 24,
                w: 29,
                h: 5,
                size: 3.2,
                alignment: .trailing
            )
        }
    }

    /// `Animations.LevelUpDigimon`: power is poured into the digimon,
    /// then into the D-Tector itself.
    @ViewBuilder
    private func levelUpDigimonScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        let step = segment(
            elapsed,
            [
                0.40, 0.15, 0.40, 0.15,
                0.20, 0.15, 0.20, 0.15,
                0.20, 0.15, 0.20, 0.20,
                0.20, 0.20, 0.15, 0.20, 0.15,
                0.30
            ] + Array(repeating: 0.15, count: 10) + [1.0]
        )
        // Steps 0-16 charge the digimon; from 17 the D-Tector is shown.
        if step < 17 {
            centeredDigimon(digimon)
            let lit = [1, 3, 5, 7, 9, 11, 12, 14, 16].contains(step)
            if lit {
                // The burst inverts as the charge builds.
                if step <= 9 {
                    fullSprite(step <= 7 ? "givePower" : "givePowerInverted")
                } else {
                    fullSprite("giveMassivePowerInverted")
                }
            }
        } else {
            fullSprite("dTector")
            if step > 17, step < 28, !step.isMultiple(of: 2) {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    /// `Animations.LevelDownDigimon`: the digimon blinks out and the
    /// massive burst alternates between its two polarities.
    @ViewBuilder
    private func levelDownDigimonScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        let step = segment(
            elapsed,
            [
                0.20, 0.15, 0.20, 0.15,
                0.15, 0.15, 0.15, 0.15
            ]
            + [0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.20, 0.20]
            + [0.40, 0.20, 0.20]
            + [0.60, 0.20, 0.20, 0.30]
            + [0.15, 0.15, 0.15, 0.15, 0.50]
        )
        // The digimon is hidden on the blink-out steps.
        let hidden = [1, 3, 5, 7, 24, 26].contains(step)
        if !hidden {
            centeredDigimon(digimon)
        }
        // Burst steps: pairs of (massive, massive inverted).
        let massive = [8, 11, 14, 18, 21]
        let inverted = [9, 12, 15, 19, 22]
        if massive.contains(step) {
            fullSprite("giveMassivePower")
        } else if inverted.contains(step) {
            fullSprite("giveMassivePowerInverted")
        }
    }

    /// `Animations.EraseDigimon`: the digimon flickers and is wiped out.
    @ViewBuilder
    private func eraseDigimonScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        let step = segment(
            elapsed,
            [0.2, 1.0, 0.05, 0.9, 0.05]
            + [0.3, 0.1, 0.3, 0.1, 0.3, 0.1, 0.3, 0.1, 0.3, 0.1]
            + [0.3, 0.4]
        )
        // Visible during the long hold and on each brief flash back.
        let visible = step == 1 || step == 2 || step == 3
            || [6, 8, 10, 12, 14].contains(step)
        if visible {
            centeredDigimon(digimon)
        }
        if [2, 4, 15].contains(step) {
            fullSprite("givePower")
        }
    }

    /// `Animations.UnlockDigimon`: a curtain wipes the digimon up and
    /// off, then the D-Tector flashes.
    @ViewBuilder
    private func unlockDigimonScene(
        digimon: String,
        spiritForm: Bool,
        elapsed: TimeInterval
    ) -> some View {
        let curtainStart = 0.15
        let firstWipe = curtainStart + 1.5
        let secondWipe = firstWipe + 1.5
        let hold = secondWipe + 0.75

        if elapsed < hold {
            let progress = max(0, elapsed - curtainStart) / 1.5
            // The curtain rises from below; after it covers the screen
            // it carries the digimon up with it.
            let curtainY = 32 - 32 * min(2, progress)
            let digimonY = elapsed < firstWipe
                ? 4.0
                : 4 - 32 * ((elapsed - firstWipe) / 1.5)
            centeredDigimon(digimon, spirit: spiritForm)
                .offset(y: 0)
                .hidden()
            UnityDTSprite(
                key: "digimon:\(digimon)\(spiritForm ? "_sp" : "")",
                x: 4,
                y: digimonY,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: curtainY,
                w: 32,
                h: 32
            )
        } else {
            fullSprite("dTector")
            let local = elapsed - hold - 0.30
            if local >= 0, Int(local / 0.15).isMultiple(of: 2),
               local < 1.5 {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    /// `Animations.ReceiveSpirit`: the spirit drops onto a platform and
    /// turns to face the player.
    @ViewBuilder
    private func receiveSpiritScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTPixelRect(x: 3, y: 29, w: 26, h: 1, color: .black)
        let fallStart = 0.15
        let fallen = min(
            28.0,
            max(0, elapsed - fallStart) / (2.5 / 28)
        )
        UnityDTSprite(
            key: "digimon:\(digimon)_sp",
            x: 4,
            y: -24 + fallen,
            w: 24,
            h: 24,
            // It lands facing away and turns around after 0.75s.
            mirrored: elapsed < fallStart + 2.5 + 0.75
        )
    }

    /// `Animations.LoseSpirit`: the enemy drags the spirit away with the
    /// attractor beam, then leaps off screen.
    @ViewBuilder
    private func loseSpiritScene(
        spirit: String,
        enemy: String,
        elapsed: TimeInterval
    ) -> some View {
        let tick = 2.0 / 32.0
        let reach = 12 * tick
        let regrab = reach + 8 * tick
        let drag = regrab + 32 * tick
        let haul = drag + 42 * tick
        let pause = haul + 0.75

        if elapsed < pause {
            if elapsed < reach || elapsed >= regrab {
                UnityDTSprite(
                    key: "digimon:\(enemy)",
                    x: 0,
                    y: 4,
                    w: 24,
                    h: 24,
                    mirrored: true
                )
            }
            if elapsed >= reach {
                let pulled = elapsed < drag
                    ? -(elapsed - regrab) / tick
                    : -32 + 40 + 28 - (elapsed - drag) / tick
                UnityDTSprite(
                    key: "digimon:\(spirit)_sp",
                    x: 8 + pulled,
                    y: 4,
                    w: 24,
                    h: 24
                )
            }
            let beamX = elapsed < reach
                ? 20 + elapsed / tick
                : 20
            UnityDTSprite(
                key: spriteDB("stealSpiritAttractor"),
                x: min(31, beamX),
                y: 4,
                w: 3,
                h: 24
            )
        } else {
            let leapt = min(32.0, (elapsed - pause) / (0.6 / 16) * 2)
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: 0,
                y: 4 - leapt,
                w: 24,
                h: 24,
                mirrored: true
            )
        }
    }

    /// `Animations.ChangeDistance`: the caption is the pre-rendered
    /// 32x5 `animDistance` strip, not text — spelling it out in the
    /// regular font would be 40px wide and run off both edges.
    @ViewBuilder
    private func statSignScene(
        caption: String,
        before: Int,
        after: Int,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: spriteDB("animDistance"),
            x: 0,
            y: 17,
            w: 32,
            h: 5
        )
        UnityDTLabel(
            "\(elapsed < 1.0 ? before : after)",
            x: 2,
            y: 24,
            w: 29,
            h: 5,
            size: 3.2,
            alignment: .trailing
        )
    }

    /// `Animations.CharHappy` / `CharSad`: the character alternates
    /// between its idle and mood sprite, twice over.
    private func charMoodScene(
        character: Int,
        happy: Bool,
        elapsed: TimeInterval
    ) -> some View {
        let beat = happy ? 0.5 : 0.475
        let phase = Int(elapsed / beat)
        return fullCharacter(
            character,
            frame: phase.isMultiple(of: 2) ? 0 : (happy ? 6 : 7)
        )
    }

    /// `Animations.EnemyEscapes`: the enemy hops away while the player's
    /// digimon watches.
    @ViewBuilder
    private func enemyEscapesScene(
        enemy: String,
        friendly: String,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: "digimon:\(friendly)",
            x: 4,
            y: 4,
            w: 24,
            h: 24
        )
        if elapsed >= 1.0 {
            let fled = (elapsed - 1.0) / 3.0 * 40
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: 4 + fled,
                y: 4 - (Int(elapsed * 6).isMultiple(of: 2) ? 2 : 0),
                w: 24,
                h: 24,
                mirrored: true
            )
        }
    }

    /// `Animations.DeportSpirit`: the digimon splits apart vertically,
    /// then the character reappears and powers down.
    @ViewBuilder
    private func deportSpiritScene(
        digimon: String,
        character: Int,
        elapsed: TimeInterval
    ) -> some View {
        let splitStart = 0.25
        let splitEnd = splitStart + 1.75
        let blinkEnd = splitEnd + 3 * 0.4 + 0.3

        if elapsed < splitEnd {
            let apart = max(0, elapsed - splitStart) / (1.75 / 16)
            UnityDTSprite(
                key: "digimon:\(digimon)",
                x: 4,
                y: 4 - apart,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: "digimon:\(digimon)",
                x: 4,
                y: 4 + apart,
                w: 24,
                h: 24
            )
        } else if elapsed < blinkEnd {
            let local = elapsed - splitEnd
            if local.truncatingRemainder(dividingBy: 0.4) < 0.1 {
                UnityDTSprite(
                    key: "digimon:\(digimon)",
                    x: 4,
                    y: -12,
                    w: 24,
                    h: 24
                )
                UnityDTSprite(
                    key: "digimon:\(digimon)",
                    x: 4,
                    y: 20,
                    w: 24,
                    h: 24
                )
            }
        } else {
            let local = elapsed - blinkEnd
            // The character appears on the third flash, then switches
            // to the final power-down pose after the long last pulse.
            if local >= 0.8 {
                fullCharacter(
                    character,
                    frame: local >= 3.2 ? 9 : 0
                )
            }
            let flashWindows: [ClosedRange<TimeInterval>] = [
                0.0...0.1,
                0.4...0.5,
                0.8...0.9,
                1.4...1.5,
                2.5...3.2
            ]
            if flashWindows.contains(where: { $0.contains(local) }) {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    @ViewBuilder
    private func characterSelectionScene(
        character: Int,
        elapsed: TimeInterval
    ) -> some View {
        UnityDTSprite(
            key: characterKey(character, frame: 0),
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )

        if elapsed < 0.8 {
            if elapsed.truncatingRemainder(
                dividingBy: 0.4
            ) < 0.15 {
                blackScreen
            }
        } else if elapsed < 2.0 {
            if (elapsed - 0.8).truncatingRemainder(
                dividingBy: 0.4
            ) < 0.15 {
                fullSprite("curtain")
            }
        } else if elapsed < 4.0 {
            let step = min(
                32,
                Int((elapsed - 2.0) / (2.0 / 32.0)) + 1
            )
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: -Double(step),
                w: 32,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func gameStartScene(
        character: Int,
        spirit: String,
        initial: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 2.0 {
            let step = min(
                32,
                Int(elapsed / (2.0 / 32.0)) + 1
            )
            let frame = ((step - 1) / 2).isMultiple(of: 2)
                ? 4
                : 5
            UnityDTSprite(
                key: characterKey(character, frame: frame),
                x: Double(32 - step),
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < 6.0 {
            let frame = Int((elapsed - 2.0) / 0.5)
                .isMultiple(of: 2) ? 0 : 6
            fullCharacter(character, frame: frame)
        } else if elapsed < 17.5 {
            sourceOpeningTrain(elapsed: elapsed - 6.0)
        } else if elapsed < 19.5 {
            let step = min(
                32,
                Int(
                    (elapsed - 17.5)
                        / (2.0 / 32.0)
                ) + 1
            )
            let frame = ((step - 1) / 2)
                .isMultiple(of: 2) ? 4 : 5
            UnityDTSprite(
                key: characterKey(character, frame: frame),
                x: Double(32 - step),
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < 20.0 {
            fullCharacter(character, frame: 0)
            UnityDTSprite(
                key: spriteDB("battle_disobey"),
                x: 1,
                y: 1,
                w: 3,
                h: 9
            )
        } else if elapsed < 20.4 {
            EmptyView()
        } else if elapsed < 24.7 {
            sourceOpeningEnemyAttack(
                enemy: initial,
                elapsed: elapsed - 20.4
            )
        } else if elapsed < 28.15 {
            sourceOpeningSpiritInterception(
                spirit: spirit,
                enemy: initial,
                elapsed: elapsed - 24.7
            )
        } else if elapsed < 40.0 {
            sourceOpeningSpiritCounterattack(
                character: character,
                spirit: spirit,
                enemy: initial,
                elapsed: elapsed - 28.15
            )
        } else {
            sourceOpeningFinale(
                character: character,
                enemy: initial,
                elapsed: elapsed - 40.0
            )
        }
    }

    @ViewBuilder
    private func sourceOpeningTrain(
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 4.2 {
            let steps = min(
                75,
                Int(elapsed / (4.2 / 75.0)) + 1
            )
            UnityDTSprite(
                key: spriteDB("gameStart_clouds"),
                x: -Double((steps + 1) / 2),
                y: 0,
                w: 76,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("gameStart_trailmon"),
                x: Double(32 - steps),
                y: 9,
                w: 118,
                h: 15
            )
        } else if elapsed < 7.6 {
            let steps = min(
                32,
                Int((elapsed - 4.2) / (3.4 / 32.0)) + 1
            )
            UnityDTSprite(
                key: spriteDB("gameStart_clouds"),
                x: -Double(38 + (min(steps, 12) + 1) / 2),
                y: 0,
                w: 76,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("gameStart_trailmon"),
                x: Double(-43 - steps),
                y: 9,
                w: 118,
                h: 15
            )
        } else if elapsed < 10.2 {
            let steps = min(
                11,
                Int((elapsed - 7.6) / (2.6 / 11.0)) + 1
            )
            UnityDTSprite(
                key: spriteDB("gameStart_clouds"),
                x: -44,
                y: 0,
                w: 76,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("gameStart_trailmon"),
                x: Double(-75 - steps),
                y: 9,
                w: 118,
                h: 15
            )
        } else if elapsed < 11.0 {
            UnityDTSprite(
                key: spriteDB("gameStart_clouds"),
                x: -44,
                y: 0,
                w: 76,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("gameStart_trailmon"),
                x: -86,
                y: 9,
                w: 118,
                h: 15
            )
            let step = min(
                2,
                Int((elapsed - 10.2) / 0.4) + 1
            )
            ForEach([7.0, 17.0, 27.0], id: \.self) {
                position in
                UnityDTPixelRect(
                    x: position - Double(step),
                    y: 14,
                    w: Double(step),
                    h: 5,
                    color: .black
                )
            }
        }
    }

    @ViewBuilder
    private func sourceOpeningEnemyAttack(
        enemy: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 0.15 {
            enemySprite(enemy, attack: false)
        } else if elapsed < 0.55 {
            EmptyView()
        } else if elapsed < 0.70 {
            enemySprite(enemy, attack: false)
        } else if elapsed < 1.10 {
            EmptyView()
        } else if elapsed < 2.80 {
            let steps = min(
                38,
                Int((elapsed - 1.10) / (1.7 / 38.0))
            )
            UnityDTSprite(
                key: "digimon:\(enemy)_at",
                x: 1,
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
            UnityDTSprite(
                key: energyKey(for: enemy),
                x: Double(1 + steps),
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
        } else {
            let steps = min(
                32,
                Int((elapsed - 2.80) / (1.5 / 32.0))
            )
            UnityDTSprite(
                key: energyKey(for: enemy),
                x: Double(-24 + steps),
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
        }
    }

    @ViewBuilder
    private func sourceOpeningSpiritInterception(
        spirit: String,
        enemy: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 1.0 {
            let steps = min(
                21,
                Int(elapsed / (1.0 / 21.0)) + 1
            )
            UnityDTClip(x: 8, y: 4, w: 24, h: 24) {
                UnityDTSprite(
                    key: "digimon:\(spirit)_sp",
                    x: 8,
                    y: Double(25 - steps),
                    w: 24,
                    h: 24
                )
                UnityDTSprite(
                    key: spriteDB("gameStart_spiritPlatform"),
                    x: 9,
                    y: 25,
                    w: 22,
                    h: 3
                )
            }
        } else if elapsed < 1.4 {
            UnityDTClip(x: 8, y: 4, w: 24, h: 24) {
                UnityDTSprite(
                    key: "digimon:\(spirit)_sp",
                    x: 8,
                    y: 4,
                    w: 24,
                    h: 24
                )
                UnityDTSprite(
                    key: spriteDB("gameStart_spiritPlatform"),
                    x: 9,
                    y: 25,
                    w: 22,
                    h: 3
                )
            }
            let steps = min(
                8,
                Int((elapsed - 1.0) / (0.4 / 8.0))
            )
            UnityDTSprite(
                key: energyKey(for: enemy),
                x: Double(-24 + steps),
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
        } else if elapsed < 1.8 {
            UnityDTSprite(
                key: spriteDB("battle_attackCollisionSmall"),
                x: 0,
                y: 8,
                w: 7,
                h: 15
            )
            UnityDTSprite(
                key: "digimon:\(spirit)_sp",
                x: 8,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 1.95 {
            UnityDTSprite(
                key: "digimon:\(spirit)_sp",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        } else {
            let steps = min(
                24,
                Int((elapsed - 1.95) / (1.5 / 24.0))
            )
            UnityDTSprite(
                key: "digimon:\(spirit)_sp",
                x: 4,
                y: Double(4 - steps),
                w: 24,
                h: 24
            )
        }
    }

    @ViewBuilder
    private func sourceOpeningSpiritCounterattack(
        character: Int,
        spirit: String,
        enemy: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 2.8 {
            let steps = min(
                30,
                Int(elapsed / (2.8 / 30.0)) + 1
            )
            UnityDTSprite(
                key: "digimon:\(spirit)_sp",
                x: Double(-24 + steps),
                y: 4,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: characterKey(character, frame: 0),
                x: Double(32 - steps),
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < 3.8 {
            UnityDTSprite(
                key: characterKey(character, frame: 0),
                x: 2,
                y: 0,
                w: 32,
                h: 32
            )
            let local = elapsed - 2.8
            if local < 0.25
                || (local >= 0.50 && local < 0.75) {
                UnityDTSprite(
                    key: "digimon:\(spirit)_sp",
                    x: 6,
                    y: 4,
                    w: 24,
                    h: 24,
                    opacity: 1
                )
            }
        } else if elapsed < 4.3 {
            UnityDTSprite(
                key: "digimon:\(spirit)",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 4.6 {
            UnityDTSprite(
                key: "digimon:\(spirit)_at",
                x: 7,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 4.9 {
            UnityDTSprite(
                key: "digimon:\(spirit)",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 5.05 {
            UnityDTSprite(
                key: "digimon:\(spirit)",
                x: 7,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 6.55 {
            let steps = min(
                38,
                Int((elapsed - 5.05) / (1.5 / 38.0))
            )
            UnityDTSprite(
                key: "digimon:\(spirit)_at",
                x: 10,
                y: 4,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: energyKey(for: spirit, boss: true),
                x: Double(10 - steps),
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 7.95 {
            let steps = min(
                32,
                Int((elapsed - 6.55) / (1.4 / 32.0))
            )
            UnityDTSprite(
                key: energyKey(for: spirit, boss: true),
                x: Double(32 - steps),
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 8.35 {
            let steps = min(
                4,
                Int((elapsed - 7.95) / 0.1)
            )
            enemySprite(enemy, attack: false)
            UnityDTSprite(
                key: energyKey(for: spirit, boss: true),
                x: Double(32 - steps),
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 10.35 {
            UnityDTSprite(
                key: spriteDB(
                    "battle_explosion",
                    index: Int((elapsed - 8.35) / 0.5) % 2
                ),
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        } else {
            fullCharacter(character, frame: 0)
            let local = elapsed - 10.35
            if local < 0.30
                || (local >= 0.60 && local < 0.90) {
                UnityDTSprite(
                    key: "digimon:\(spirit)",
                    x: 4,
                    y: 4,
                    w: 24,
                    h: 24
                )
            }
        }
    }

    @ViewBuilder
    private func sourceOpeningFinale(
        character: Int,
        enemy: String,
        elapsed: TimeInterval
    ) -> some View {
        let chaseDuration = 26.0 * (3.3 / 32.0)
        let chaseStart = 0.15
        let chaseEnd = chaseStart + chaseDuration
        if elapsed < chaseStart {
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: -24,
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
            UnityDTSprite(
                key: characterKey(character, frame: 9),
                x: 0,
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < chaseEnd {
            let steps = min(
                26,
                Int(
                    (elapsed - chaseStart)
                        / (3.3 / 32.0)
                ) + 1
            )
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: Double(-24 + steps),
                y: 4,
                w: 24,
                h: 24,
                mirrored: true
            )
            UnityDTSprite(
                key: characterKey(character, frame: 9),
                x: Double(steps),
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < chaseEnd + 0.6 {
            UnityDTSprite(
                key: characterKey(character, frame: 9),
                x: 26,
                y: 0,
                w: 32,
                h: 32
            )
        } else if elapsed < chaseEnd + 1.05 {
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < chaseEnd + 4.45 {
            let local = elapsed - chaseEnd - 1.05
            let steps = min(
                64,
                Int(local / (3.4 / 64.0)) + 1
            )
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: 4,
                y: Double(4 - max(0, steps - 32)),
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: Double(32 - steps),
                w: 32,
                h: 32
            )
        } else if elapsed < chaseEnd + 5.95 {
            fullSprite("dTector")
            let local = elapsed - chaseEnd - 4.45
            if local.truncatingRemainder(
                dividingBy: 0.30
            ) < 0.15 {
                fullSprite("giveMassivePowerInverted")
            }
        } else {
            let local = elapsed - chaseEnd - 5.95
            fullCharacter(
                character,
                frame: Int(local / 0.5)
                    .isMultiple(of: 2) ? 0 : 6
            )
        }
    }

    @ViewBuilder
    private func encounterScene(
        enemy: String,
        boss: Bool,
        elapsed: TimeInterval
    ) -> some View {
        let body = boss
            ? UnityDTPresentation.encounterBossBodyLength
            : UnityDTPresentation.encounterBodyLength
        if elapsed >= body {
            // Name hold. The sign is opaque in its own right, so it
            // erases the sprite behind it rather than tangling with it.
            enemySprite(enemy, attack: true)
            UnityDTScrollingName(
                text: enemy,
                y: 26,
                pixelsPerSecond: 20
            )
        } else if boss {
            // Animations.EncounterBoss: the enemy stays on screen from
            // the fourth flash onwards and the power sprite overlays it.
            let step = segment(
                elapsed,
                [
                    0.5, 0.1, 0.5, 0.1, 0.5, 0.1, 0.5, 0.1,
                    0.25, 0.1, 0.25, 0.1, 0.25, 0.15,
                    0.5, 0.5, 0.5, 0.75
                ]
            )
            let showEnemy = step >= 8 && step != 13
            let showPower = [1, 3, 5, 7, 9, 11].contains(step)
            if showEnemy {
                enemySprite(
                    enemy,
                    attack: step == 15 || step >= 17
                )
            }
            if showPower {
                fullSprite("giveMassivePower")
            }
        } else {
            // Animations.EncounterEnemy: the power sprite and the enemy
            // alternate; they are never on screen at the same time.
            let step = segment(
                elapsed,
                [
                    0.5, 0.1, 0.5, 0.1, 0.5, 0.1, 0.5,
                    0.25, 0.1, 0.25, 0.1, 0.25, 0.1, 0.35,
                    0.35, 0.6, 0.6, 1.0
                ]
            )
            if [1, 3, 5, 7, 8, 10, 12].contains(step) {
                fullSprite("givePower")
            } else if [9, 11, 14, 15, 16, 17].contains(step) {
                enemySprite(enemy, attack: step == 15 || step == 17)
            }
        }
    }

    @ViewBuilder
    private func summonScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        // Animations.SummonDigimon: the screen flashes black, then the
        // inverted power burst, and the digimon fades in behind it.
        let step = segment(
            elapsed,
            Array(repeating: 0.15, count: 23)
                + [0.20, 0.20, 0.15, 0.90, 0.15, 1.25, 0.75, 0.15]
        )

        // The digimon joins the scene once the burst turns black again.
        if step >= 18 {
            centeredDigimon(digimon, crush: step == 29)
        }

        if step < 8 {
            // Plain black screen blinking on and off.
            if !step.isMultiple(of: 2) {
                fullSprite("blackScreen")
            }
        } else if step < 16 {
            fullSprite(
                step.isMultiple(of: 2)
                    ? "givePowerInverted"
                    : "blackScreen"
            )
        } else if step < 24 {
            let white = [17, 19, 21, 23].contains(step)
            fullSprite(white ? "givePower" : "givePowerInverted")
        } else if [25, 27].contains(step) {
            fullSprite("givePower")
        }
    }

    @ViewBuilder
    private func regularEvolutionScene(
        before: String,
        after: String,
        elapsed: TimeInterval
    ) -> some View {
        // Animations.RegularEvolution: two power flashes, then the
        // digimon blinks five times, swapping form on the third blink.
        let step = segment(
            elapsed,
            [0.5, 0.1, 0.5, 0.1, 0.5]
            + Array(repeating: 0.25, count: 10)
            + [0.25, 0.1, 0.25]
        )
        let blinkStart = 5
        let blink = step - blinkStart

        return ZStack {
            // Hidden on the "off" half of each blink (even offsets).
            if step < blinkStart || step >= blinkStart + 10 {
                centeredDigimon(step >= blinkStart ? after : before)
            } else if !blink.isMultiple(of: 2) {
                // The new form appears from the third blink onwards.
                centeredDigimon(blink >= 5 ? after : before)
            }
            if [1, 3, 16].contains(step) {
                fullSprite("givePower")
            }
        }
    }

    @ViewBuilder
    private func spiritEvolutionScene(
        character: Int,
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        // Animations.SpiritEvolution, transcribed step for step: the
        // character charges up, the spirit splits into four and scatters,
        // the character sweeps up off screen, the silhouette flashes
        // against black, and the evolved digimon is revealed behind a
        // rising curtain.
        let step = segment(
            elapsed,
            [0.5]
            + [0.2, 0.4, 0.2, 0.4, 0.2, 0.4]
            + [0.2, 0.3, 0.2, 0.2]
            + [0.15, 0.25, 0.15, 0.25]
            + [0.7, 3.0, 0.3, 1.0, 0.7, 0.5]
            + [0.1, 0.5, 0.1, 0.5, 0.1, 0.5]
            + [0.1, 0.5, 0.1]
            + [0.3, 0.2, 0.3, 0.2, 0.3, 0.2]
            + [0.3, 0.1, 0.5, 0.2, 3.0, 0.6, 0.8, 0.6]
        )
        let stepStart = segmentStart(
            elapsed,
            [0.5]
            + [0.2, 0.4, 0.2, 0.4, 0.2, 0.4]
            + [0.2, 0.3, 0.2, 0.2]
            + [0.15, 0.25, 0.15, 0.25]
            + [0.7, 3.0, 0.3, 1.0, 0.7, 0.5]
            + [0.1, 0.5, 0.1, 0.5, 0.1, 0.5]
            + [0.1, 0.5, 0.1]
            + [0.3, 0.2, 0.3, 0.2, 0.3, 0.2]
            + [0.3, 0.1, 0.5, 0.2, 3.0, 0.6, 0.8, 0.6]
        )
        let local = elapsed - stepStart

        return ZStack {
            // 0-10: the character charges, switching to its evolving
            // pose once the first three bursts are done.
            if step <= 10 {
                fullCharacter(character, frame: step >= 7 ? 9 : 0)
                if [1, 3, 5, 7, 9].contains(step) {
                    fullSprite("giveMassivePowerInverted")
                }
            }

            // 11-15: the spirit blinks into view.
            if [11, 13, 15].contains(step) {
                centeredDigimon(digimon, spirit: true)
            }

            // 16: four copies of the spirit scatter to the edges.
            if step == 16 {
                let travel = min(32.0, local / 3.0 * 32)
                ForEach(0..<4, id: \.self) { index in
                    UnityDTSprite(
                        key: "digimon:\(digimon)_sp",
                        x: index == 0 ? 4 - travel
                            : index == 1 ? 4 + travel : 4,
                        y: index == 2 ? 4 - travel
                            : index == 3 ? 4 + travel : 4,
                        w: 24,
                        h: 24
                    )
                }
            }

            // 18: the character sweeps up through the screen.
            if step == 18 {
                fullCharacter(character, frame: 0)
                    .offset(y: 0)
                    .hidden()
                UnityDTSprite(
                    key: characterKey(character, frame: 0),
                    x: 0,
                    y: 32 - 64 * (local / 1.0),
                    w: 32,
                    h: 32
                )
            }

            // 20-37: everything happens against a black screen.
            if step >= 20, step <= 37 {
                let silhouette = [27, 29, 31, 33, 35, 37].contains(step)
                if silhouette {
                    // The `_bl` sprite is a filled screen with the new
                    // form punched out of it, and Unity draws it on an
                    // opaque background — so it replaces the black
                    // screen instead of stacking on top, and the digimon
                    // reads as a lit cut-out.
                    UnityDTSolidRect(x: 0, y: 0, w: 32, h: 32)
                    UnityDTSprite(
                        key: "digimon:\(digimon)_bl",
                        x: 0,
                        y: 0,
                        w: 32,
                        h: 32
                    )
                } else {
                    fullSprite("blackScreen")
                    if [21, 23, 25].contains(step) {
                        fullSprite("givePower")
                    }
                }
            }

            // 39-43: the reveal, wiped in by the rising curtain.
            if step >= 39 {
                centeredDigimon(digimon, attack: step == 42)
                if step == 40 {
                    UnityDTSprite(
                        key: spriteDB("curtain"),
                        x: 0,
                        y: 32 - 64 * (local / 3.0),
                        w: 32,
                        h: 32
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func battleTurnScene(
        friendly: String,
        enemy: String,
        friendlyAttack: Int,
        enemyAttack: Int,
        playerHPBefore: Int,
        playerHPAfter: Int,
        enemyHPBefore: Int,
        enemyHPAfter: Int,
        elapsed: TimeInterval
    ) -> some View {
        let winner = UnityDTBattleTiming.winner(
            playerHPBefore: playerHPBefore,
            playerHPAfter: playerHPAfter,
            enemyHPBefore: enemyHPBefore,
            enemyHPAfter: enemyHPAfter
        )
        let friendlyLaunch = UnityDTBattleTiming.launch(friendlyAttack)
        let enemyLaunch = UnityDTBattleTiming.launch(enemyAttack)
        let collision = UnityDTBattleTiming.collision(
            friendlyAttack: friendlyAttack,
            enemyAttack: enemyAttack,
            winner: winner
        )
        let collisionStart = friendlyLaunch + enemyLaunch
        let destroyStart = collisionStart + collision

        if elapsed < friendlyLaunch {
            launchScene(
                digimon: friendly,
                attack: friendlyAttack,
                enemySide: false,
                elapsed: elapsed
            )
        } else if elapsed < collisionStart {
            launchScene(
                digimon: enemy,
                attack: enemyAttack,
                enemySide: true,
                elapsed: elapsed - friendlyLaunch
            )
        } else if elapsed < destroyStart || winner == 2 {
            collisionSceneBody(
                friendly: friendly,
                enemy: enemy,
                friendlyAttack: friendlyAttack,
                enemyAttack: enemyAttack,
                winner: winner,
                elapsed: elapsed - collisionStart
            )
        } else {
            let loser = winner == 0 ? enemy : friendly
            destroyScene(
                loser: loser,
                loserIsEnemy: winner == 0,
                winningAttack: winner == 0
                    ? friendlyAttack
                    : enemyAttack,
                winningDigimon: winner == 0 ? friendly : enemy,
                hpBefore: winner == 0 ? enemyHPBefore : playerHPBefore,
                hpAfter: winner == 0 ? enemyHPAfter : playerHPAfter,
                elapsed: elapsed - destroyStart
            )
        }
    }

    /// `Animations.LaunchAttack`: the attacker recoils and its attack
    /// travels off the far side of the screen. The player fires to the
    /// left, the enemy to the right.
    @ViewBuilder
    private func launchScene(
        digimon: String,
        attack: Int,
        enemySide: Bool,
        elapsed: TimeInterval
    ) -> some View {
        let direction: Double = enemySide ? 1 : -1
        let charging = elapsed < 0.2
        // The attacker steps back 3px as it fires.
        let recoil = charging ? 0.0 : -3 * direction

        if attack == 3 {
            // Disobeyed: no attack, the digimon just turns around twice.
            UnityDTSprite(
                key: "digimon:\(digimon)",
                x: 4,
                y: 4,
                w: 24,
                h: 24,
                mirrored: Int(elapsed / 0.65).isMultiple(of: 2)
                    ? enemySide
                    : !enemySide
            )
        } else if attack == 1 {
            // Crush: seven after-images trail toward the target.
            UnityDTSprite(
                key: "digimon:\(digimon)_cr",
                x: 4 + recoil,
                y: 4,
                w: 24,
                h: 24,
                mirrored: enemySide
            )
            if !charging {
                let spawned = min(
                    7,
                    Int((elapsed - 0.2) / (0.9 / 7)) + 1
                )
                // Each after-image is its own opaque box laid over the
                // previous one, so only a slice of each stays visible.
                ForEach(0..<max(0, spawned), id: \.self) { index in
                    let cx = 4 + recoil + direction * Double(4 * index)
                    UnityDTSolidRect(x: cx, y: 4, w: 24, h: 24)
                    UnityDTSprite(
                        key: "digimon:\(digimon)_cr",
                        x: cx,
                        y: 4,
                        w: 24,
                        h: 24,
                        mirrored: enemySide
                    )
                }
            }
        } else {
            // Unity builds the attack sprite FIRST and the attacker
            // SECOND, and neither calls SetTransparent — so both are
            // opaque 24x24 boxes and the attacker, drawn last, hides the
            // attack completely while they overlap. The energy is only
            // ever seen once it has slid out from behind the body, which
            // is why it reads as being thrown from the hand rather than
            // sitting on top of the digimon.
            let travelled = charging
                ? 0
                : min(38.0, (elapsed - 0.2) / (1.7 / 32.0))
            UnityDTSprite(
                key: attackKey(digimon: digimon, attack: attack),
                x: 4 + recoil + direction * travelled,
                y: 4,
                w: 24,
                h: 24,
                mirrored: enemySide
            )
            UnityDTSolidRect(x: 4 + recoil, y: 4, w: 24, h: 24)
            UnityDTSprite(
                key: charging
                    ? "digimon:\(digimon)"
                    : "digimon:\(digimon)_at",
                x: 4 + recoil,
                y: 4,
                w: 24,
                h: 24,
                mirrored: enemySide
            )
        }
    }

    /// `Animations.AttackCollision`: both attacks enter from opposite
    /// sides, meet at the centre, and the winner pushes through while
    /// the loser turns into the collision sprite and disappears.
    @ViewBuilder
    private func collisionSceneBody(
        friendly: String,
        enemy: String,
        friendlyAttack: Int,
        enemyAttack: Int,
        winner: Int,
        elapsed: TimeInterval
    ) -> some View {
        // Both attacks start just outside and close 16px in 0.6s, so
        // they touch exactly at the middle of the screen.
        let approach = min(1.0, elapsed / 0.6)
        let friendlyX = 32 - 16 * approach
        let enemyX = -24 + 16 * approach

        if elapsed < 0.6 {
            if friendlyAttack != 3 {
                UnityDTSprite(
                    key: attackKey(
                        digimon: friendly,
                        attack: friendlyAttack
                    ),
                    x: friendlyX,
                    y: 4,
                    w: 24,
                    h: 24
                )
            }
            if enemyAttack != 3 {
                UnityDTSprite(
                    key: attackKey(digimon: enemy, attack: enemyAttack),
                    x: enemyX,
                    y: 4,
                    w: 24,
                    h: 24,
                    mirrored: true
                )
            }
        } else if winner == 2 {
            // A tie bursts into the wide collision sprite.
            UnityDTSprite(
                key: spriteDB("battle_attackCollisionBig"),
                x: 8,
                y: 0,
                w: 15,
                h: 32
            )
        } else {
            let pushed = (elapsed - 0.6) / UnityDTBattleTiming.attackStep
            let winnerIsPlayer = winner == 0
            let winningKey = attackKey(
                digimon: winnerIsPlayer ? friendly : enemy,
                attack: winnerIsPlayer ? friendlyAttack : enemyAttack
            )
            let winningX = winnerIsPlayer
                ? 16 - pushed
                : -8 + pushed
            // The losing attack becomes the thin collision sprite and
            // is removed three steps later.
            if pushed < 3 {
                UnityDTSprite(
                    key: spriteDB("battle_attackCollision"),
                    x: winnerIsPlayer ? 12.5 : 12.5,
                    y: 4,
                    w: 7,
                    h: 24
                )
            }
            UnityDTSprite(
                key: winningKey,
                x: winningX,
                y: 4,
                w: 24,
                h: 24,
                mirrored: !winnerIsPlayer
            )
        }
    }

    /// `Animations.DestroyLoser`: the loser explodes, then the LIFE sign
    /// counts its HP down from the old value to the new one.
    @ViewBuilder
    private func destroyScene(
        loser: String,
        loserIsEnemy: Bool,
        winningAttack: Int,
        winningDigimon: String,
        hpBefore: Int,
        hpAfter: Int,
        elapsed: TimeInterval
    ) -> some View {
        let impact = UnityDTBattleTiming.destroy(winningAttack: winningAttack) - 2.5
        let direction: Double = loserIsEnemy ? -1 : 1

        if elapsed < impact {
            switch winningAttack {
            case 0:
                if elapsed < 0.5 {
                    UnityDTSprite(
                        key: "digimon:\(loser)",
                        x: 4,
                        y: 4,
                        w: 24,
                        h: 24,
                        mirrored: loserIsEnemy
                    )
                } else {
                    explosionSprite(elapsed - 0.5)
                }
            case 1:
                // The winner's crush sprite sweeps the loser away.
                let travel = 64 * UnityDTBattleTiming.attackStep
                if elapsed < travel {
                    UnityDTSprite(
                        key: "digimon:\(loser)_cr",
                        x: 4 - direction * 32
                            + direction * (elapsed / UnityDTBattleTiming.attackStep),
                        y: 4,
                        w: 24,
                        h: 24,
                        mirrored: loserIsEnemy
                    )
                } else {
                    explosionSprite(elapsed - travel)
                }
            default:
                // Ability: the ability sprite sweeps across the loser.
                // Unity builds it after the loser and leaves it opaque,
                // so it wipes the loser out as it crosses rather than
                // passing through it; the loser is switched off at step
                // 28 and there is no explosion — the sweep is the whole
                // effect.
                let travelled = elapsed / 0.05
                let abilityX = 4 - direction * 32 + direction * travelled
                if travelled < 28 {
                    UnityDTSprite(
                        key: "digimon:\(loser)",
                        x: 4,
                        y: 4,
                        w: 24,
                        h: 24,
                        mirrored: loserIsEnemy
                    )
                }
                UnityDTSolidRect(x: abilityX, y: 4, w: 24, h: 24)
                UnityDTSprite(
                    key: attackKey(
                        digimon: winningDigimon,
                        attack: winningAttack
                    ),
                    x: abilityX,
                    y: 4,
                    w: 24,
                    h: 24,
                    mirrored: !loserIsEnemy
                )
            }
        } else {
            let local = elapsed - impact
            UnityDTSprite(
                key: "digimon:\(loser)",
                x: 4,
                y: 4,
                w: 24,
                h: 24,
                mirrored: loserIsEnemy
            )
            if local >= 0.5 {
                lifeSign(
                    value: local < 1.0
                        ? nil
                        : (local < 1.75 ? hpBefore : hpAfter)
                )
            }
        }
    }

    private func explosionSprite(_ elapsed: TimeInterval) -> some View {
        UnityDTSprite(
            key: spriteDB(
                "battle_explosion",
                index: Int(elapsed / 0.5) % 2
            ),
            x: 4,
            y: 4,
            w: 24,
            h: 24
        )
    }

    /// `ScreenElement.BuildStatSign`: a filled panel across the lower
    /// half of the screen with an inverted caption and value.
    private func lifeSign(value: Int?) -> some View {
        ZStack {
            // The panel is filled with lit LCD cells, so it keeps the
            // pixel grid instead of reading as one solid block.
            UnityDTPixelRect(x: 0, y: 15, w: 32, h: 17, color: .black)
            UnityDTLabel(
                "LIFE",
                x: 2,
                y: 17,
                w: 28,
                h: 5,
                size: 2.8,
                alignment: .leading,
                color: UnityDTLCDColor.background
            )
            if let value {
                UnityDTLabel(
                    "\(value)",
                    x: 2,
                    y: 25,
                    w: 28,
                    h: 5,
                    size: 2.8,
                    alignment: .trailing,
                    color: UnityDTLCDColor.background
                )
            }
        }
    }

    @ViewBuilder
    private func deportScene(
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 1.0 {
            if Int(elapsed / 0.25).isMultiple(of: 2) {
                centeredDigimon(digimon)
            }
        } else {
            let travel = min(32, (elapsed - 1.75) * 21.34)
            ForEach(0..<4, id: \.self) { index in
                UnityDTSprite(
                    key: "digimon:\(digimon)",
                    x: index == 0 ? 4 - travel
                        : index == 1 ? 4 + travel : 4,
                    y: index == 2 ? 4 - travel
                        : index == 3 ? 4 + travel : 4,
                    w: 24,
                    h: 24,
                    opacity: index == 0 ? 1 : 0.55
                )
            }
        }
    }

    @ViewBuilder
    private func dataStormScene(
        character: Int,
        moved: Bool,
        escapeTicks: Int,
        elapsed: TimeInterval
    ) -> some View {
        let escapeDuration = Double(escapeTicks) * 0.1
        let stormFrame = Int(elapsed / 0.2) % 2

        if elapsed < 8.0 {
            stormPair(
                x: 32 - (elapsed * 10),
                frame: stormFrame
            )
        } else if elapsed < 8.5 {
            fullCharacter(character, frame: 2)
            UnityDTSprite(
                key: spriteDB("battle_disobey"),
                x: 26,
                y: 1,
                w: 3,
                h: 9
            )
        } else if elapsed < 8.9 {
            let steps = floor((elapsed - 8.5) / 0.1) + 1
            UnityDTSprite(
                key: characterKey(
                    character,
                    frame: Int(steps).isMultiple(of: 2) ? 4 : 5
                ),
                x: -min(4, steps),
                y: 0,
                w: 32,
                h: 32
            )
            stormPair(x: 32, frame: stormFrame)
        } else {
            let active = elapsed - 8.9
            let initialStormSteps = min(20, floor(active / 0.1))
            let baseStormX = 32 - initialStormSteps
            let afterApproach = max(0, active - 2.0)
            let afterEscape = max(0, afterApproach - escapeDuration)
            let characterFrame = Int(floor(active / 0.1))
                .isMultiple(of: 2) ? 4 : 5

            if moved {
                let finalStormSteps = min(
                    60,
                    floor(afterEscape / 0.1)
                )
                UnityDTSprite(
                    key: characterKey(
                        character,
                        frame: characterFrame
                    ),
                    x: -4,
                    y: 0,
                    w: 32,
                    h: 32
                )
                stormPair(
                    x: baseStormX - finalStormSteps,
                    frame: stormFrame
                )
            } else {
                let retreatSteps = min(
                    30,
                    floor(afterEscape / 0.1)
                )
                UnityDTSprite(
                    key: characterKey(
                        character,
                        frame: characterFrame
                    ),
                    x: -4 - retreatSteps,
                    y: 0,
                    w: 32,
                    h: 32
                )
                stormPair(
                    x: baseStormX + retreatSteps,
                    frame: stormFrame
                )
            }
        }
    }

    @ViewBuilder
    private func campOpenScene(
        character: Int,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 0.2 {
            fullCharacter(character, frame: 0)
        } else if elapsed < 3.2 {
            let local = elapsed - 0.2
            UnityDTSprite(
                key: characterKey(
                    character,
                    frame: Int(local / (3.0 / 32.0))
                        .isMultiple(of: 2) ? 4 : 5
                ),
                x: -min(32, local * (32.0 / 3.0)),
                y: 0,
                w: 32,
                h: 32
            )
        } else {
            let local = min(3.0, elapsed - 3.2)
            UnityDTSprite(
                key: spriteDB("camp", index: 0),
                x: -28 + (local * (32.0 / 3.0)),
                y: 4,
                w: 24,
                h: 24
            )
        }
    }

    @ViewBuilder
    private func campCloseScene(
        character: Int,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 3.0 {
            UnityDTSprite(
                key: spriteDB("camp", index: 0),
                x: 4 - (elapsed * (32.0 / 3.0)),
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < 6.0 {
            let local = elapsed - 3.0
            UnityDTSprite(
                key: characterKey(
                    character,
                    frame: Int(local / (3.0 / 32.0))
                        .isMultiple(of: 2) ? 4 : 5
                ),
                x: -32 + (local * (32.0 / 3.0)),
                y: 0,
                w: 32,
                h: 32,
                mirrored: true
            )
        } else {
            fullCharacter(character, frame: 0)
        }
    }

    @ViewBuilder
    private func mapTravelScene(
        worldSprite: String,
        before: Int,
        after: Int,
        elapsed: TimeInterval
    ) -> some View {
        let midpoint: Int? = {
            switch (before, after) {
            case (0, 2), (2, 0):
                return 1
            case (1, 3), (3, 1):
                return 2
            default:
                return nil
            }
        }()

        if let midpoint {
            if elapsed < 0.75 {
                mapTravelSegment(
                    worldSprite: worldSprite,
                    before: before,
                    after: midpoint,
                    progress: elapsed / 0.75
                )
            } else {
                mapTravelSegment(
                    worldSprite: worldSprite,
                    before: midpoint,
                    after: after,
                    progress: (elapsed - 0.75) / 0.75
                )
            }
        } else {
            mapTravelSegment(
                worldSprite: worldSprite,
                before: before,
                after: after,
                progress: elapsed / 1.5
            )
        }
    }

    @ViewBuilder
    private func mapTravelSegment(
        worldSprite: String,
        before: Int,
        after: Int,
        progress rawProgress: Double
    ) -> some View {
        let progress = min(
            1,
            max(0, floor(rawProgress * 32) / 32)
        )
        let beforePoint = mapPoint(before)
        let afterPoint = mapPoint(after)
        let dx = Double(afterPoint.x - beforePoint.x)
        let dy = Double(afterPoint.y - beforePoint.y)

        UnityDTSprite(
            key: "map:\(worldSprite)_\(before)",
            x: -dx * 32 * progress,
            y: -dy * 32 * progress,
            w: 32,
            h: 32
        )
        UnityDTSprite(
            key: "map:\(worldSprite)_\(after)",
            x: dx * 32 * (1 - progress),
            y: dy * 32 * (1 - progress),
            w: 32,
            h: 32
        )
    }

    @ViewBuilder
    private func swapDockScene(
        index: Int,
        oldDigimon: String,
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 0.75 {
            dockScene(
                index: index,
                digimon: oldDigimon,
                y: 0
            )
        } else if elapsed < 2.25 {
            let travel = (elapsed - 0.75) * (32.0 / 1.5)
            dockScene(
                index: index,
                digimon: oldDigimon,
                y: -travel
            )
            UnityDTSprite(
                key: spriteDB("blackBars"),
                x: 0,
                y: 32 - travel,
                w: 32,
                h: 32
            )
        } else if elapsed < 3.0 {
            fullSprite("blackBars")
        } else if elapsed < 4.5 {
            let travel = (elapsed - 3.0) * (32.0 / 1.5)
            UnityDTSprite(
                key: spriteDB("blackBars"),
                x: 0,
                y: travel,
                w: 32,
                h: 32
            )
            dockScene(
                index: index,
                digimon: digimon,
                y: -32 + travel
            )
        } else if elapsed < 5.0 {
            dockScene(index: index, digimon: digimon, y: 0)
        } else if elapsed < 6.75 {
            dockScene(
                index: index,
                digimon: digimon,
                y: 0,
                crush: true,
                visible: Int((elapsed - 5.0) / 0.175)
                    .isMultiple(of: 2)
            )
        } else {
            dockScene(index: index, digimon: digimon, y: 0)
        }
    }

    @ViewBuilder
    private func summonUnlockScene(
        character: Int,
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 7.15 {
            summonScene(digimon: digimon, elapsed: elapsed)
        } else if elapsed < 13.3 {
            unlockScene(
                digimon: digimon,
                useSpiritForm: false,
                elapsed: elapsed - 7.15
            )
        } else {
            fullCharacter(
                character,
                frame: Int((elapsed - 13.3) / 0.30)
                    .isMultiple(of: 2) ? 0 : 6
            )
        }
    }

    @ViewBuilder
    private func unlockScene(
        digimon: String,
        useSpiritForm: Bool,
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 0.15 {
            centeredDigimon(digimon, spirit: useSpiritForm)
        } else if elapsed < 1.65 {
            centeredDigimon(digimon, spirit: useSpiritForm)
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: 32 - ((elapsed - 0.15) * (32.0 / 1.5)),
                w: 32,
                h: 32
            )
        } else if elapsed < 3.15 {
            let travel = (elapsed - 1.65) * (32.0 / 1.5)
            UnityDTSprite(
                key: "digimon:\(digimon)\(useSpiritForm ? "_sp" : "")",
                x: 4,
                y: 4 - travel,
                w: 24,
                h: 24
            )
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: -travel,
                w: 32,
                h: 32
            )
        } else if elapsed >= 3.9 {
            fullSprite("dTector")
            if elapsed >= 4.2,
               elapsed < 5.7,
               Int((elapsed - 4.2) / 0.15)
                    .isMultiple(of: 2) {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    private func stormPair(
        x: Double,
        frame: Int
    ) -> some View {
        ZStack {
            UnityDTSprite(
                key: spriteDB("digistorm", index: frame),
                x: x,
                y: 0,
                w: 40,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("digistorm", index: frame),
                x: x + 40,
                y: 0,
                w: 40,
                h: 32
            )
        }
    }

    @ViewBuilder
    private func dockScene(
        index: Int,
        digimon: String,
        y: Double,
        crush: Bool = false,
        visible: Bool = true
    ) -> some View {
        UnityDTSprite(
            key: spriteDB("status_ddock", index: index),
            x: 0,
            y: y,
            w: 32,
            h: 32
        )
        if visible {
            if digimon.isEmpty {
                UnityDTSprite(
                    key: spriteDB("status_ddockEmpty"),
                    x: 4,
                    y: 8 + y,
                    w: 24,
                    h: 24
                )
            } else {
                UnityDTSprite(
                    key: "digimon:\(digimon)\(crush ? "_cr" : "")",
                    x: 4,
                    y: 8 + y,
                    w: 24,
                    h: 24
                )
            }
        }
    }

    private func mapPoint(_ map: Int) -> (x: Int, y: Int) {
        switch map {
        case 1: return (0, 1)
        case 2: return (1, 1)
        case 3: return (1, 0)
        default: return (0, 0)
        }
    }

    @ViewBuilder
    private func failedEvolutionScene(elapsed: TimeInterval) -> some View {
        if Int(elapsed / 0.20).isMultiple(of: 2) {
            fullSprite("giveMassivePower")
        } else {
            blackScreen
        }
        UnityDTLabel(
            "FAILED",
            x: 0,
            y: 14,
            w: 32,
            h: 5,
            size: 3.2
        )
    }

    private var blackScreen: some View {
        UnityDTPixelRect(
            x: 0,
            y: 0,
            w: 32,
            h: 32,
            color: .black
        )
    }

    /// `Animations.BoostFailed`: the sacrifice flashes the power symbol
    /// twice, then blinks out with a shrinking rhythm.
    @ViewBuilder
    private func boostFailedScene(
        sacrifice: String,
        elapsed: TimeInterval
    ) -> some View {
        let durations: [TimeInterval] = [
            0.2, 0.2, 0.45, 0.2, 0.2, 0.45, 0.4,
            0.6, 0.45, 0.6, 0.45,
            0.3, 0.1, 0.3, 0.1, 0.3, 0.1, 0.3, 0.1, 0.3, 0.1,
            0.5
        ]
        let step = segment(elapsed, durations)
        let digimonVisible = step <= 6 || step % 2 == 0
        if digimonVisible {
            centeredDigimon(sacrifice)
        }
        if step < 6, step % 3 != 2 {
            fullSprite(step % 3 == 0 ? "givePowerInverted" : "givePower")
        }
    }

    /// `Animations.BoostSucceed`: the same power flash, then a curtain
    /// wipes the sacrifice away and reveals the boosted digimon, with a
    /// decorative pass and a final power flash to close.
    @ViewBuilder
    private func boostSucceedScene(
        friendly: String,
        sacrifice: String,
        elapsed: TimeInterval
    ) -> some View {
        let flashDurations: [TimeInterval] = [
            0.2, 0.2, 0.45, 0.2, 0.2, 0.45, 0.4
        ]
        let flashTotal = flashDurations.reduce(0, +)
        let descentEnd = flashTotal + 3.5
        let revealEnd = descentEnd + 0.5
        let ascentEnd = revealEnd + 3.5
        let holdEnd = ascentEnd + 0.4

        if elapsed < flashTotal {
            let step = segment(elapsed, flashDurations)
            centeredDigimon(sacrifice)
            if step < 6, step % 3 != 2 {
                fullSprite(
                    step % 3 == 0 ? "givePowerInverted" : "givePower"
                )
            }
        } else if elapsed < descentEnd {
            // 64 one-pixel steps from just above the screen to just
            // below it. The curtain is built without SetTransparent, so
            // on the way down it is an opaque background-coloured panel
            // that wipes whatever it passes over — hence the solid rect
            // travelling with it. The sacrifice is switched off exactly
            // when the panel has the screen covered, at step 32.
            let progress = (elapsed - flashTotal) / 3.5
            let curtainY = -32 + 64 * progress
            if progress < 0.5 {
                centeredDigimon(sacrifice)
            }
            UnityDTSolidRect(x: 0, y: curtainY, w: 32, h: 32)
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: curtainY,
                w: 32,
                h: 32
            )
        } else if elapsed < revealEnd {
            centeredDigimon(friendly)
        } else if elapsed < ascentEnd {
            // SetTransparent(true) before the upward pass: the same
            // sparkle field runs back up, this time layered over the
            // boosted digimon instead of wiping it.
            let progress = (elapsed - revealEnd) / 3.5
            centeredDigimon(friendly)
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: 32 - 64 * progress,
                w: 32,
                h: 32
            )
        } else if elapsed < holdEnd {
            centeredDigimon(friendly)
        } else {
            centeredDigimon(friendly)
            let flashSegments: [TimeInterval] = [
                0.1, 0.4, 0.1, 0.4, 0.1, 1.0
            ]
            let step = segment(elapsed - holdEnd, flashSegments)
            if step % 2 == 0 {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    /// `Animations.FusionSpiritEvolution` (20.3s), transcribed step for
    /// step: the character charges, the five human and five animal
    /// spirits of the fusion's half fly in and sweep up, a cover wipes
    /// down to reveal the transcendent spirit, it flashes and rises, the
    /// digimon runs past twice and a curtain wipes up to the reveal.
    @ViewBuilder
    private func fusionEvolutionScene(
        character: Int,
        digimon: String,
        elapsed: TimeInterval
    ) -> some View {
        // Unity hardcodes the two halves; KaiserGreymon takes the fire
        // side, anything else the light side.
        let humans = digimon == "kaisergreymon"
            ? ["agunimon", "kazemon", "kumamon", "grumblemon", "arbormon"]
            : ["lobomon", "beetlemon", "loweemon", "mercurymon", "lanamon"]
        let animals = digimon == "kaisergreymon"
            ? [
                "burninggreymon", "zephyrmon", "korikakumon",
                "gigasmon", "petaldramon"
            ]
            : [
                "kendogarurumon", "metalkabuterimon", "kaiserleomon",
                "sephirothmon", "calmaramon"
            ]

        let chargeSteps: [TimeInterval] = [
            0.5, 0.2, 0.4, 0.2, 0.4, 0.2, 0.4, 0.2, 0.3, 0.2, 0.2
        ]
        let chargeEnd = chargeSteps.reduce(0, +)     // 3.2
        let spiritsEnd = chargeEnd + 3.0
        let revealEnd = spiritsEnd + 3.2
        let flashEnd = revealEnd + 2.1
        let riseEnd = flashEnd + 1.4
        let runOneEnd = riseEnd + 1.0
        let pauseEnd = runOneEnd + 0.7
        let runTwoEnd = pauseEnd + 0.7
        let curtainEnd = runTwoEnd + 3.0
        let holdEnd = curtainEnd + 0.6
        let attackEnd = holdEnd + 0.8

        if elapsed < chargeEnd {
            let step = segment(elapsed, chargeSteps)
            // The character switches to its evolving pose once the
            // three-flash loop is done.
            fullCharacter(character, frame: step < 7 ? 0 : 9)
            if [1, 3, 5, 7, 9].contains(step) {
                fullSprite("giveMassivePowerInverted")
            }
        } else if elapsed < spiritsEnd {
            // Five pairs, 0.6s each: 0.24s sliding together at y=16,
            // then 0.36s sweeping up off the top.
            let local = elapsed - chargeEnd
            let pair = min(4, Int(local / 0.6))
            let within = local - Double(pair) * 0.6
            let slide = min(4.0, floor(within / 0.06))
            let rise = max(0, floor((within - 0.24) / 0.06))
            let y = 16.0 - rise * 4
            UnityDTSprite(
                key: "digimon:\(humans[pair])_sm",
                x: -15 + slide * 4,
                y: y,
                w: 14,
                h: 16
            )
            UnityDTSprite(
                key: "digimon:\(animals[pair])_sm",
                x: 33 - slide * 4,
                y: y,
                w: 14,
                h: 16
            )
        } else if elapsed < revealEnd {
            // A background-coloured cover slides down off the screen,
            // uncovering the transcendent spirit from the top, with the
            // special curtain riding along behind it.
            let tick = floor((elapsed - spiritsEnd) / (3.2 / 32))
            UnityDTSprite(
                key: "digimon:\(digimon)_sp",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
            UnityDTSolidRect(x: 0, y: tick, w: 32, h: 32)
            UnityDTSprite(
                key: spriteDB("curtainSpecial", index: 0),
                x: 0,
                y: -32 + tick,
                w: 32,
                h: 32
            )
            if tick == 14 || tick == 28 {
                fullSprite("giveMassivePowerInverted")
            }
        } else if elapsed < flashEnd {
            // Blinks three times, starting on the "off" half.
            if !Int((elapsed - revealEnd) / 0.35).isMultiple(of: 2) {
                UnityDTSprite(
                    key: "digimon:\(digimon)_sp",
                    x: 4,
                    y: 4,
                    w: 24,
                    h: 24
                )
            }
        } else if elapsed < riseEnd {
            let risen = floor((elapsed - flashEnd) / (1.4 / 32))
            UnityDTSprite(
                key: "digimon:\(digimon)_sp",
                x: 4,
                y: 4 - risen,
                w: 24,
                h: 24
            )
        } else if elapsed < runOneEnd {
            // Charges in from the right, six pixels a tick, straight
            // past and off the left edge.
            let moved = floor((elapsed - riseEnd) / (1.0 / 12)) * 6
            UnityDTSprite(
                key: "digimon:\(digimon)_cr",
                x: 32 - moved,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < pauseEnd {
            // Legitimately empty: it has run off screen and the second
            // pass has not started.
            EmptyView()
        } else if elapsed < runTwoEnd {
            // Second pass is slower and stops dead centre.
            let moved = floor((elapsed - pauseEnd) / (0.7 / 14)) * 2
            UnityDTSprite(
                key: "digimon:\(digimon)_cr",
                x: 32 - moved,
                y: 4,
                w: 24,
                h: 24
            )
        } else if elapsed < curtainEnd {
            centeredDigimon(digimon)
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: 32 - floor((elapsed - runTwoEnd) / (3.0 / 64)),
                w: 32,
                h: 32
            )
        } else if elapsed < holdEnd {
            centeredDigimon(digimon)
        } else if elapsed < attackEnd {
            centeredDigimon(digimon, attack: true)
        } else {
            centeredDigimon(digimon)
        }
    }

    // MARK: - Map and reward scenes

    /// `Animations.AwardDistance`: four rows drop in a second apart —
    /// SCORE, the score, DISTANCE, the distance — then the distance
    /// ticks down to its new value.
    @ViewBuilder
    private func awardDistanceScene(
        score: Int,
        before: Int,
        after: Int,
        elapsed: TimeInterval,
    ) -> some View {
        UnityDTSprite(
            key: spriteDB("games_score"),
            x: 0,
            y: 1,
            w: 32,
            h: 5
        )
        if elapsed >= 1.0 {
            UnityDTLabel(
                "\(score)",
                x: 0,
                y: 9,
                w: 31,
                h: 5,
                size: 3.2,
                alignment: .trailing
            )
        }
        if elapsed >= 2.0 {
            UnityDTSprite(
                key: spriteDB("games_distance"),
                x: 0,
                y: 18,
                w: 32,
                h: 5
            )
        }
        if elapsed >= 3.0 {
            UnityDTLabel(
                "\(elapsed < 4.0 ? before : after)",
                x: 0,
                y: 26,
                w: 31,
                h: 5,
                size: 3.2,
                alignment: .trailing
            )
        }
    }

    /// `Animations.DisplayNewArea`: the world map scrolled to the new
    /// area's quadrant with its name, a blinking marker on the target
    /// and solid markers on everything already cleared, then the
    /// distance panel.
    @ViewBuilder
    private func displayNewAreaScene(
        world: Int,
        area: Int,
        distance: Int,
        elapsed: TimeInterval
    ) -> some View {
        let data = game.catalog.worlds.first { $0.number == world }
        let areaData = data?.areas[safe: area]
        let map = areaData?.map ?? 0
        let point = mapPoint(map)

        UnityDTSprite(
            key: "map:\(data?.worldSprite ?? "frontier_initial")_\(map)",
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
        // Unity puts the caption at the top of maps 0 and 3, at the
        // bottom of 1 and 2, i.e. away from where those quadrants meet.
        // Its TextBox prefab has an opaque LCD-background fill, so it
        // covers the "MAP N" caption baked into the map art rather than
        // letting it bleed through and double up.
        let captionY: Double = (map == 0 || map == 3) ? 1 : 26
        UnityDTSolidRect(x: 2, y: captionY, w: 30, h: 5)
        UnityDTLabel(
            String(format: "area%02d", area + 1),
            x: 2,
            y: captionY,
            w: 30,
            h: 5,
            size: 2.8,
            alignment: .leading
        )
        // Areas already cleared in this quadrant sit as steady dots.
        // NOTE: Unity reads `GetAreaCompleted(0, i)` — world 0 hardcoded
        // — which is a bug in the original; this uses the world being
        // displayed so the markers mean something in every world.
        let completed = game.state.completedAreas[safe: world] ?? []
        ForEach(
            (data?.areas ?? []).filter { $0.map == map },
            id: \.number
        ) { other in
            if completed[safe: other.number] == true {
                UnityDTPixelRect(
                    x: Double(other.coords.x),
                    y: Double(other.coords.y),
                    w: 2,
                    h: 2,
                    color: .black
                )
            }
        }
        if let areaData,
           Int(elapsed / 0.25).isMultiple(of: 2) {
            UnityDTPixelRect(
                x: Double(areaData.coords.x),
                y: Double(areaData.coords.y),
                w: 2,
                h: 2,
                color: .black
            )
        }
        // `point` only exists to keep the quadrant maths beside the
        // sprite lookup; the flattened map art is already per-quadrant.
        let _ = point

        if elapsed >= 2.25 {
            UnityDTSolidRect(x: 0, y: 0, w: 32, h: 32)
            fullSprite("map_distanceScreen")
            UnityDTLabel(
                "\(distance)",
                x: 6,
                y: 25,
                w: 25,
                h: 5,
                size: 3.2,
                alignment: .trailing
            )
        }
    }

    /// `Animations.ForcedTravelMap`: the map slides from the old
    /// quadrant to the new one over 3.5s, then DisplayNewArea.
    @ViewBuilder
    private func forcedTravelScene(
        world: Int,
        areaBefore: Int,
        areaAfter: Int,
        distance: Int,
        elapsed: TimeInterval
    ) -> some View {
        let data = game.catalog.worlds.first { $0.number == world }
        let sprite = data?.worldSprite ?? "frontier_initial"
        let mapBefore = data?.areas[safe: areaBefore]?.map ?? 0
        let mapAfter = data?.areas[safe: areaAfter]?.map ?? 0
        let travel = UnityDTPresentation.forcedTravelMapLength

        if elapsed < travel {
            if mapBefore == mapAfter {
                UnityDTSprite(
                    key: "map:\(sprite)_\(mapBefore)",
                    x: 0,
                    y: 0,
                    w: 32,
                    h: 32
                )
            } else {
                mapTravelScene(
                    worldSprite: sprite,
                    before: mapBefore,
                    after: mapAfter,
                    // mapTravelScene is written against the map app's
                    // 1.5s travel; rescale to Unity's 3.5s here.
                    elapsed: elapsed * (1.5 / travel)
                )
            }
        } else {
            displayNewAreaScene(
                world: world,
                area: areaAfter,
                distance: distance,
                elapsed: elapsed - travel
            )
        }
    }

    /// `Animations.DestroyBox`: the jackpot box blows apart and lands
    /// as its broken sprite.
    @ViewBuilder
    private func destroyBoxScene(elapsed: TimeInterval) -> some View {
        let durations: [TimeInterval] = [
            0.5, 0.5, 0.5, 0.5, 0.5, 0.15, 0.85
        ]
        let step = segment(elapsed, durations)
        switch step {
        case 0:
            centeredDigimon("jackpot")
        case 1, 3:
            UnityDTSprite(
                key: spriteDB("battle_explosion", index: 0),
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        case 2, 4:
            UnityDTSprite(
                key: spriteDB("battle_explosion", index: 1),
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        case 5:
            EmptyView()
        default:
            UnityDTSprite(
                key: "digimon:jackpot_sp",
                x: 4,
                y: 4,
                w: 24,
                h: 24
            )
        }
    }

    /// `Animations.BoxResists`: the box shrugs off two power flashes,
    /// then the digimon is thrown across the screen in its crush pose.
    @ViewBuilder
    private func boxResistsScene(
        friendly: String,
        elapsed: TimeInterval
    ) -> some View {
        let flash: [TimeInterval] = [0.5, 0.15, 0.35, 0.15, 0.35, 0.25]
        let flashTotal = flash.reduce(0, +)
        if elapsed < flashTotal {
            centeredDigimon("jackpot")
            let step = segment(elapsed, flash)
            if step == 1 || step == 3 {
                fullSprite("giveMassivePowerInverted")
            }
        } else {
            // 64 steps of one pixel at 0.6/16 each — it crosses the
            // screen and keeps going well past the right edge.
            let travelled = (elapsed - flashTotal) / (0.6 / 16.0)
            UnityDTSprite(
                key: "digimon:\(friendly)_cr",
                x: -24 + min(64, travelled),
                y: 4,
                w: 24,
                h: 24
            )
        }
    }

    /// `Animations.RewardDistance` / `RewardSpiritPower`: the reward
    /// background cycles, the icon fades in, floats up and hands over to
    /// a caption and a value that ticks to its new number.
    @ViewBuilder
    private func rewardPanelScene(
        iconField: String,
        iconIndex: Int,
        caption: String,
        captionX: Double,
        before: Int,
        after: Int,
        elapsed: TimeInterval
    ) -> some View {
        let cycle = 0.125
        let introEnd = 8 * cycle        // background alone
        let blinkEnd = introEnd + 4 * cycle
        let holdEnd = blinkEnd + 24 * cycle
        let riseEnd = holdEnd + 0.5

        if elapsed < riseEnd {
            if elapsed < holdEnd {
                UnityDTSprite(
                    key: spriteDB(
                        "rewardBackground",
                        index: Int(elapsed / cycle) % 4
                    ),
                    x: 0,
                    y: 0,
                    w: 32,
                    h: 32
                )
            }
            // Blinks on the even quarters while fading in, then stays.
            let iconVisible = elapsed >= blinkEnd
                || (elapsed >= introEnd
                    && Int((elapsed - introEnd) / cycle)
                        .isMultiple(of: 2))
            if iconVisible {
                let rise = elapsed < holdEnd
                    ? 0.0
                    : 9.0 * ((elapsed - holdEnd) / 0.5)
                UnityDTSprite(
                    key: spriteDB(iconField, index: iconIndex),
                    x: 8,
                    y: 8 - rise,
                    w: 16,
                    h: 16
                )
            }
        } else {
            UnityDTSprite(
                key: spriteDB(iconField, index: iconIndex),
                x: 8,
                y: -1,
                w: 16,
                h: 16
            )
            UnityDTLabel(
                caption,
                x: captionX,
                y: 17,
                w: 32 - captionX,
                h: 5,
                size: 2.8
            )
            UnityDTLabel(
                "\(elapsed < riseEnd + 1.0 ? before : after)",
                x: 2,
                y: 24,
                w: 29,
                h: 5,
                size: 3.2,
                alignment: .trailing
            )
        }
    }

    /// `Animations.RewardCode`: the digimon drifts down inside a
    /// bubble, the bubble pops in a quickening blink, and the code is
    /// spelled out on a database page before the D-Tector flashes.
    @ViewBuilder
    private func rewardCodeScene(
        digimon: String,
        code: String,
        elapsed: TimeInterval
    ) -> some View {
        let dropEnd = 4.0
        let bubbleBlink: [TimeInterval] = [
            0.15, 1.0,
            0.25, 0.4, 0.25, 0.4, 0.25, 0.4,
            0.25, 0.2, 0.25, 0.2, 0.25, 0.2,
            1.0
        ]
        let blinkTotal = bubbleBlink.reduce(0, +)
        let codeEnd = dropEnd + blinkTotal + 3.0

        if elapsed < dropEnd {
            // 64 ticks, moving on every other one, so 32 pixels total.
            // Unity starts the digimon centred, pushed outside the top
            // and up another 4 — y = -28 — so it lands dead centre.
            let moved = floor(elapsed / (4.0 / 64.0) / 2)
            UnityDTSprite(
                key: "digimon:\(digimon)",
                x: 4,
                y: -28 + moved,
                w: 24,
                h: 24
            )
            if Int(elapsed / (4.0 / 64.0)).isMultiple(of: 2) == false {
                UnityDTSprite(
                    key: spriteDB("bubble"),
                    x: 0,
                    y: -32 + moved,
                    w: 32,
                    h: 32
                )
            }
        } else if elapsed < dropEnd + blinkTotal {
            let step = segment(elapsed - dropEnd, bubbleBlink)
            centeredDigimon(digimon)
            // Step 0 is the gap where the opaque bubble is swapped for
            // the transparent one; from there it is on for every odd
            // step and off for every even one.
            if !step.isMultiple(of: 2) {
                UnityDTSprite(
                    key: spriteDB("bubble"),
                    x: 0,
                    y: 0,
                    w: 32,
                    h: 32
                )
            }
        } else if elapsed < codeEnd {
            fullSprite("database_pages")
            UnityDTLabel(
                code.uppercased(),
                x: 2,
                y: 23,
                w: 28,
                h: 8,
                size: 4.0,
                alignment: .trailing
            )
        } else {
            fullSprite("dTector")
            let local = elapsed - codeEnd - 0.30
            if local >= 0, Int(local / 0.15).isMultiple(of: 2) {
                fullSprite("giveMassivePowerInverted")
            }
        }
    }

    /// `Animations.TransitionToMap1`: the screen stutters to black, the
    /// character vanishes for seven seconds, it stutters back and the
    /// curtain brings the character back in their sad pose, then the
    /// new area is announced.
    @ViewBuilder
    private func transitionToMap1Scene(
        character: Int,
        world: Int,
        area: Int,
        distance: Int,
        elapsed: TimeInterval
    ) -> some View {
        let durations: [TimeInterval] = [
            0.5, 0.1, 0.5, 0.1,          // 0-3   slow blinks
            0.3, 0.1, 0.3, 0.1,          // 4-7   quicker blinks
            0.2, 0.5,                    // 8-9   into full black
            7.0,                         // 10    the long dark
            0.1,                         // 11    light
            0.2, 0.1, 0.2, 0.1,          // 12-15 stutter back
            0.1, 0.2, 0.1, 0.3, 0.1      // 16-20
        ]
        let blackoutEnd = durations.reduce(0, +)
        let curtainEnd = blackoutEnd + 4.0
        let holdEnd = curtainEnd + 0.5

        if elapsed < blackoutEnd {
            let step = segment(elapsed, durations)
            // The character is on screen until the beep at step 10.
            if step < 10 {
                fullCharacter(character, frame: 0)
            }
            // Odd early steps are the black flashes; steps 9-10 hold
            // black through the beep, then the screen stutters back.
            if [1, 3, 5, 7, 9, 10, 12, 14, 16, 18, 20].contains(step) {
                fullSprite("blackScreen")
            }
        } else if elapsed < curtainEnd {
            let progress = (elapsed - blackoutEnd) / 4.0
            if progress >= 0.5 {
                fullCharacter(character, frame: 7)
            }
            UnityDTSolidRect(
                x: 0,
                y: -32 + 64 * progress,
                w: 32,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("curtain"),
                x: 0,
                y: -32 + 64 * progress,
                w: 32,
                h: 32
            )
        } else if elapsed < holdEnd {
            fullCharacter(character, frame: 7)
        } else {
            displayNewAreaScene(
                world: world,
                area: area,
                distance: distance,
                elapsed: elapsed - holdEnd
            )
        }
    }

    /// `Animations.TransitionToMap3`: the endgame. The character runs,
    /// two absorbers appear, every spirit the player owns is dragged off
    /// screen, the boss reveals itself and the spirits are destroyed
    /// four at a time before it rises away.
    @ViewBuilder
    private func transitionToMap3Scene(
        character: Int,
        enemy: String,
        spirits: [String],
        elapsed: TimeInterval
    ) -> some View {
        let runEnd = 2.5
        let absorberEnd = runEnd + 3.5
        let panEnd = absorberEnd + 1.0
        let dragEnd = panEnd + 9.0
        let settleEnd = dragEnd + 0.35
        let enemyBlinkEnd = settleEnd + 1.5
        let invertBlinkEnd = enemyBlinkEnd + 1.5
        let clearEnd = invertBlinkEnd + 0.25
        let groups = Int(ceil(Double(max(1, spirits.count)) / 4.0))
        let explodeEnd = clearEnd + Double(groups) * 1.2
        let pauseEnd = explodeEnd + 0.1
        let revealEnd = pauseEnd + 0.4
        let settleEnemyEnd = revealEnd + 0.25
        let riseEnd = settleEnemyEnd + 0.8

        if elapsed < runEnd {
            // Running on the spot, 0.25s per frame.
            fullCharacter(
                character,
                frame: Int(elapsed / 0.25).isMultiple(of: 2) ? 4 : 5
            )
        } else if elapsed < absorberEnd {
            fullCharacter(character, frame: 4)
            if Int((elapsed - runEnd) / 0.35).isMultiple(of: 2) {
                absorberPair()
            }
        } else if elapsed < panEnd {
            // The character is dragged 16px to the right, into the
            // absorbers, one pixel per tick.
            let moved = floor((elapsed - absorberEnd) / (1.0 / 16.0))
            UnityDTSprite(
                key: characterKey(character, frame: 4),
                x: moved,
                y: 0,
                w: 32,
                h: 32
            )
            absorberPair()
        } else if elapsed < settleEnd {
            let tick = (elapsed - panEnd) / (1.5 / 32.0)
            // Both halves show the left absorber once the spirits start
            // streaming through; the right one strobes every 7 ticks.
            UnityDTSprite(
                key: spriteDB("spirit_absorber", index: 0),
                x: 0,
                y: 0,
                w: 16,
                h: 32
            )
            if Int(tick / 7).isMultiple(of: 2) {
                UnityDTSprite(
                    key: spriteDB("spirit_absorber", index: 0),
                    x: 16,
                    y: 0,
                    w: 16,
                    h: 32
                )
            }
            ForEach(Array(spirits.enumerated()), id: \.offset) {
                index, spirit in
                let startX = 32.0 + Double(index / 2) * 16.0
                let x = startX - tick
                if x > -16, x < 32 {
                    UnityDTSprite(
                        key: "digimon:\(spirit)_sm",
                        x: x,
                        y: Double((index % 2) * 16),
                        w: 14,
                        h: 16
                    )
                }
            }
        } else if elapsed < enemyBlinkEnd {
            if Int((elapsed - settleEnd) / 0.25).isMultiple(of: 2) == false {
                enemySprite(enemy, attack: false)
            }
        } else if elapsed < invertBlinkEnd {
            enemySprite(enemy, attack: true)
            if Int((elapsed - enemyBlinkEnd) / 0.25)
                .isMultiple(of: 2) == false {
                // The inverted pass is a black field with the attack
                // pose punched out of it.
                blackScreen
                enemySprite(enemy, attack: true)
            }
        } else if elapsed < clearEnd {
            enemySprite(enemy, attack: true)
        } else if elapsed < explodeEnd {
            let local = elapsed - clearEnd
            let group = min(groups - 1, Int(local / 1.2))
            let within = local - Double(group) * 1.2
            // Within a group: a 0.4s beat, then the four spirits pop in
            // the order 1, 4, 2, 3.
            let order = [0, 3, 1, 2]
            let popped = within < 0.4
                ? 0
                : min(4, Int((within - 0.4) / 0.2) + 1)
            ForEach(0..<4, id: \.self) { slot in
                let index = group * 4 + slot
                if index < spirits.count {
                    let rank = order.firstIndex(of: slot) ?? 0
                    let x = Double(1 + (slot % 2) * 16)
                    let y = Double((slot / 2) * 16)
                    if rank < popped - 1 {
                        EmptyView()
                    } else if rank == popped - 1 {
                        UnityDTSprite(
                            key: spriteDB("spirit_explosion"),
                            x: x,
                            y: y,
                            w: 14,
                            h: 16
                        )
                    } else {
                        UnityDTSprite(
                            key: "digimon:\(spirits[index])_sm",
                            x: x,
                            y: y,
                            w: 14,
                            h: 16
                        )
                    }
                }
            }
        } else if elapsed < pauseEnd {
            EmptyView()
        } else if elapsed < revealEnd {
            enemySprite(enemy, attack: true)
        } else if elapsed < settleEnemyEnd {
            enemySprite(enemy, attack: false)
        } else if elapsed < riseEnd {
            // Rises two pixels a tick until it leaves the screen.
            let risen = (elapsed - settleEnemyEnd) / (0.8 / 16.0) * 2
            UnityDTSprite(
                key: "digimon:\(enemy)",
                x: 4,
                y: 4 - risen,
                w: 24,
                h: 24,
                mirrored: true
            )
        }
    }

    private func absorberPair() -> some View {
        ZStack {
            UnityDTSprite(
                key: spriteDB("spirit_absorber", index: 0),
                x: 0,
                y: 0,
                w: 16,
                h: 32
            )
            UnityDTSprite(
                key: spriteDB("spirit_absorber", index: 1),
                x: 16,
                y: 0,
                w: 16,
                h: 32
            )
        }
    }

    /// Index of the active step for `elapsed`, given the consecutive step
    /// durations of a Unity animation coroutine. Each duration is one
    /// `yield return new WaitForSeconds(...)` in `Animations.cs`, so a
    /// scene body can be transcribed step for step from the original.
    private func segment(
        _ elapsed: TimeInterval,
        _ durations: [TimeInterval]
    ) -> Int {
        var remaining = elapsed
        for (index, duration) in durations.enumerated() {
            if remaining < duration { return index }
            remaining -= duration
        }
        return durations.count - 1
    }

    /// When the active step began, for scenes that also need to
    /// interpolate movement within a step.
    private func segmentStart(
        _ elapsed: TimeInterval,
        _ durations: [TimeInterval]
    ) -> TimeInterval {
        var start = 0.0
        var remaining = elapsed
        for duration in durations {
            if remaining < duration { return start }
            remaining -= duration
            start += duration
        }
        return start - (durations.last ?? 0)
    }

    private func fullSprite(_ field: String) -> some View {
        UnityDTSprite(
            key: spriteDB(field),
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
    }

    private func fullCharacter(
        _ character: Int,
        frame: Int
    ) -> some View {
        UnityDTSprite(
            key: characterKey(character, frame: frame),
            x: 0,
            y: 0,
            w: 32,
            h: 32
        )
    }

    private func centeredDigimon(
        _ name: String,
        attack: Bool = false,
        crush: Bool = false,
        spirit: Bool = false
    ) -> some View {
        let suffix = spirit ? "_sp" : attack ? "_at" : crush ? "_cr" : ""
        return UnityDTSprite(
            key: "digimon:\(name)\(suffix)",
            x: 4,
            y: 4,
            w: 24,
            h: 24
        )
    }

    private func enemySprite(
        _ name: String,
        attack: Bool
    ) -> some View {
        UnityDTSprite(
            key: "digimon:\(name)\(attack ? "_at" : "")",
            x: 4,
            y: 4,
            w: 24,
            h: 24,
            mirrored: true
        )
    }

    private func characterKey(_ character: Int, frame: Int) -> String {
        let fields = [
            "takuya",
            "koji",
            "zoe",
            "jp",
            "tommy",
            "koichi"
        ]
        return game.catalog.spriteDBKey(
            fields[safe: character] ?? "takuya",
            frame
        ) ?? "sliced:characters_0"
    }

    private func spriteDB(_ field: String, index: Int? = nil) -> String {
        game.catalog.spriteDBKey(field, index)
            ?? game.catalog.spriteDBKey("blackScreen")
            ?? "sliced:menus_20"
    }

    /// Battle.cs reads the rank off the live `friendlyStats` /
    /// `enemyStats`, not the database entry — a spirit form fights with
    /// boss-tier energy, so using the base stats picked the wrong
    /// (denser or sparser) energy sprite.
    private func energyKey(
        for digimon: String,
        boss: Bool = false
    ) -> String {
        if let battle = game.state.battle {
            if digimon == battle.playerName,
               let friendly = battle.friendlyStats {
                return "energy:energy_\(energyRank(friendly.EN))"
            }
            if digimon == battle.enemyName {
                return "energy:energy_\(energyRank(battle.enemyStats.EN))"
            }
        }
        let rank = game.catalog.digimonByName[digimon]
            .map {
                energyRank(
                    boss
                        ? ($0.bossStats ?? $0.stats).EN
                        : $0.stats.EN
                )
            } ?? 0
        return "energy:energy_\(rank)"
    }

    private func attackKey(digimon: String, attack: Int) -> String {
        switch attack {
        case 0:
            return energyKey(for: digimon)
        case 1:
            return "digimon:\(digimon)_cr"
        case 2:
            let ability = game.catalog.digimonByName[digimon]?
                .abilityName ?? "flames_1"
            return "ability:\(ability)"
        default:
            return "digimon:\(digimon)"
        }
    }

    private func energyRank(_ energy: Int) -> Int {
        switch energy {
        case ..<20: 0
        case ..<30: 1
        case ..<45: 2
        case ..<60: 3
        case ..<75: 4
        case ..<90: 5
        case ..<105: 6
        case ..<120: 7
        case ..<135: 8
        case ..<150: 9
        case ..<175: 10
        case ..<200: 11
        case ..<225: 12
        case ..<250: 13
        case ..<275: 14
        default: 15
        }
    }
}

private struct UnityDTLCD<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                UnityDTLCDColor.background

                content
                    .frame(width: side, height: side)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(
                Rectangle()
                    .stroke(
                        UnityDTLCDColor.border,
                        lineWidth: 4
                    )
            )
        }
    }
}

/// A name that does not fit the 32px screen scrolls right to left. The
/// pixel font advances 5px a glyph, so anything over 6 letters has to
/// move — and most digimon names do.
///
/// The scroll is measured from an anchor taken when the text last
/// changed, not from the free-running frame counter: browsing to
/// another digimon has to start its name from the right edge again
/// rather than dropping it in wherever the previous one had got to.
/// Scenery for the walking screen. Nothing like this exists in the
/// original — its character screen is bare — so this is invented, kept
/// deliberately low and sparse so it reads as ground the character is
/// walking over rather than clutter competing with the sprite.
///
/// The world repeats every `period` pixels and scrolls 6px per step,
/// derived from the step count plus the in-progress walk so it never
/// jumps: before a step it sits at `steps * 6`, and the moment the step
/// lands the counter advances while the progress resets to zero.
private struct UnityDTWalkBackdrop: View {
    let scroll: Double
    /// Five-minute day/night phase supplied by the home screen.
    let night: Bool
    /// Drives the moon's slow drift.
    let frame: Int

    private static let period = 128
    private static let farSkyPeriod = 64
    private static let nearSkyPeriod = 40
    /// Distant, small, slow-moving cloud layer — the depth cue. Night
    /// keeps far fewer of them so the sky stays calm around the moon.
    private static let farClouds = [(6, 0), (30, 1), (50, 0)]
    private static let farCloudsNight = [(30, 1)]
    private static let farCloudShapes = [
        [".###.", "#####"],
        ["..##.", "#####"],
    ]
    /// Nearer, bigger, faster-moving cloud layer.
    private static let nearClouds = [(12, 0), (33, 1)]
    private static let nearCloudsNight = [(12, 1)]
    private static let nearCloudShapes = [
        ["..###..", ".#####.", "#######"],
        ["...##..", ".######", "#######"],
    ]
    /// A crescent, not a disc: on a one-bit screen a filled blob reads
    /// as any old circle, where a crescent can only be the moon.
    private static let moon = [
        "..##.", ".##..", "##...", "##...", "##...", ".##..", "..##.",
    ]
    /// (world position, kind) — 0 tree, 1/3/4 mountain variants, 2 rock.
    private static let items: [(Int, Int)] = [
        (2, 1), (23, 0), (31, 2), (40, 3),
        (63, 0), (71, 2), (80, 4), (98, 0),
        (107, 2), (116, 0),
    ]
    private static let tree = [
        "..#..", ".###.", "#####", ".###.", "#####", "..#..", "..#..",
    ]
    /// After dark the trees fill in as silhouettes, but mountains keep
    /// their ridgeline so they do not become a heavy block behind the
    /// character.
    private static let treeNight = [
        "..#..", ".###.", "#####", "#####", "#####", "..#..", "..#..",
    ]
    /// A main peak with a foothill off to one side. The old shape was
    /// twice as wide as it was tall, which reads as a slab rather than
    /// a mountain — this one rises well clear of its base. Daylight
    /// shows the ridgeline only, night fills it in as a silhouette.
    private static let hill = [
        ".....#..........",
        "....#.#.........",
        "...#...#........",
        "..#.....#..#....",
        ".#.......##.#...",
        "#............#..",
        "..............##",
    ]
    private static let hillNight = hill
    private static let twinHill = [
        "......#....#......",
        ".....#.#..#.#.....",
        "....#...##...#....",
        "...#..........#...",
        "..#............#..",
        ".#..............#.",
        "#................#",
    ]
    private static let sharpHill = [
        "......#......",
        ".....#.#.....",
        "....#...#....",
        "...#.....#...",
        "..#.......#..",
        ".#.........#.",
        "#...........#",
    ]
    private static let rock = ["*.##.", "####"]

    private static func art(_ kind: Int, night: Bool) -> [String] {
        switch kind {
        case 0: return night ? treeNight : tree
        case 1: return night ? hillNight : hill
        case 2: return rock
        case 3: return twinHill
        default: return sharpHill
        }
    }

    var body: some View {
        Canvas { context, size in
            let cw = size.width / 32.0
            let ch = size.height / 32.0
            let insetX = cw / 13.0
            let insetY = ch / 13.0
            let pw = cw * 11.0 / 13.0
            let ph = ch * 11.0 / 13.0

            func plot(
                _ x: Int,
                _ y: Int,
                color: Color = .black
            ) {
                guard x >= 0, x < 32, y >= 0, y < 32 else { return }
                context.fill(
                    Path(
                        CGRect(
                            x: CGFloat(x) * cw + insetX,
                            y: CGFloat(y) * ch + insetY,
                            width: pw,
                            height: ph
                        )
                    ),
                    with: .color(color)
                )
            }

            /// Wipes a block back to bare screen, the way the game's own
            /// opaque elements erase whatever they are built over.
            func clear(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
                context.fill(
                    Path(
                        CGRect(
                            x: CGFloat(x) * cw,
                            y: CGFloat(y) * ch,
                            width: CGFloat(w) * cw,
                            height: CGFloat(h) * ch
                        )
                    ),
                    with: .color(UnityDTLCDColor.background)
                )
            }

            let offset = Int(scroll.rounded(.down))
            let farOffset = Int((scroll / 6).rounded(.down))
                % Self.farSkyPeriod
            let nearOffset = Int((scroll / 2).rounded(.down))
                % Self.nearSkyPeriod
            let moonX = 24
            let moonBobStep = (frame / 30) % 4
            let moonY = (moonBobStep == 1 || moonBobStep == 2) ? 3 : 2

            // Two cloud layers moving at different speeds/sizes give the
            // sky actual depth instead of one flat drifting strip.
            for (pos, shapeIndex) in
                (night ? Self.farCloudsNight : Self.farClouds) {
                let cloud = Self.farCloudShapes[shapeIndex]
                for repeatIndex in -1...1 {
                    let sx = pos - farOffset
                        + repeatIndex * Self.farSkyPeriod
                    guard sx > -4, sx < 32 else { continue }
                    for (dy, row) in cloud.enumerated() {
                        for (dx, c) in row.enumerated() where c == "#" {
                            plot(sx + dx, 0 + dy)
                        }
                    }
                }
            }
            for (pos, shapeIndex) in
                (night ? Self.nearCloudsNight : Self.nearClouds) {
                let cloud = Self.nearCloudShapes[shapeIndex]
                for repeatIndex in -1...1 {
                    let sx = pos - nearOffset
                        + repeatIndex * Self.nearSkyPeriod
                    guard sx > -6, sx < 32 else { continue }
                    for (dy, row) in cloud.enumerated() {
                        for (dx, c) in row.enumerated() where c == "#" {
                            plot(sx + dx, 3 + dy)
                        }
                    }
                }
            }

            if night {
                // The moon drifts slowly inside a safe band so it never
                // kisses the bezel. It does not clear the sky, so clouds
                // can pass naturally around it.
                for (dy, row) in Self.moon.enumerated() {
                    for (dx, c) in row.enumerated() where c == "#" {
                        plot(moonX + dx, moonY + dy)
                    }
                }
            }

            // Ground line the character stands on.
            for x in 0..<32 {
                plot(x, 29)
            }

            // Scenery, standing on the ground line.
            let wrapped = offset % Self.period
            for (pos, kind) in Self.items {
                let rows = Self.art(kind, night: night)
                let height = rows.count
                let baseY = 29 - height
                for repeatIndex in -1...1 {
                    let sx = pos - wrapped + repeatIndex * Self.period
                    guard sx > -18, sx < 32 else { continue }
                    for (dy, row) in rows.enumerated() {
                        for (dx, c) in row.enumerated() where c == "#" {
                            plot(sx + dx, baseY + dy)
                        }
                    }
                    // The hill's left ridge reaches the ground one cell
                    // down-left from the first column of its sprite.
                    if kind == 1 {
                        plot(sx - 1, 28)
                    }
                }
            }

        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTScrollingName: View {
    @EnvironmentObject private var game: UnityDTGameModel
    let text: String
    let y: Double
    var pixelsPerSecond: Double = 12

    @State private var anchor: Int?

    var body: some View {
        let name = text.uppercased()
        let width = Double(name.count) * 5
        // The engine's own name-sign style: a black panel with the text
        // knocked out of it, the way ScreenElement.BuildStatSign builds
        // its sign with InvertColors(true). Sized to sit flush with the
        // bottom of the screen rather than leaving a sliver under it.
        let barY = y - 1
        let barHeight = min(8.0, 32.0 - barY)
        return ZStack {
            UnityDTSolidRect(
                x: 0,
                y: barY,
                w: 32,
                h: barHeight,
                color: .black
            )
            if width <= 32 {
                UnityDTLabel(
                    name,
                    x: 0,
                    y: y,
                    w: 32,
                    h: 5,
                    size: 2.8,
                    color: UnityDTLCDColor.background
                )
            } else {
                // One full pass every (width + 32) pixels.
                let span = width + 32
                let elapsed = max(
                    0,
                    game.animationFrame - (anchor ?? game.animationFrame)
                )
                let travelled = (Double(elapsed) / 30.0 * pixelsPerSecond)
                    .truncatingRemainder(dividingBy: span)
                UnityDTLabel(
                    name,
                    x: 32 - travelled,
                    y: y,
                    w: width,
                    h: 5,
                    size: 2.8,
                    alignment: .leading,
                    color: UnityDTLCDColor.background
                )
            }
        }
        .onAppear { anchor = game.animationFrame }
        .onChange(of: text) { _ in anchor = game.animationFrame }
    }
}

/// `DatabaseApp.AnimateSprite`: a digimon sitting on a screen holds its
/// default pose for 2.5s, then twitches into its attack pose and back
/// twice at 0.4s a step, over and over. The original only does this in
/// the database gallery; the port uses it everywhere a digimon is shown
/// standing still, which is the only deliberate widening.
private struct UnityDTIdleDigimon: View {
    @EnvironmentObject private var game: UnityDTGameModel
    let name: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    var mirrored = false

    static let period: Double = 2.5 + 0.4 + 0.4 + 0.4

    var body: some View {
        let t = (Double(game.animationFrame) / 30.0)
            .truncatingRemainder(dividingBy: Self.period)
        let twitching = (t >= 2.5 && t < 2.9) || (t >= 3.3 && t < 3.7)
        UnityDTSprite(
            key: "digimon:\(name)\(twitching ? "_at" : "")",
            x: x,
            y: y,
            w: w,
            h: h,
            mirrored: mirrored
        )
    }
}

private struct UnityDTSpriteClearance: View {
    @EnvironmentObject private var game: UnityDTGameModel
    let key: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var body: some View {
        GeometryReader { proxy in
            if let asset = game.catalog.assetName(for: key),
               let mask = UnityDTImageCache.shared.clearanceMask(named: asset) {
                Canvas { context, size in
                    let cellWidth = size.width / CGFloat(mask.width)
                    let cellHeight = size.height / CGFloat(mask.height)
                    let sourceGroundY = floor(
                        CGFloat(mask.height) * CGFloat(29.0 - y) / CGFloat(h)
                    )
                    for pixel in mask.pixels where pixel.y < sourceGroundY {
                        context.fill(
                            Path(
                                CGRect(
                                    x: pixel.x * cellWidth,
                                    y: pixel.y * cellHeight,
                                    width: cellWidth,
                                    height: cellHeight
                                )
                            ),
                            with: .color(UnityDTLCDColor.background)
                        )
                    }
                }
                .frame(
                    width: proxy.size.width * w / 32.0,
                    height: proxy.size.height * h / 32.0
                )
                .position(
                    x: proxy.size.width * (x + w / 2) / 32.0,
                    y: proxy.size.height * (y + h / 2) / 32.0
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTSprite: View {
    @EnvironmentObject private var game: UnityDTGameModel
    let key: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    var mirrored = false
    var opacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            if let colored = UnityDTImageCache.shared
                .colorImage(forSpriteKey: key) {
                // Drawn at the art's own resolution rather than being
                // resampled onto the LCD cell grid, so the sprite keeps
                // the detail it was authored with.
                Image(uiImage: colored)
                    .interpolation(.none)
                    .resizable()
                    .id(key)
                    .frame(
                        width: proxy.size.width * w / 32.0,
                        height: proxy.size.height * h / 32.0
                    )
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .opacity(opacity)
                    .position(
                        x: proxy.size.width * (x + w / 2) / 32.0,
                        y: proxy.size.height * (y + h / 2) / 32.0
                    )
            } else if let asset = game.catalog.assetName(for: key),
               let mask = UnityDTImageCache.shared.mask(named: asset) {
                UnityDTPixelMaskView(mask: mask)
                    .id(key)
                    .frame(
                        width: proxy.size.width * w / 32.0,
                        height: proxy.size.height * h / 32.0
                    )
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .opacity(opacity)
                    .position(
                        x: proxy.size.width * (x + w / 2) / 32.0,
                        y: proxy.size.height * (y + h / 2) / 32.0
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private enum UnityDTLCDColor {
    static let background = Color(
        red: 166.0 / 255.0,
        green: 171.0 / 255.0,
        blue: 168.0 / 255.0
    )
    static let border = Color(
        red: 38.0 / 255.0,
        green: 38.0 / 255.0,
        blue: 38.0 / 255.0
    )
}

private struct UnityDTPixelMask {
    let width: Int
    let height: Int
    let pixels: [CGPoint]
}

private struct UnityDTPixelMaskView: View {
    let mask: UnityDTPixelMask

    var body: some View {
        Canvas { context, size in
            let cellWidth = size.width / CGFloat(mask.width)
            let cellHeight = size.height / CGFloat(mask.height)
            let insetX = cellWidth / 13.0
            let insetY = cellHeight / 13.0
            let pixelWidth = cellWidth * 11.0 / 13.0
            let pixelHeight = cellHeight * 11.0 / 13.0

            for pixel in mask.pixels {
                let rect = CGRect(
                    x: pixel.x * cellWidth + insetX,
                    y: pixel.y * cellHeight + insetY,
                    width: pixelWidth,
                    height: pixelHeight
                )
                context.fill(
                    Path(rect),
                    with: .color(.black)
                )
            }
        }
    }
}

private final class UnityDTImageCache {
    static let shared = UnityDTImageCache()
    private var cache: [String: UIImage] = [:]
    private var maskCache: [String: UnityDTPixelMask] = [:]
    private var clearanceMaskCache: [String: UnityDTPixelMask] = [:]
    private var colorCache: [String: UIImage?] = [:]

    func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        let image = Bundle.main.path(forResource: name, ofType: "png").flatMap { UIImage(contentsOfFile: $0) }
        if let image {
            cache[name] = image
        }
        return image
    }

    /// Colour art for a sprite key, when a digimon has been converted.
    /// `digimon:veemon_at` looks for `color_veemon_at`. There is no
    /// fallback chain on purpose: a pose without colour art keeps its
    /// monochrome silhouette rather than borrowing another pose's.
    func colorImage(forSpriteKey key: String) -> UIImage? {
        guard key.hasPrefix("digimon:") else { return nil }
        let name = "color_" + key.dropFirst("digimon:".count)
            .replacingOccurrences(of: " ", with: "_")
        if let cached = colorCache[name] { return cached }
        let image = Bundle.main.path(forResource: name, ofType: "png")
            .flatMap { UIImage(contentsOfFile: $0) }
        colorCache[name] = image
        return image
    }

    func mask(named name: String) -> UnityDTPixelMask? {
        if let cached = maskCache[name] {
            return cached
        }
        guard let image = image(named: name),
              let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )

        var pixels: [CGPoint] = []
        pixels.reserveCapacity(width * height / 3)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                if bytes[offset + 3] > 32,
                   bytes[offset] < 128,
                   bytes[offset + 1] < 128,
                   bytes[offset + 2] < 128 {
                    pixels.append(
                        CGPoint(x: x, y: y)
                    )
                }
            }
        }

        let sourceMask = UnityDTPixelMask(
            width: width,
            height: height,
            pixels: pixels
        )
        let mask = sourceMask
        maskCache[name] = mask
        return mask
    }

    func clearanceMask(named name: String) -> UnityDTPixelMask? {
        if let cached = clearanceMaskCache[name] {
            return cached
        }
        guard let source = mask(named: name) else { return nil }
        let mask = expandedMask(source)
        clearanceMaskCache[name] = mask
        return mask
    }

    private func expandedMask(
        _ source: UnityDTPixelMask
    ) -> UnityDTPixelMask {
        var expanded = Set<Int>()
        for pixel in source.pixels {
            let sourceX = Int(pixel.x)
            let sourceY = Int(pixel.y)
            for deltaY in -1...1 {
                for deltaX in -1...1 {
                    let x = sourceX + deltaX
                    let y = sourceY + deltaY
                    guard x >= 0, x < source.width,
                          y >= 0, y < source.height else { continue }
                    expanded.insert(y * source.width + x)
                }
            }
        }

        return UnityDTPixelMask(
            width: source.width,
            height: source.height,
            pixels: expanded.map {
                CGPoint(x: $0 % source.width, y: $0 / source.width)
            }
        )
    }
}

private struct UnityDTSolidRect: View {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    var color: Color = UnityDTLCDColor.background

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 32.0
            let cellHeight = proxy.size.height / 32.0
            Rectangle()
                .fill(color)
                .frame(
                    width: cellWidth * w,
                    height: cellHeight * h
                )
                .position(
                    x: cellWidth * (x + w / 2),
                    y: cellHeight * (y + h / 2)
                )
        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTPixelRect: View {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let cellWidth = size.width / 32.0
                let cellHeight = size.height / 32.0
                let insetX = cellWidth / 13.0
                let insetY = cellHeight / 13.0
                let countX = max(0, Int(ceil(w)))
                let countY = max(0, Int(ceil(h)))

                for row in 0..<countY {
                    for column in 0..<countX {
                        let rect = CGRect(
                            x: (CGFloat(x) + CGFloat(column))
                                * cellWidth + insetX,
                            y: (CGFloat(y) + CGFloat(row))
                                * cellHeight + insetY,
                            width: cellWidth * 11.0 / 13.0,
                            height: cellHeight * 11.0 / 13.0
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTClip<Content: View>: View {
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let content: Content

    init(
        x: Double,
        y: Double,
        w: Double,
        h: Double,
        @ViewBuilder content: () -> Content
    ) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .mask(
                    Rectangle()
                        .frame(
                            width: proxy.size.width * w / 32.0,
                            height: proxy.size.height * h / 32.0
                        )
                        .position(
                            x: proxy.size.width * (x + w / 2) / 32.0,
                            y: proxy.size.height * (y + h / 2) / 32.0
                        )
                )
        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTMazePixels: View {
    let paths: [Int]
    let playerX: Int
    let playerY: Int
    let showPlayer: Bool

    var body: some View {
        Canvas { context, size in
            let cellWidth = size.width / 32.0
            let cellHeight = size.height / 32.0
            let pixelWidth = cellWidth * 11.0 / 13.0
            let pixelHeight = cellHeight * 11.0 / 13.0
            let insetX = cellWidth / 13.0
            let insetY = cellHeight / 13.0
            var open = Set<Int>()

            func key(_ x: Int, _ y: Int) -> Int {
                y * 32 + x
            }

            for y in 0..<12 {
                for x in 0..<15 {
                    let centerX = 1 + x * 2
                    let centerY = 30 - y * 2
                    open.insert(key(centerX, centerY))
                    let index = x + y * 15
                    guard paths.indices.contains(index) else {
                        continue
                    }
                    let cell = paths[index]
                    if (cell & 0b00010) != 0 {
                        open.insert(key(centerX - 1, centerY))
                    }
                    if (cell & 0b01000) != 0 {
                        open.insert(key(centerX + 1, centerY))
                    }
                    if (cell & 0b00001) != 0 {
                        open.insert(key(centerX, centerY + 1))
                    }
                    if (cell & 0b00100) != 0 {
                        open.insert(key(centerX, centerY - 1))
                    }
                }
            }
            open.insert(key(0, 30))
            open.insert(key(30, 8))
            open.insert(key(31, 8))

            for y in 7..<32 {
                for x in 0..<32 where !open.contains(key(x, y)) {
                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth + insetX,
                        y: CGFloat(y) * cellHeight + insetY,
                        width: pixelWidth,
                        height: pixelHeight
                    )
                    context.fill(Path(rect), with: .color(.black))
                }
            }

            if showPlayer {
                var markerX = 1 + playerX * 2
                let markerY = 30 - playerY * 2
                markerX = max(0, min(31, markerX))
                let rect = CGRect(
                    x: CGFloat(markerX) * cellWidth + insetX,
                    y: CGFloat(markerY) * cellHeight + insetY,
                    width: pixelWidth,
                    height: pixelHeight
                )
                context.fill(Path(rect), with: .color(.black))
            }
        }
        .allowsHitTesting(false)
    }
}

private enum UnityDTTextAlignment {
    case leading
    case center
    case trailing
}

private struct UnityDTLabel: View {
    let text: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let size: Double
    let alignment: UnityDTTextAlignment
    let color: Color

    init(
        _ text: String,
        x: Double,
        y: Double,
        w: Double,
        h: Double,
        size: Double,
        alignment: UnityDTTextAlignment = .center,
        color: Color = .black
    ) {
        self.text = text
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        self.size = size
        self.alignment = alignment
        self.color = color
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, canvasSize in
                let style: UnityDTPixelFontStyle
                if size <= 2.8 {
                    style = .small
                } else if size <= 3.6 {
                    style = .regular
                } else {
                    style = .big
                }
                let font = UnityDTPixelFontCache.shared.font(style)
                let lines = text.uppercased().split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).map(String.init)
                let cellWidth = canvasSize.width / 32.0
                let cellHeight = canvasSize.height / 32.0
                let pixelWidth = cellWidth * 11.0 / 13.0
                let pixelHeight = cellHeight * 11.0 / 13.0
                let insetX = cellWidth / 13.0
                let insetY = cellHeight / 13.0
                let totalHeight = max(
                    1,
                    lines.count * font.lineHeight - 1
                )
                let startY = Int(
                    round(y + (h - Double(totalHeight)) / 2.0)
                )

                for (lineIndex, line) in lines.enumerated() {
                    let characters = Array(line)
                    let lineWidth = characters.reduce(0) {
                        partial, character in
                        let code = Int(
                            character.asciiValue
                                ?? Character("?").asciiValue!
                        )
                        return partial
                            + (font.glyphs[code]?.advance
                                ?? font.defaultAdvance)
                    }
                    let startX: Int
                    switch alignment {
                    case .leading:
                        startX = Int(round(x))
                    case .center:
                        startX = Int(
                            round(x + (w - Double(lineWidth)) / 2.0)
                        )
                    case .trailing:
                        startX = Int(round(x + w)) - lineWidth
                    }

                    var cursorX = startX
                    let cursorY = startY
                        + lineIndex * font.lineHeight
                    for character in characters {
                        let code = Int(
                            character.asciiValue
                                ?? Character("?").asciiValue!
                        )
                        if let glyph = font.glyphs[code] {
                            for pixel in glyph.pixels {
                                let logicalX = cursorX + Int(pixel.x)
                                let logicalY = cursorY + Int(pixel.y)
                                guard logicalX >= 0,
                                      logicalX < 32,
                                      logicalY >= 0,
                                      logicalY < 32 else {
                                    continue
                                }
                                let rect = CGRect(
                                    x: CGFloat(logicalX) * cellWidth + insetX,
                                    y: CGFloat(logicalY) * cellHeight + insetY,
                                    width: pixelWidth,
                                    height: pixelHeight
                                )
                                context.fill(Path(rect), with: .color(color))
                            }
                            cursorX += glyph.advance
                        } else {
                            cursorX += font.defaultAdvance
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct UnityDTMarquee: View {
    let text: String
    let y: Double

    init(_ text: String, y: Double) {
        self.text = text
        self.y = y
    }

    var body: some View {
        UnityDTLabel(text, x: 0, y: y, w: 32, h: 4, size: text.count > 10 ? 2.2 : 2.8)
    }
}
