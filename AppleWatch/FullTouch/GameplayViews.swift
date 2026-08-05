import SwiftUI

private struct BattleVisualSnapshot {
    var player: BattlePresentationSprite
    var enemy: BattlePresentationSprite
    var playerName: String
    var enemyName: String
    var activeHP: Int
    var activeMaxHP: Int
    var enemyHP: Int
    var enemyMaxHP: Int
    var hasActiveDigimon: Bool
}

struct ClassicBattleActorScreen: View {
    @Environment(\.displayScale) private var displayScale

    var resource: String
    var frame: Int
    var mirrored: Bool
    var alert: Bool
    var verticalOffset: CGFloat = 0
    var pulse: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let viewportSize = ClassicLCDGeometry.pixelAlignedSize(
                fitting: geometry.size,
                displayScale: displayScale
            )
            let scale = viewportSize.width
                / ClassicLCDGeometry.logicalWidth
            let viewportWidth = viewportSize.width
            let viewportHeight = viewportSize.height
            let safeDisplayScale = max(1, displayScale)
            let originX = round(
                (geometry.size.width - viewportWidth)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale
            let originY = round(
                (geometry.size.height - viewportHeight)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale

            ZStack {
                DetectorPalette.screen

                ClassicPixelAsset(resource: resource, frame: frame)
                    .frame(width: 24 * scale, height: 24 * scale)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .scaleEffect(pulse)
                    .position(
                        x: originX + 15 * scale,
                        y: originY + (16 + verticalOffset) * scale
                    )

                if alert {
                    ClassicLCDSprite(
                        resource: "spr_alert_dtector",
                        frame: 0
                    )
                    .frame(
                        width: viewportWidth,
                        height: viewportHeight
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                }
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
    }
}

private struct ClassicBattleHPOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var value: Int
    var showsNumber: Bool

    var body: some View {
        GeometryReader { geometry in
            let viewportSize = ClassicLCDGeometry.pixelAlignedSize(
                fitting: geometry.size,
                displayScale: displayScale
            )
            let scale = viewportSize.width
                / ClassicLCDGeometry.logicalWidth
            let viewportWidth = viewportSize.width
            let viewportHeight = viewportSize.height
            let safeDisplayScale = max(1, displayScale)
            let originX = round(
                (geometry.size.width - viewportWidth)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale
            let originY = round(
                (geometry.size.height - viewportHeight)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale
            ZStack {
                ClassicLCDSprite(
                    resource: "spr_life_dtector",
                    frame: 0
                )
                .frame(width: viewportWidth, height: viewportHeight)
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                if showsNumber {
                    ClassicLCDNumber(
                        value: value,
                        white: true,
                        scale: scale
                    )
                    .position(
                        x: originX
                            + ClassicLCDNumber.logicalCenter(
                                for: value,
                                leastSignificantX: 23
                            ) * scale,
                        y: originY + 26.5 * scale
                    )
                }
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClassicSpiritSelectionScreen: View {
    @Environment(\.displayScale) private var displayScale

    var spiritFrame: Int

    var body: some View {
        GeometryReader { geometry in
            let viewportSize = ClassicLCDGeometry.pixelAlignedSize(
                fitting: geometry.size,
                displayScale: displayScale
            )
            let scale = viewportSize.width
                / ClassicLCDGeometry.logicalWidth
            let safeDisplayScale = max(1, displayScale)
            let originX = round(
                (geometry.size.width - viewportSize.width)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale
            let originY = round(
                (geometry.size.height - viewportSize.height)
                    / 2 * safeDisplayScale
            ) / safeDisplayScale

            ZStack {
                DetectorPalette.screen

                ClassicLCDSprite(
                    resource: "spr_sel_dtector",
                    frame: 0
                )
                .frame(
                    width: viewportSize.width,
                    height: viewportSize.height
                )
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                ClassicPixelAsset(
                    resource: "spr_spirits_dtector",
                    frame: spiritFrame
                )
                .frame(width: 24 * scale, height: 24 * scale)
                .position(
                    x: originX + 15 * scale,
                    y: originY + 12 * scale
                )

                ClassicPixelAsset(
                    resource: "spr_type_dtector",
                    frame: min(5, max(0, spiritFrame / 2))
                )
                .frame(width: 30 * scale, height: 5 * scale)
                .position(
                    x: originX + 15 * scale,
                    y: originY + 27.5 * scale
                )
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
    }
}

private enum ClassicBattleScannerStage: Equatable {
    case prompt
    case arming(Date)
    case streaming(Date)
    case finishing(Date)
}

/// `obj_scan_dtector` is a timed scanner, not a three-button code form.
///
/// The prompt alternates frames 0/1 every 15 source steps. Starting the scan
/// shows frame 2, then frame 3 travels one logical pixel every two source
/// steps over frame 4. The actual one/zero capture windows are controlled by
/// `BattleView`; this view only reproduces the original LCD presentation.
private struct ClassicBattleScanScreen: View {
    var stage: ClassicBattleScannerStage

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / 30,
                    geometry.size.height / 32
                )
                let viewportWidth = 30 * scale
                let viewportHeight = 32 * scale
                let originX = (geometry.size.width - viewportWidth) / 2
                let originY = (geometry.size.height - viewportHeight) / 2

                ZStack {
                    DetectorPalette.screen

                    switch stage {
                    case .prompt:
                        let frame = Int(
                            timeline.date.timeIntervalSinceReferenceDate
                                / 0.25
                        ) % 2
                        scanFrame(
                            frame,
                            x: originX,
                            y: originY,
                            width: viewportWidth,
                            height: viewportHeight
                        )

                    case .arming:
                        scanFrame(
                            2,
                            x: originX,
                            y: originY,
                            width: viewportWidth,
                            height: viewportHeight
                        )

                    case .streaming(let startedAt),
                         .finishing(let startedAt):
                        scanFrame(
                            4,
                            x: originX,
                            y: originY,
                            width: viewportWidth,
                            height: viewportHeight
                        )

                        let elapsed = max(
                            0,
                            timeline.date.timeIntervalSince(startedAt)
                        )
                        let scroll = CGFloat(
                            Int(elapsed / (2.0 / 60.0)) % 64
                        )
                        ClassicPixelAsset(
                            resource: "spr_scan_dtector",
                            frame: 3
                        )
                        .frame(
                            width: viewportWidth,
                            height: viewportHeight
                        )
                        .position(
                            x: originX + viewportWidth / 2,
                            y: originY + (scroll - 16) * scale
                        )
                    }
                }
                .clipped()
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
        .accessibilityHidden(true)
    }

    private func scanFrame(
        _ frame: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ClassicPixelAsset(
            resource: "spr_scan_dtector",
            frame: frame
        )
        .frame(width: width, height: height)
        .position(x: x + width / 2, y: y + height / 2)
    }
}

struct ClassicPostBattleCharacterScreen: View {
    @Environment(\.displayScale) private var displayScale
    @State private var startedAt = Date()

    var characterResource: String
    var enemyResource: String
    var won: Bool
    var levelChange: Int
    var lostSpiritID: Int?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            GeometryReader { geometry in
                let viewportSize = ClassicLCDGeometry.pixelAlignedSize(
                    fitting: geometry.size,
                    displayScale: displayScale
                )
                let scale = viewportSize.width
                    / ClassicLCDGeometry.logicalWidth
                let safeDisplayScale = max(1, displayScale)
                let originX = round(
                    (geometry.size.width - viewportSize.width)
                        / 2 * safeDisplayScale
                ) / safeDisplayScale
                let originY = round(
                    (geometry.size.height - viewportSize.height)
                        / 2 * safeDisplayScale
                ) / safeDisplayScale
                let animation = Int(
                    timeline.date.timeIntervalSinceReferenceDate * 2
                ).isMultiple(of: 2)
                let elapsed = max(
                    0,
                    timeline.date.timeIntervalSince(startedAt)
                )
                let levelCounter = min(14, Int(elapsed / 0.20))
                let lossCounter = min(165, Int(elapsed / 0.10))
                let poseResource = animation
                    ? characterResource
                    : "\(characterResource)_\(won ? "happy" : "defeat")"

                ZStack {
                    DetectorPalette.screen

                    if let lostSpiritID {
                        lostSpiritStage(
                            counter: lossCounter,
                            spiritID: lostSpiritID,
                            scale: scale,
                            origin: CGPoint(x: originX, y: originY)
                        )
                    } else if levelChange != 0 && elapsed < 3.0 {
                        ClassicLCDSprite(
                            resource: "spr_object_dtector",
                            frame: levelCounter
                        )
                        .frame(
                            width: viewportSize.width,
                            height: viewportSize.height
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                        ClassicLCDSprite(
                            resource: "spr_change_level_dtector",
                            frame: levelChange > 0 ? 0 : 1
                        )
                        .frame(
                            width: viewportSize.width,
                            height: viewportSize.height
                        )
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                    } else {
                        ClassicPixelAsset(
                            resource: poseResource,
                            frame: 0
                        )
                        .frame(width: 24 * scale, height: 24 * scale)
                        .position(
                            x: originX + 15 * scale,
                            y: originY + 16 * scale
                        )
                    }

                    if lostSpiritID == nil && won && !animation
                        && !(levelChange != 0 && elapsed < 3.0) {
                        ForEach([CGFloat(4), CGFloat(27)], id: \.self) { x in
                            ClassicPixelAsset(
                                resource: "spr_happy",
                                frame: 0
                            )
                            .frame(width: 8 * scale, height: 8 * scale)
                            .position(
                                x: originX + x * scale,
                                y: originY + 4 * scale
                            )
                        }
                    }
                }
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
    }

    @ViewBuilder
    private func lostSpiritStage(
        counter: Int,
        spiritID: Int,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        if counter <= 14 {
            logicalLossAsset(
                "spr_lose_spirit_dtector",
                x: CGFloat(-1 + counter),
                y: 4,
                scale: scale,
                origin: origin
            )
            logicalLossAsset(
                enemyResource,
                x: 22,
                y: 4,
                mirrored: true,
                scale: scale,
                origin: origin
            )
        } else if counter <= 44 {
            logicalLossAsset(
                "spr_lose_spirit_dtector",
                x: CGFloat(counter - 40),
                y: 4,
                scale: scale,
                origin: origin
            )
        } else if counter <= 99 {
            let offset = CGFloat(counter - 45)
            logicalLossAsset(
                "spr_lose_spirit_dtector",
                x: 5 - offset,
                y: 4,
                scale: scale,
                origin: origin
            )
            logicalLossAsset(
                "spr_spirits_dtector",
                frame: spiritID,
                x: 30 - offset,
                y: 4,
                scale: scale,
                origin: origin
            )
        } else if counter <= 131 {
            let offset = CGFloat(counter - 101)
            logicalLossAsset(
                "spr_lose_spirit_dtector",
                x: 5 - offset,
                y: 4,
                scale: scale,
                origin: origin
            )
            logicalLossAsset(
                "spr_spirits_dtector",
                frame: spiritID,
                x: 30 - offset,
                y: 4,
                scale: scale,
                origin: origin
            )
            logicalLossAsset(
                enemyResource,
                x: 22,
                y: 4,
                mirrored: true,
                scale: scale,
                origin: origin
            )
        } else {
            logicalLossAsset(
                enemyResource,
                x: 22,
                y: CGFloat(4 - (counter - 132)),
                mirrored: true,
                scale: scale,
                origin: origin
            )
        }
    }

    private func logicalLossAsset(
        _ resource: String,
        frame: Int = 0,
        x: CGFloat,
        y: CGFloat,
        mirrored: Bool = false,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicPixelAsset(resource: resource, frame: frame)
            .frame(width: 24 * scale, height: 24 * scale)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(
                x: origin.x + (x + 12) * scale,
                y: origin.y + (y + 12) * scale
            )
    }
}

struct BattleView: View {
    @EnvironmentObject private var game: GameModel
    @StateObject private var battleFX = BattlePresentationDirector()
    @State private var audioTask: Task<Void, Never>?
    @State private var didPresentEncounter = false
    @State private var visualSnapshot: BattleVisualSnapshot?
    @State private var classicSelection = Self.initialClassicSelection
    @State private var selectingMove = false
    @State private var showsCodeEntry = false
    @State private var didPresentEvolutionQA = false
    @State private var scannerStage: ClassicBattleScannerStage = .prompt
    @State private var scannerBits = [Int]()
    @State private var scannerCaptureEnabled = false
    @State private var scannerGeneration = 0
    @State private var scannerTask: Task<Void, Never>?
    @State private var resultReturnTask: Task<Void, Never>?
    @State private var battleCodeSelectedGlyph = 0
    @State private var battleCodeSlot = 0
    @State private var battleCodeGlyphs: [Int?] = Array(
        repeating: nil,
        count: 5
    )

    private static var initialClassicSelection: Int {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("-qa-battle-spirit-digipower")
            ? 1
            : 0
#else
        0
#endif
    }

    var body: some View {
        GeometryReader { geometry in
            if let battle = game.battle, let enemy = game.enemyCombatant {
                ClassicWideBattleShell(
                    showsControls: !battleFX.isPlaying,
                    leftEnabled: !battleFX.isPlaying,
                    cancelEnabled: !battleFX.isPlaying,
                    acceptEnabled: !battleFX.isPlaying,
                    onStageTap: {
                        handleClassicRight(for: battle)
                    },
                    onLeft: {
                        handleClassicLeft(for: battle)
                    },
                    onCancel: {
                        handleClassicCancel(for: battle)
                    },
                    onAccept: {
                        handleClassicAccept(for: battle)
                    }
                ) {
                    battleStage(battle: battle, enemy: enemy)
                }
            } else {
                ClassicExpandedShell(
                    onStageTap: game.goHome,
                    onLeft: game.goHome,
                    onCancel: game.goHome,
                    onAccept: game.goHome
                ) {
                    ClassicLCDLogicalSurface {
                        Rectangle()
                            .fill(DetectorPalette.screen)
                            .frame(width: 30, height: 32)
                            .position(x: 15, y: 16)
                        ClassicLCDText(text: "NO", x: 9, y: 7)
                        ClassicLCDText(text: "BATTLE", x: 0, y: 17)
                    }
                }
            }
        }
        .sheet(isPresented: $showsCodeEntry) {
            battleCodeEntry
        }
        .onChange(of: showsCodeEntry) { _, isPresented in
            guard isPresented else { return }
            battleCodeSelectedGlyph = 0
            battleCodeSlot = 0
            battleCodeGlyphs = Array(repeating: nil, count: 5)
            game.battleCodeInput = ""
        }
        .onAppear {
            presentEncounterIfNeeded()
            presentEvolutionQAIfNeeded()
            if game.battle?.phase == .scanning {
                resetClassicScanner()
            }
            if let battle = game.battle,
               battle.phase == .result {
                beginAutomaticResultReturn(battle.result)
            }
        }
        .onChange(of: game.battle?.phase) { _, phase in
            classicSelection = 0
            selectingMove = false
            if phase == .scanning {
                resetClassicScanner()
            } else {
                stopClassicScanner()
            }
        }
        .onDisappear {
            audioTask?.cancel()
            audioTask = nil
            resultReturnTask?.cancel()
            resultReturnTask = nil
            stopClassicScanner()
            visualSnapshot = nil
            battleFX.stop(resetToIdle: true)
            GameAudio.shared.stop()
        }
    }

    private var animationLabel: String {
        switch battleFX.sample(at: Date()).phase {
        case .summon: "DIGIMON MATERIALIZING"
        case .windUp(_, let move): "\(moveLabel(move)) READY"
        case .projectile(_, let move): "\(moveLabel(move)) LAUNCH"
        case .collision: "ATTACK COLLISION"
        case .impact: "DIRECT HIT"
        case .callPower: "BATTLE CALL"
        case .spiritCheck: "SPIRIT CHECK"
        case .spiritReady: "SPIRIT READY"
        case .digiPower: "DIGI-POWER"
        case .evolution: "DIGIVOLUTION"
        case .capture: "DIGITIZE & CAPTURE"
        case .deport: "DIGIMON DEPORT"
        case .victory: "BATTLE CLEAR"
        case .defeat: "SYSTEM DOWN"
        default: "BATTLE SEQUENCE"
        }
    }

    private var battleTitle: String {
        guard let battle = game.battle else { return "BATTLE" }
        if battle.isFinalBoss { return "FINAL BATTLE" }
        if battle.isBoss { return "BOSS BATTLE" }
        return "DIGIMON BATTLE"
    }

    @ViewBuilder
    private func battleStage(
        battle: BattleSession,
        enemy: Combatant
    ) -> some View {
        let shownEnemyVisual = visualSnapshot?.enemy
            ?? presentationSprite(for: enemy, mirrored: true)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let sample = battleFX.sample(at: context.date)

            ZStack {
                DetectorPalette.screen

                if battleFX.isPlaying {
                    BattlePresentationStage(
                        director: battleFX,
                        player: playerVisual,
                        enemy: shownEnemyVisual,
                        showsGrid: false,
                        cornerRadius: 0
                    )

                    if case let .impact(target, _, _) = sample.phase,
                       sample.beatProgress >= 0.60 {
                        let oldHP = target == .player
                            ? (visualSnapshot?.activeHP ?? battle.activeHP)
                            : (visualSnapshot?.enemyHP ?? battle.enemyHP)
                        let newHP = target == .player
                            ? battle.activeHP
                            : battle.enemyHP
                        ClassicBattleHPOverlay(
                            value: sample.beatProgress < 0.86 ? oldHP : newHP,
                            showsNumber: sample.beatProgress >= 0.72
                        )
                    }
                } else {
                    classicBattleScreen(battle: battle, enemy: enemy)
                }
            }
        }
        .clipped()
        .overlay {
            Rectangle()
                .stroke(DetectorPalette.ink, lineWidth: 2)
        }
    }

    @ViewBuilder
    private func classicBattleScreen(
        battle: BattleSession,
        enemy: Combatant
    ) -> some View {
        switch battle.phase {
        case .alert:
            ClassicBattleActorScreen(
                resource: "\(game.currentCharacter.sprite)_attack",
                frame: Int(
                    Date().timeIntervalSinceReferenceDate * 2
                ).isMultiple(of: 2) ? 0 : 1,
                mirrored: false,
                alert: true
            )

        case .command:
            ClassicLCDSprite(
                resource: "spr_battle_menu_dtector",
                frame: min(3, classicSelection)
            )

        case .scanning:
            ClassicBattleScanScreen(stage: scannerStage)

        case .chooseSpirit:
            if let id = selectedClassicSpiritID, (100...111).contains(id) {
                ClassicSpiritSelectionScreen(
                    spiritFrame: id - 100
                )
            } else if let id = selectedClassicSpiritID {
                ClassicBattleActorScreen(
                    resource: game.combatant(for: id).sprite,
                    frame: 0,
                    mirrored: false,
                    alert: false
                )
            } else {
                ClassicLCDSprite(
                    resource: "spr_spirit_ready_dtector",
                    frame: 0
                )
            }

        case .chooseAttack, .resolving:
            if selectingMove {
                ClassicLCDSprite(
                    resource: "spr_select_attack_dtector",
                    frame: min(2, classicSelection)
                )
            } else if let active = game.activeCombatant,
                      active.type == "spirit" || active.type == "ancient" {
                ClassicLCDSprite(
                    resource: "spr_spirit_menu_dtector",
                    frame: min(3, classicSelection)
                )
            } else {
                ClassicLCDSprite(
                    resource: "spr_call_menu_dtector",
                    frame: min(2, classicSelection)
                )
            }

        case .capture:
            ClassicBattleActorScreen(
                resource: enemy.sprite,
                frame: 0,
                mirrored: true,
                alert: false
            )

        case .result:
            ClassicPostBattleCharacterScreen(
                characterResource: game.currentCharacter.sprite,
                enemyResource: enemy.sprite,
                won: battle.result == .win,
                levelChange: battle.levelChange,
                lostSpiritID: battle.lostSpiritID
            )
        }
    }

    private var availableClassicSpiritIDs: [Int] {
        var values: [Int] = []

        for spirit in game.catalog.spirits {
            guard let battle = game.battle,
                  battle.copiedSpirits.indices.contains(spirit.id),
                  battle.copiedSpirits[spirit.id],
                  game.state.characterParty.indices.contains(
                    spirit.ownerCharacterID
                  ),
                  game.state.characterParty[spirit.ownerCharacterID]
            else {
                continue
            }
            values.append(spirit.digimonID)
        }

        for character in game.catalog.characters
            where game.canUseAncient(character.id) {
            values.append(122 + character.id)
        }

        return values
    }

    private var selectedClassicSpiritID: Int? {
        let values = availableClassicSpiritIDs
        guard !values.isEmpty else { return nil }
        return values[min(classicSelection, values.count - 1)]
    }

    private func classicSelectionCount(for battle: BattleSession) -> Int {
        switch battle.phase {
        case .alert, .capture, .result:
            return 1
        case .command:
            return 4
        case .scanning:
            return 2
        case .chooseSpirit:
            return max(1, availableClassicSpiritIDs.count)
        case .chooseAttack, .resolving:
            if selectingMove {
                return 3
            }
            if let active = game.activeCombatant,
               active.type == "spirit" || active.type == "ancient" {
                return 4
            }
            return 3
        }
    }

    private func handleClassicLeft(for battle: BattleSession) {
        guard !battleFX.isPlaying else { return }

        if battle.phase == .scanning {
            handleClassicScannerTap()
            return
        }

        let count = max(1, classicSelectionCount(for: battle))
        classicSelection = (classicSelection + count - 1) % count
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
    }

    private func handleClassicRight(for battle: BattleSession) {
        guard !battleFX.isPlaying else { return }

        switch battle.phase {
        case .alert, .capture, .result:
            handleClassicAccept(for: battle)
        case .scanning:
            handleClassicScannerTap()
        default:
            let count = max(1, classicSelectionCount(for: battle))
            classicSelection = (classicSelection + 1) % count
            GameAudio.shared.play(
                "sound_select",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func handleClassicCancel(for battle: BattleSession) {
        guard !battleFX.isPlaying else { return }

        if selectingMove {
            selectingMove = false
            classicSelection = 0
        } else {
            switch battle.phase {
            case .scanning, .chooseSpirit:
                game.showBattleCommands()
            case .chooseAttack, .resolving:
                game.showBattleCommands()
            case .command:
                game.escapeBattle()
            case .alert:
                game.escapeBattle()
            case .result:
                game.continueAfterBattle()
            default:
                break
            }
        }

        GameAudio.shared.play(
            "sound_cancel",
            enabled: game.state.soundEnabled
        )
    }

    private func handleClassicAccept(for battle: BattleSession) {
        guard !battleFX.isPlaying else { return }

        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )

        switch battle.phase {
        case .alert:
            game.showBattleCommands()

        case .command:
            switch min(3, classicSelection) {
            case 0:
                game.beginBattleScan(.call)
            case 1:
                game.showSpiritSelection()
                if game.battle?.phase == .chooseSpirit {
                    playSpiritCheck()
                }
            case 2:
                showsCodeEntry = true
            default:
                game.escapeBattle()
            }

        case .scanning:
            handleClassicScannerTap()

        case .chooseSpirit:
            guard let id = selectedClassicSpiritID else {
                game.showBattleCommands()
                return
            }
            if id >= 122 {
                game.summonAncient(for: id - 122)
                playSummon(evolution: true, ancient: true)
            } else {
                game.summonSpirit(id - 100)
                playSummon(evolution: true)
            }

        case .chooseAttack, .resolving:
            if selectingMove {
                performMove(min(2, classicSelection))
                selectingMove = false
                classicSelection = 0
                return
            }

            if let active = game.activeCombatant,
               active.type == "spirit" || active.type == "ancient" {
                switch min(3, classicSelection) {
                case 0:
                    if active.type == "ancient" {
                        performMove(Int.random(in: 0...2))
                    } else {
                        selectingMove = true
                        classicSelection = 0
                    }
                case 1:
                    game.beginBattleScan(.digiPower)
                case 2:
                    deportActive()
                default:
                    game.escapeBattle()
                }
            } else {
                switch min(2, classicSelection) {
                case 0:
                    game.beginBattleScan(.attack)
                case 1:
                    attemptEvolution()
                default:
                    deportActive()
                }
            }

        case .capture:
            captureEnemy()

        case .result:
            game.continueAfterBattle()
        }
    }

    private var battleCodeEntry: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            onLeft: battleCodeCycle,
            onCancel: battleCodeCancel,
            onAccept: battleCodeAccept
        ) {
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                ClassicLCDLogicalSurface {
                    Rectangle()
                        .fill(DetectorPalette.screen)
                        .frame(width: 30, height: 32)
                        .position(x: 15, y: 16)
                    ClassicLCDText(text: "CALL", x: 3, y: 0)
                    ClassicPixelAsset(
                        resource: "spr_font_dtector",
                        frame: battleCodeSelectedGlyph
                    )
                    .frame(width: 5, height: 7)
                    .position(x: 14.5, y: 18.5)

                    ForEach(0..<5, id: \.self) { index in
                        let x = CGFloat(index * 6)
                        if let glyph = battleCodeGlyphs[index] {
                            ClassicPixelAsset(
                                resource: "spr_font_dtector",
                                frame: glyph
                            )
                            .frame(width: 5, height: 7)
                            .position(x: x + 2.5, y: 28.5)
                        }
                        if index != battleCodeSlot
                            || Int(
                                timeline.date.timeIntervalSinceReferenceDate
                                    * 3
                            ).isMultiple(of: 2) {
                            ClassicPixelAsset(
                                resource: "spr_sel_letter_dtector",
                                frame: 0
                            )
                            .frame(width: 5, height: 7)
                            .position(x: x + 2.5, y: 28.5)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .accessibilityLabel("Battle Digi-Digits")
        .accessibilityValue(battleCodeValue)
        .accessibilityHint(
            "Tap left to change glyph, center or right to enter, hold to cancel"
        )
    }

    private var battleCodeValue: String {
        battleCodeGlyphs.compactMap { glyph -> String? in
            guard let glyph else { return nil }
            if glyph <= 25 {
                return String(
                    UnicodeScalar(65 + glyph) ?? UnicodeScalar(65)
                )
            }
            return String(glyph - 26)
        }
        .joined()
    }

    private func battleCodeCycle() {
        battleCodeSelectedGlyph = (battleCodeSelectedGlyph + 1) % 36
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
    }

    private func battleCodeCancel() {
        showsCodeEntry = false
        GameAudio.shared.play(
            "sound_cancel",
            enabled: game.state.soundEnabled
        )
    }

    private func battleCodeAccept() {
        battleCodeGlyphs[battleCodeSlot] = battleCodeSelectedGlyph
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )

        if battleCodeSlot < 4 {
            battleCodeSlot += 1
            return
        }

        game.battleCodeInput = battleCodeValue
        summonFromCode()
        showsCodeEntry = false
    }

    private var playerVisual: BattlePresentationSprite {
        if let visualSnapshot {
            return visualSnapshot.player
        }
        if let active = game.activeCombatant {
            return presentationSprite(for: active)
        }
        return currentCharacterPresentationSprite
    }

    private var currentCharacterPresentationSprite: BattlePresentationSprite {
        BattlePresentationSprite(
            resource: game.currentCharacter.sprite,
            idleFrames: [0, 1],
            attackFrames: [0, 1],
            hitFrames: [0, 1],
            victoryFrames: [0, 1],
            defeatFrames: [0],
            framesPerSecond: 2,
            size: 70,
            accessibilityLabel: game.currentCharacter.name
        )
    }

    private func presentationSprite(
        for combatant: Combatant,
        mirrored: Bool = false
    ) -> BattlePresentationSprite {
        BattlePresentationSprite(
            resource: combatant.sprite,
            idleFrames: [0, 1],
            attackFrames: [1, 2, 3],
            hitFrames: [0, 1],
            victoryFrames: [0, 1],
            defeatFrames: [0],
            framesPerSecond: 3.2,
            size: 68,
            mirrored: mirrored,
            accessibilityLabel: combatant.name
        )
    }

    private func makeVisualSnapshot(
        for battle: BattleSession
    ) -> BattleVisualSnapshot {
        let active = battle.activeDigimonID.map { game.combatant(for: $0) }
        let enemy = game.combatant(for: battle.enemyID)

        return BattleVisualSnapshot(
            player: active.map { presentationSprite(for: $0) }
                ?? currentCharacterPresentationSprite,
            enemy: presentationSprite(for: enemy, mirrored: true),
            playerName: active?.name ?? game.currentCharacter.name,
            enemyName: enemy.name,
            activeHP: battle.activeHP,
            activeMaxHP: battle.activeMaxHP,
            enemyHP: battle.enemyHP,
            enemyMaxHP: enemy.maxHP,
            hasActiveDigimon: battle.activeDigimonID != nil
        )
    }

    @ViewBuilder
    private func controls(for battle: BattleSession) -> some View {
        switch battle.phase {
        case .alert:
            Button("READY") { game.showBattleCommands() }
                .buttonStyle(DetectorButtonStyle(tint: .red))

        case .command:
            HStack(spacing: 4) {
                Button("CALL") { game.beginBattleScan(.call) }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .cyan))
                Button("SPIRIT") { game.showSpiritSelection() }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .orange))
                Button("ESCAPE") { game.escapeBattle() }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .gray))
            }
            TextField("5-CHAR BATTLE CODE", text: $game.battleCodeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
            Button("CODE CALL • \(game.dPowerCost) DP") {
                summonFromCode()
            }
            .buttonStyle(CompactDetectorButtonStyle(tint: .purple))

        case .scanning:
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Text(game.scanBits.indices.contains(index) ? "\(game.scanBits[index])" : "·")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .frame(width: 28, height: 18)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.12)))
                    }
                }
                HStack(spacing: 5) {
                    Button("SCAN") { handleClassicScannerTap() }
                        .buttonStyle(
                            CompactDetectorButtonStyle(tint: .green)
                        )
                }
            }

        case .chooseSpirit:
            VStack(spacing: 5) {
                ForEach(game.catalog.spirits) { spirit in
                    if battle.copiedSpirits.indices.contains(spirit.id),
                       battle.copiedSpirits[spirit.id],
                       game.state.characterParty.indices.contains(spirit.ownerCharacterID),
                       game.state.characterParty[spirit.ownerCharacterID],
                       let digimon = game.catalog.digimon.first(where: { $0.id == spirit.digimonID }) {
                        Button {
                            game.summonSpirit(spirit.id)
                            playSummon(evolution: true)
                        } label: {
                            HStack {
                                GameSprite(resource: digimon.sprite, frame: 0, size: 30)
                                Text(digimon.displayName)
                                Spacer()
                                Text(spirit.kind.uppercased())
                            }
                        }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .orange))
                    }
                }

                ForEach(game.catalog.characters) { character in
                    if game.canUseAncient(character.id) {
                        Button("ANCIENT • \(character.name) • 99 DP") {
                            game.summonAncient(for: character.id)
                            playSummon(evolution: true, ancient: true)
                        }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .purple))
                    }
                }
                Button("BACK") { game.showBattleCommands() }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .white))
            }

        case .chooseAttack, .resolving:
            VStack(spacing: 5) {
                if let active = game.activeCombatant,
                   active.type == "spirit" || active.type == "ancient" {
                    HStack(spacing: 4) {
                        moveButton("ENERGY", 0, .red)
                        moveButton("CRUNCH", 1, .orange)
                        moveButton("ABILITY", 2, .cyan)
                    }
                    HStack(spacing: 4) {
                        if active.type == "spirit" {
                            Button("D-POWER") { game.beginBattleScan(.digiPower) }
                                .buttonStyle(CompactDetectorButtonStyle(tint: .purple))
                        }
                        Button("OFF") { deportActive() }
                            .buttonStyle(CompactDetectorButtonStyle(tint: .gray))
                        Button("ESCAPE") { game.escapeBattle() }
                            .buttonStyle(CompactDetectorButtonStyle(tint: .white))
                    }
                } else {
                    HStack(spacing: 4) {
                        Button("SCAN ATK") { game.beginBattleScan(.attack) }
                            .buttonStyle(CompactDetectorButtonStyle(tint: .green))
                        Button("EVOLVE") { attemptEvolution() }
                            .buttonStyle(CompactDetectorButtonStyle(tint: .purple))
                        Button("SWAP") { deportActive() }
                            .buttonStyle(CompactDetectorButtonStyle(tint: .gray))
                    }
                }
                if let active = game.activeCombatant,
                   active.type == "spirit" || active.type == "ancient" {
                    Text(active.type == "ancient" ? "ATTACK COST 20 DP" : "ATTACK COST \(game.dPowerCost) DP")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                }
            }

        case .capture:
            Button("DIGITIZE & CAPTURE") {
                captureEnemy()
            }
            .buttonStyle(DetectorButtonStyle(tint: .green))

        case .result:
            Button(resultLabel(battle.result)) {
                game.continueAfterBattle()
            }
            .buttonStyle(DetectorButtonStyle(
                tint: battle.result == .lose ? DetectorPalette.danger : .green
            ))
        }
    }

    private func moveButton(_ title: String, _ move: Int, _ tint: Color) -> some View {
        Button(title) {
            performMove(move)
        }
        .buttonStyle(CompactDetectorButtonStyle(tint: tint))
    }

    private func presentEncounterIfNeeded() {
        guard !didPresentEncounter, let battle = game.battle else { return }
        guard battle.phase == .alert else { return }
        didPresentEncounter = true
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-qa-battle-call-menu")
            || ProcessInfo.processInfo.arguments.contains("-qa-battle-spirit-menu")
            || ProcessInfo.processInfo.arguments.contains("-qa-battle-win-result") {
            return
        }
#endif
        let sound: String
        if battle.isFinalBoss {
            sound = "sound_last_boss_dtector"
        } else if battle.isBoss {
            sound = "sound_boss_encounter_dtector"
        } else {
            sound = "sound_encounter_new"
        }
        GameAudio.shared.play(sound, enabled: game.state.soundEnabled)
        battleFX.play(
            .summon(
                .enemy,
                duration: battle.isFinalBoss ? 11.50 : 7.42
            )
        ) {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-qa-battle-fx"),
               game.activeCombatant != nil {
                performMove(0)
                return
            }
#endif
            game.showBattleCommands()
        }
    }

    private func presentEvolutionQAIfNeeded() {
#if DEBUG
        guard !didPresentEvolutionQA,
              ProcessInfo.processInfo.arguments.contains(
                "-qa-battle-spirit-evolution"
              )
                || ProcessInfo.processInfo.arguments.contains(
                    "-qa-battle-ancient-evolution"
                )
        else { return }
        didPresentEvolutionQA = true
        playSummon(
            evolution: true,
            ancient: ProcessInfo.processInfo.arguments.contains(
                "-qa-battle-ancient-evolution"
            )
        )
#endif
    }

    private func performMove(_ move: Int) {
        guard let before = game.battle else { return }
        let snapshot = makeVisualSnapshot(for: before)
        let showsPowerSpend: Bool
        if let active = game.activeCombatant {
            showsPowerSpend = active.type == "spirit"
                || active.type == "ancient"
        } else {
            showsPowerSpend = false
        }
        game.chooseAttack(move)
        guard let after = game.battle else { return }
        playRound(
            before: before,
            after: after,
            snapshot: snapshot,
            showsPowerSpend: showsPowerSpend
        )
    }

    private func finishClassicScan(_ bits: [Int]) {
        guard let before = game.battle else { return }
        let snapshot = makeVisualSnapshot(for: before)
        let purpose = game.scanPurpose
        for bit in bits.prefix(3) {
            game.recordScanBit(bit)
        }
        guard let after = game.battle else { return }

        if after.round > before.round {
            playRound(before: before, after: after, snapshot: snapshot)
        } else if purpose == .call,
                  after.activeDigimonID != before.activeDigimonID {
            playScannedCall(remainingCallPower: after.callPower)
        } else if purpose == .digiPower,
                  after.message.contains("DIGIPOWER") {
            let success = !after.message.contains("FAILED")
            let slot = GameRules.dockSlot(for: bits)
            let beforeHelperID = before.copiedDocks.indices.contains(slot)
                ? before.copiedDocks[slot]
                : -1
            let helperWasConsumed = beforeHelperID >= 0
                && after.copiedDocks.indices.contains(slot)
                && after.copiedDocks[slot] == -1
            let helperID = helperWasConsumed ? beforeHelperID : 32
            let helper = game.combatant(for: helperID)
            let spirit = before.activeDigimonID.map {
                game.combatant(for: $0)
            }
            playScannedDigiPower(
                remainingCallPower: after.callPower,
                helperResource: helper.sprite,
                spiritResource: spirit?.sprite
                    ?? game.currentCharacter.sprite,
                succeeds: success
            )
        }
    }

    private func playScannedCall(remainingCallPower: Int) {
        audioTask?.cancel()
        audioTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                "sound_summon_digimon_dtector",
                enabled: game.state.soundEnabled
            )
        }
        battleFX.play(
            .sequence([
                .callPower(remainingCallPower),
                .summon(.player, duration: 8.17),
                .spiritReady
            ])
        ) {
            battleFX.stop(resetToIdle: true)
        }
    }

    private func playScannedDigiPower(
        remainingCallPower: Int,
        helperResource: String,
        spiritResource: String,
        succeeds: Bool
    ) {
        audioTask?.cancel()
        audioTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_500_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                succeeds
                    ? "sound_digipower_success_dtector"
                    : "sound_digipower_fail_dtector",
                enabled: game.state.soundEnabled
            )
        }
        battleFX.play(
            .sequence([
                .callPower(remainingCallPower),
                .spiritPower(game.state.dPower),
                .digiPower(
                    spec: BattleDigiPowerSpec(
                        helperResource: helperResource,
                        spiritResource: spiritResource,
                        succeeds: succeeds
                    )
                )
            ])
        ) {
            battleFX.stop(resetToIdle: true)
        }
    }

    private func playSpiritCheck() {
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
        battleFX.play(.spiritCheck(game.state.dPower)) {
            battleFX.stop(resetToIdle: true)
        }
    }

    private func resetClassicScanner() {
        scannerTask?.cancel()
        scannerTask = nil
        scannerGeneration += 1
        scannerStage = .prompt
        scannerBits = []
        scannerCaptureEnabled = false
    }

    private func stopClassicScanner() {
        scannerTask?.cancel()
        scannerTask = nil
        scannerGeneration += 1
        scannerCaptureEnabled = false
    }

    private func handleClassicScannerTap() {
        switch scannerStage {
        case .prompt:
            beginClassicScanner()
        case .arming, .finishing:
            break
        case .streaming:
            guard scannerCaptureEnabled else {
                GameAudio.shared.play(
                    "sound_cancel",
                    enabled: game.state.soundEnabled
                )
                return
            }
            registerClassicScanBit(1)
        }
    }

    private func beginClassicScanner() {
        scannerTask?.cancel()
        scannerGeneration += 1
        let generation = scannerGeneration
        scannerCaptureEnabled = false
        scannerStage = .arming(Date())
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )

        scannerTask = Task { @MainActor in
            // One remaining 15-step prompt alarm plus the 30-step arming hold.
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled,
                  generation == scannerGeneration,
                  game.battle?.phase == .scanning else { return }
            scannerStage = .streaming(Date())
            scannerCaptureEnabled = true
            WKInterfaceDevice.current().play(.start)
        }
    }

    private func registerClassicScanBit(_ bit: Int) {
        guard scannerBits.count < 3 else { return }
        scannerTask?.cancel()
        scannerTask = nil
        scannerGeneration += 1
        scannerBits.append(bit == 0 ? 0 : 1)
        scannerCaptureEnabled = false
        WKInterfaceDevice.current().play(bit == 0 ? .click : .success)

        if scannerBits.count == 3 {
            let completedBits = scannerBits
            let streamStart: Date
            switch scannerStage {
            case .streaming(let startedAt), .finishing(let startedAt):
                streamStart = startedAt
            default:
                streamStart = Date()
            }
            scannerStage = .finishing(streamStart)
            let generation = scannerGeneration
            scannerTask = Task { @MainActor in
                // Original Alarm 3 resolves 30 source steps after bit three.
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled,
                      generation == scannerGeneration,
                      game.battle?.phase == .scanning else { return }
                finishClassicScan(completedBits)
            }
            return
        }

        scheduleClassicScanWindow()
    }

    private func scheduleClassicScanWindow() {
        let generation = scannerGeneration
        scannerTask = Task { @MainActor in
            // Alarm 1: scanner lamp off for 90 source steps.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                  generation == scannerGeneration,
                  game.battle?.phase == .scanning else { return }
            scannerCaptureEnabled = true
            WKInterfaceDevice.current().play(.start)

            // Alarm 2: missing this 90-step window records a zero.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                  generation == scannerGeneration,
                  scannerCaptureEnabled,
                  game.battle?.phase == .scanning else { return }
            registerClassicScanBit(0)
        }
    }

    private func playRound(
        before: BattleSession,
        after: BattleSession,
        snapshot: BattleVisualSnapshot,
        showsPowerSpend: Bool = false
    ) {
        visualSnapshot = snapshot

        let outcome: Int
        if after.enemyID != before.enemyID
            || after.enemyHP < before.enemyHP
            || after.result == .win
            || after.phase == .capture {
            outcome = 1
        } else if after.activeHP < before.activeHP
            || after.result == .lose {
            outcome = -1
        } else {
            outcome = 0
        }

        let damage: Int
        if outcome > 0 {
            // A final boss refreshes to the evolved form's full HP in the
            // model, so the visible hit still represents all remaining HP.
            damage = after.enemyID != before.enemyID
                ? before.enemyHP
                : max(0, before.enemyHP - after.enemyHP)
        } else if outcome < 0 {
            damage = max(0, before.activeHP - after.activeHP)
        } else {
            damage = 0
        }
        let referenceHP = outcome > 0
            ? max(1, before.enemyHP)
            : max(1, before.activeMaxHP)
        let critical = damage * 2 >= referenceHP

        let winningMove = BattlePresentationMove(
            moveID: outcome >= 0 ? after.mineMove : after.enemyMove
        )
        scheduleRoundAudio(
            outcome: outcome,
            winningMove: winningMove,
            powerDelay: showsPowerSpend
        )
        var roundTimeline = BattlePresentationTimeline.round(
            playerMove: BattlePresentationMove(moveID: after.mineMove),
            enemyMove: BattlePresentationMove(moveID: after.enemyMove),
            outcome: outcome,
            critical: critical
        )
        if after.result == .none, after.activeDigimonID != nil {
            roundTimeline = roundTimeline.appending(.spiritReady)
        }
        let timeline = showsPowerSpend
            ? BattlePresentationTimeline.sequence([
                .spiritPower(game.state.dPower),
                roundTimeline
            ])
            : roundTimeline

        battleFX.play(timeline) {
            continueRoundPresentation(
                before: before,
                after: after,
                snapshot: snapshot
            )
        }
    }

    private func continueRoundPresentation(
        before: BattleSession,
        after: BattleSession,
        snapshot: BattleVisualSnapshot
    ) {
        if after.enemyID != before.enemyID {
            let evolved = game.combatant(for: after.enemyID)
            var evolvedSnapshot = snapshot
            evolvedSnapshot.activeHP = after.activeHP
            evolvedSnapshot.activeMaxHP = after.activeMaxHP
            evolvedSnapshot.enemy = presentationSprite(
                for: evolved,
                mirrored: true
            )
            evolvedSnapshot.enemyName = evolved.name
            evolvedSnapshot.enemyHP = after.enemyHP
            evolvedSnapshot.enemyMaxHP = evolved.maxHP
            visualSnapshot = evolvedSnapshot

            GameAudio.shared.play(
                "sound_evo_boss",
                enabled: game.state.soundEnabled
            )
            battleFX.play(
                .enemyEvolution(
                    spec: BattleEnemyEvolutionSpec(
                        oldResource: snapshot.enemy.resource,
                        newResource: evolved.sprite
                    )
                )
            ) {
                visualSnapshot = nil
                battleFX.stop(resetToIdle: true)
            }
            return
        }

        if before.activeDigimonID != nil,
           after.activeDigimonID == nil,
           after.result == .none {
            var departingSnapshot = snapshot
            departingSnapshot.enemyHP = after.enemyHP
            visualSnapshot = departingSnapshot

            let departingID = before.activeDigimonID ?? -1
            let departing = game.combatant(for: departingID)
            let timeline: BattlePresentationTimeline
            let sound: String

            if departing.type == "spirit",
               (100...111).contains(departingID) {
                let owner = (departingID - 100) / 2
                timeline = .spiritOff(
                    .player,
                    spec: BattleSpiritOffSpec(
                        evolvedResource: snapshot.player.resource,
                        characterResource:
                            game.catalog.characters[owner].sprite
                    )
                )
                sound = "sound_spirit_off_dtector"
            } else {
                timeline = .deport(.player)
                sound = "sound_deport_dtector"
            }

            GameAudio.shared.play(
                sound,
                enabled: game.state.soundEnabled
            )
            battleFX.play(timeline) {
                visualSnapshot = nil
                battleFX.stop(resetToIdle: true)
            }
            return
        }

        var resolvedSnapshot = snapshot
        resolvedSnapshot.activeHP = after.activeHP
        resolvedSnapshot.activeMaxHP = after.activeMaxHP
        resolvedSnapshot.enemyHP = after.enemyHP
        visualSnapshot = resolvedSnapshot

        if after.result == .win || after.result == .lose,
           let activeID = before.activeDigimonID {
            let active = game.combatant(for: activeID)
            let departure: BattlePresentationTimeline
            let departureSound: String

            if active.type == "spirit",
               (100...111).contains(activeID) {
                let owner = (activeID - 100) / 2
                departure = .spiritOff(
                    .player,
                    spec: BattleSpiritOffSpec(
                        evolvedResource: snapshot.player.resource,
                        characterResource:
                            game.catalog.characters[owner].sprite
                    )
                )
                departureSound = "sound_spirit_off_dtector"
            } else {
                departure = .deport(.player)
                departureSound = "sound_deport_dtector"
            }

            GameAudio.shared.play(
                departureSound,
                enabled: game.state.soundEnabled
            )
            battleFX.play(
                .sequence([
                    departure,
                    .characterReturn(
                        resource: game.currentCharacter.sprite
                    )
                ])
            ) {
                visualSnapshot = nil
                battleFX.stop(resetToIdle: true)
                playResultPresentation(for: after) {
                    beginAutomaticResultReturn(after.result)
                }
            }
            return
        }

        playResultPresentation(for: after) {
            visualSnapshot = nil
            battleFX.stop(resetToIdle: true)
            beginAutomaticResultReturn(after.result)
        }
    }

    private func beginAutomaticResultReturn(
        _ result: BattleSession.Result
    ) {
        guard result == .win || result == .lose else { return }
        resultReturnTask?.cancel()
        let delay: UInt64
        if game.battle?.lostSpiritID != nil {
            delay = 16_600_000_000
        } else {
            delay = result == .win
                ? 4_000_000_000
                : 4_500_000_000
        }
        resultReturnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  game.battle?.phase == .result else { return }
            game.continueAfterBattle()
        }
    }

    private func playResultPresentation(
        for battle: BattleSession,
        completion: @escaping () -> Void
    ) {
        switch battle.result {
        case .win:
            GameAudio.shared.play(
                battle.levelChange > 0
                    ? "sound_level_up_dtector"
                    : "sound_char_happy_long",
                enabled: game.state.soundEnabled
            )
            completion()
        case .lose:
            GameAudio.shared.play(
                battle.lostSpiritID != nil
                    ? "sound_attack_travel"
                    : battle.levelChange < 0
                        ? "sound_level_down_dtector"
                        : "sound_lose_dtector",
                enabled: game.state.soundEnabled,
                loops: battle.lostSpiritID != nil
            )
            completion()
        case .none, .escaped:
            completion()
        }
    }

    private func scheduleRoundAudio(
        outcome: Int,
        winningMove: BattlePresentationMove,
        powerDelay: Bool
    ) {
        audioTask?.cancel()
        audioTask = Task { @MainActor in
            if powerDelay {
                try? await Task.sleep(nanoseconds: 5_500_000_000)
                guard !Task.isCancelled else { return }
            }
            // Original cadence at 60 steps/s:
            // 15 neutral + 30 anticipation before each launch.
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                "sound_launch_attack",
                enabled: game.state.soundEnabled
            )
            // The complete player launch object lasts 141 steps (2.35 s).
            try? await Task.sleep(nanoseconds: 2_350_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                "sound_launch_attack",
                enabled: game.state.soundEnabled
            )
            // Enemy travel completes 96 steps after its launch.
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                "sound_attack_travel",
                enabled: game.state.soundEnabled
            )
            guard outcome != 0, winningMove != .ability else { return }
            // The collision resolves at +3.05 s. The original hit object then
            // reaches its first flash after 0.50 s for Energy and 2.75 s for
            // Crunch. Ability bypasses the flash and explosion sound.
            let hitFlashDelay: UInt64 = winningMove == .energy
                ? 500_000_000
                : 2_750_000_000
            try? await Task.sleep(
                nanoseconds: 3_050_000_000 + hitFlashDelay
            )
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                "sound_explode_dtector",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func playSummon(
        evolution: Bool,
        ancient: Bool = false
    ) {
        visualSnapshot = nil
        let activeID = game.battle?.activeDigimonID
        if ancient {
            GameAudio.shared.play(
                "sound_evo_ancient_dtector",
                enabled: game.state.soundEnabled
            )
        } else if evolution,
                  let activeID,
                  (100...111).contains(activeID) {
            let owner = (activeID - 100) / 2
            if owner != game.state.currentCharacter {
                GameAudio.shared.play(
                    "sound_swap_char_dtector",
                    enabled: game.state.soundEnabled
                )
                audioTask?.cancel()
                audioTask = Task { @MainActor in
                    try? await Task.sleep(
                        nanoseconds: 3_050_000_000
                    )
                    guard !Task.isCancelled else { return }
                    GameAudio.shared.play(
                        "sound_evo_sprite_dtector",
                        enabled: game.state.soundEnabled
                    )
                }
            } else {
                GameAudio.shared.play(
                    "sound_evo_sprite_dtector",
                    enabled: game.state.soundEnabled
                )
            }
        } else {
            GameAudio.shared.play(
                evolution
                    ? "sound_evo_dtector"
                    : "sound_summon_digimon_dtector",
                enabled: game.state.soundEnabled
            )
        }
        let timeline: BattlePresentationTimeline

        if ancient,
           let activeID = game.battle?.activeDigimonID,
           (122...127).contains(activeID) {
            let characterID = activeID - 122
            let character = game.catalog.characters[
                min(
                    game.catalog.characters.count - 1,
                    max(0, characterID)
                )
            ]
            timeline = .sequence([
                .spiritPower(game.state.dPower),
                .ancientEvolution(
                    .player,
                    spec: BattleAncientEvolutionSpec(
                        characterResource: character.sprite,
                        firstSpiritFrame: characterID * 2,
                        secondSpiritFrame: characterID * 2 + 1,
                        evolvedResource: game.combatant(for: activeID).sprite
                    )
                )
            ])
        } else if evolution,
                  let activeID = game.battle?.activeDigimonID,
                  (100...111).contains(activeID) {
            let spiritFrame = activeID - 100
            let characterID = spiritFrame / 2
            let character = game.catalog.characters[
                min(
                    game.catalog.characters.count - 1,
                    max(0, characterID)
                )
            ]
            timeline = .spiritEvolution(
                .player,
                spec: BattleSpiritEvolutionSpec(
                    oldCharacterResource: game.currentCharacter.sprite,
                    newCharacterResource: character.sprite,
                    spiritFrame: spiritFrame,
                    evolvedResource: game.combatant(for: activeID).sprite,
                    swapsCharacter:
                        characterID != game.state.currentCharacter
                )
            )
        } else if evolution {
            timeline = .evolution(.player)
        } else {
            timeline = .summon(.player)
        }

        battleFX.play(
            timeline.appending(.spiritReady)
        ) {
            battleFX.stop(resetToIdle: true)
        }
    }

    private func summonFromCode() {
        let previousID = game.battle?.activeDigimonID
        game.summonBattleCode()
        guard game.battle?.activeDigimonID != previousID else { return }
        playSummon(
            evolution: game.activeCombatant?.type == "spirit"
                || game.activeCombatant?.type == "ancient",
            ancient: game.activeCombatant?.type == "ancient"
        )
    }

    private func attemptEvolution() {
        let previousID = game.battle?.activeDigimonID
        game.attemptEvolution()
        guard game.battle?.activeDigimonID != previousID else {
            GameAudio.shared.play(
                "sound_digipower_fail_dtector",
                enabled: game.state.soundEnabled
            )
            return
        }
        playSummon(
            evolution: true,
            ancient: game.activeCombatant?.type == "ancient"
        )
    }

    private func deportActive() {
        guard let before = game.battle else { return }
        visualSnapshot = makeVisualSnapshot(for: before)
        let activeID = before.activeDigimonID ?? -1
        let active = before.activeDigimonID.map { game.combatant(for: $0) }
        game.swapActiveDigimon()
        let timeline: BattlePresentationTimeline
        let sound: String

        if active?.type == "spirit", (100...111).contains(activeID) {
            let owner = (activeID - 100) / 2
            timeline = .spiritOff(
                .player,
                spec: BattleSpiritOffSpec(
                    evolvedResource: active?.sprite
                        ?? playerVisual.resource,
                    characterResource:
                        game.catalog.characters[owner].sprite
                )
            )
            sound = "sound_spirit_off_dtector"
        } else {
            timeline = .deport(.player)
            sound = "sound_deport_dtector"
        }
        GameAudio.shared.play(
            sound,
            enabled: game.state.soundEnabled
        )
        battleFX.play(timeline) {
            visualSnapshot = nil
            battleFX.stop(resetToIdle: true)
        }
    }

    private func captureEnemy() {
        guard let before = game.battle, before.phase == .capture else { return }
        visualSnapshot = makeVisualSnapshot(for: before)
        game.captureEnemy()
        GameAudio.shared.play(
            "sound_catch_dtector",
            enabled: game.state.soundEnabled
        )
        battleFX.play(.capture(.enemy)) {
            visualSnapshot = nil
            battleFX.stop(resetToIdle: true)
            beginAutomaticResultReturn(.win)
        }
    }

    private func moveLabel(_ move: BattlePresentationMove) -> String {
        switch move {
        case .energy: "ENERGY"
        case .crunch: "CRUNCH"
        case .ability: "ABILITY"
        }
    }

    private func resultLabel(_ result: BattleSession.Result) -> String {
        switch result {
        case .win: "CLEAR • CONTINUE"
        case .lose: "REBOOT • CONTINUE"
        case .escaped: "RETURN"
        case .none: "CONTINUE"
        }
    }
}

struct DigiStormView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ScreenHeader(title: "DIGI-STORM") {
                if game.storm?.outcome != .active {
                    game.continueAfterStorm()
                }
            }
            if let storm = game.storm {
                DetectorScreen(
                    content: {
                        stormStage(storm)
                            .frame(height: 108)
                    },
                    accent: .red,
                    showGrid: game.state.gridEnabled
                )

                if storm.outcome == .active {
                    Button("RESIST \(storm.taps)/\(storm.target)") {
                        game.tapDigiStorm()
                    }
                    .buttonStyle(DetectorButtonStyle(tint: .red))
                } else {
                    Button("CONTINUE") {
                        game.continueAfterStorm()
                    }
                    .buttonStyle(DetectorButtonStyle(tint: .green))
                }
            }
        }
        .task(id: game.storm?.deadline) {
            guard let deadline = game.storm?.deadline else { return }
            let seconds = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled,
                  let current = game.storm,
                  current.deadline == deadline,
                  current.outcome == .active else { return }
            game.resolveDigiStorm()
        }
        .onAppear {
            playStormOutcome(game.storm?.outcome)
        }
        .onChange(of: game.storm?.outcome) { _, outcome in
            playStormOutcome(outcome)
        }
        .onDisappear {
            GameAudio.shared.stop()
        }
    }

    @ViewBuilder
    private func stormStage(_ storm: DigiStormSession) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geometry in
                let start = storm.deadline.addingTimeInterval(-8.2)
                let elapsed = max(0, context.date.timeIntervalSince(start))
                let stepFrame = Int(elapsed / 0.12) % 2

                ZStack {
                    stormActor(
                        storm,
                        stepFrame: stepFrame,
                        elapsed: elapsed,
                        size: geometry.size
                    )

                    if storm.outcome == .active {
                        activeStormLayer(
                            elapsed: elapsed,
                            taps: storm.taps,
                            size: geometry.size
                        )
                    }

                    VStack(spacing: 3) {
                        Spacer()
                        Text(stormText(storm))
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 4)
                            .background(DetectorPalette.screenBright.opacity(0.78))
                        Meter(
                            value: Double(storm.taps) / Double(storm.target),
                            color: DetectorPalette.danger
                        )
                        if storm.outcome == .active {
                            Text(
                                "\(max(0, storm.deadline.timeIntervalSince(context.date)), specifier: "%.1f") SEC"
                            )
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stormText(storm))
        .accessibilityValue("\(storm.taps) of \(storm.target)")
    }

    @ViewBuilder
    private func activeStormLayer(
        elapsed: TimeInterval,
        taps: Int,
        size: CGSize
    ) -> some View {
        let duration = reduceMotion ? 2.6 : 1.65
        let progress = elapsed.truncatingRemainder(dividingBy: duration) / duration
        let secondProgress = (progress + 0.50).truncatingRemainder(dividingBy: 1)
        let tapKick = reduceMotion ? 0.0 : CGFloat((taps % 2) * 3)

        Group {
            GameSprite(resource: "spr_digistorm_dtector", size: 105)
                .position(
                    x: stormX(progress: progress, width: size.width) + tapKick,
                    y: size.height * 0.43
                )
            GameSprite(resource: "spr_digistorm_dtector", size: 105)
                .position(
                    x: stormX(progress: secondProgress, width: size.width) - tapKick,
                    y: size.height * 0.43
                )
        }
        .opacity(reduceMotion ? 0.70 + 0.20 * sin(elapsed * 4) : 0.88)
    }

    @ViewBuilder
    private func stormActor(
        _ storm: DigiStormSession,
        stepFrame: Int,
        elapsed: TimeInterval,
        size: CGSize
    ) -> some View {
        let actor = "\(game.currentCharacter.sprite)_step"
        let pulse = 0.82 + 0.18 * abs(sin(elapsed * 5))

        switch storm.outcome {
        case .active:
            GameSprite(resource: actor, frame: stepFrame, size: 62)
                .position(x: size.width * 0.30, y: size.height * 0.43)
                .opacity(pulse)
        case .safe:
            GameSprite(resource: actor, frame: stepFrame, size: 66)
                .position(
                    x: reduceMotion
                        ? size.width * 0.50
                        : size.width * CGFloat(0.38 + min(0.12, elapsed * 0.10)),
                    y: size.height * 0.43
                )
        case .partyLost:
            ZStack {
                GameSprite(resource: "spr_question_dtector", size: 34)
                    .position(x: size.width * 0.46, y: size.height * 0.18)
                GameSprite(resource: actor, frame: stepFrame, size: 62)
                    .position(
                        x: reduceMotion
                            ? size.width * 0.50
                            : size.width * CGFloat(min(0.88, 0.34 + elapsed * 0.24)),
                        y: size.height * 0.44
                    )
            }
        case .teleported:
            ZStack {
                GameSprite(resource: actor, frame: stepFrame, size: 62)
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: Int(elapsed / 0.16) % 2,
                    size: 106
                )
                .opacity(pulse)
            }
            .position(x: size.width * 0.50, y: size.height * 0.43)
        case .partyRecovered:
            GameSprite(resource: actor, frame: stepFrame, size: 66)
                .position(
                    x: reduceMotion
                        ? size.width * 0.50
                        : size.width * CGFloat(min(0.50, 0.08 + elapsed * 0.25)),
                    y: size.height * 0.43
                )
        }
    }

    private func stormX(progress: Double, width: CGFloat) -> CGFloat {
        guard !reduceMotion else { return width * 0.58 }
        return width * (1.20 - CGFloat(progress) * 1.42)
    }

    private func playStormOutcome(_ outcome: DigiStormSession.Outcome?) {
        guard let outcome else { return }
        switch outcome {
        case .active:
            GameAudio.shared.play(
                "sound_digistorm_dtector",
                enabled: game.state.soundEnabled,
                loops: true
            )
        case .safe:
            GameAudio.shared.stop()
        case .partyLost:
            GameAudio.shared.play(
                "sound_lose_dtector",
                enabled: game.state.soundEnabled
            )
        case .teleported:
            GameAudio.shared.play(
                "sound_catch_dtector",
                enabled: game.state.soundEnabled
            )
        case .partyRecovered:
            GameAudio.shared.play(
                "sound_summon_digimon_dtector",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func stormText(_ storm: DigiStormSession) -> String {
        switch storm.outcome {
        case .active:
            "TAP FAST"
        case .safe:
            "STORM CLEARED"
        case .partyLost(let ids):
            "PARTY LOST\n\(ids.map(String.init).joined(separator: ","))"
        case .teleported(let area):
            storm.lostParty.isEmpty
                ? "TELEPORTED\nAREA \(area + 1)"
                : "PARTY LOST \(storm.lostParty.count)\nAREA \(area + 1)"
        case .partyRecovered:
            "MISSING PARTY\nRECOVERED"
        }
    }
}

struct MiniGameView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var actionStartedAt: Date?
    @State private var selectedChoice: Int?
    @State private var targetSnapshot: Int?
    @State private var actionSucceeded = false
    @State private var actionTask: Task<Void, Never>?
    @State private var showsScore = ProcessInfo.processInfo.arguments.contains(
        "-qa-digiship-score"
    )

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            drawsViewport: true,
            onStageTap: {
                handleInput(2)
            },
            onLeft: {
                handleInput(0)
            },
            onCancel: {
                game.closeMiniGame()
            },
            onAccept: {
                handleInput(1)
            }
        ) {
            if let mini = game.miniGame {
                miniGameStage(mini)
            }
        }
        .accessibilityLabel(gameTitle)
        .accessibilityHint(
            "Tap left, center, or right. Hold to return."
        )
        .onDisappear {
            actionTask?.cancel()
            actionTask = nil
            GameAudio.shared.stop()
        }
        .onAppear {
            guard game.miniGame?.kind == .digiShip else { return }
            GameAudio.shared.play(
                "sound_rocket_start",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func handleInput(_ choice: Int) {
        guard actionStartedAt == nil,
              let mini = game.miniGame else { return }
        if mini.finished {
            GameAudio.shared.play(
                "sound_select",
                enabled: game.state.soundEnabled
            )
            if mini.kind == .digiShip && !showsScore {
                showsScore = true
            } else {
                game.closeMiniGame()
            }
        } else {
            play(choice, in: mini)
        }
    }

    @ViewBuilder
    private func miniGameStage(_ mini: MiniGameSession) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            GeometryReader { geometry in
                if mini.kind == .digiDigit {
                    digiDigitStage(mini, at: context.date, size: geometry.size)
                } else {
                    digiShipStage(mini, at: context.date, size: geometry.size)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            mini.kind == .digiDigit
                ? "Scan Break. Match \(moveName(targetSnapshot ?? mini.targetMove))"
                : "Digi Ship. Avoid lane \((targetSnapshot ?? mini.targetMove) + 1)"
        )
    }

    @ViewBuilder
    private func digiDigitStage(
        _ mini: MiniGameSession,
        at date: Date,
        size: CGSize
    ) -> some View {
        let elapsed = actionStartedAt.map { max(0, date.timeIntervalSince($0)) }
        let target = targetSnapshot ?? mini.targetMove
        let idleTick = Int(date.timeIntervalSinceReferenceDate / 0.18)
        let attackFrame = elapsed.map { min(3, 1 + Int($0 / 0.14) % 3) } ?? 0
        let projectileProgress = min(1, max(0, (elapsed ?? 0) / 0.48))

        ZStack {
            if let id = mini.usedDigimonID,
               let digimon = game.catalog.digimon.first(where: { $0.id == id }) {
                GameSprite(resource: digimon.sprite, frame: attackFrame, size: 61)
                    .position(x: size.width * 0.27, y: size.height * 0.52)
            }

            GameSprite(
                resource: "spr_box_dtector",
                frame: elapsed == nil ? idleTick % 2 : 1,
                size: 60
            )
            .position(x: size.width * 0.73, y: size.height * 0.53)

            GameSprite(resource: "spr_use_move_dtector", frame: target, size: 42)
                .position(x: size.width * 0.50, y: size.height * 0.18)

            if elapsed == nil, idleTick.isMultiple(of: 3) {
                GameSprite(resource: "spr_use_move_dtector", frame: 3, size: 42)
                    .position(x: size.width * 0.50, y: size.height * 0.18)
            }

            if let elapsed {
                if elapsed < 0.58 {
                    GameSprite(
                        resource: "spr_energy_dtector",
                        frame: Int(elapsed / 0.045) % 12,
                        size: 45
                    )
                    .position(
                        x: size.width * CGFloat(0.31 + projectileProgress * 0.40),
                        y: size.height * 0.52
                    )
                }

                if elapsed >= 0.43 {
                    GameSprite(
                        resource: actionSucceeded
                            ? "spr_hit_dtector"
                            : "spr_empty_dtector",
                        frame: actionSucceeded ? Int(elapsed / 0.09) % 2 : 0,
                        size: 72
                    )
                    .position(x: size.width * 0.73, y: size.height * 0.53)
                    .opacity(reduceMotion ? 1 : 0.72 + 0.28 * abs(sin(elapsed * 18)))
                }
            }

        }
    }

    @ViewBuilder
    private func digiShipStage(
        _ mini: MiniGameSession,
        at date: Date,
        size: CGSize
    ) -> some View {
        let elapsed = actionStartedAt.map { max(0, date.timeIntervalSince($0)) }
        let target = targetSnapshot ?? mini.targetMove
        let lane = selectedChoice ?? 1
        let screenFrame = mini.round <= 1
            ? 0
            : min(4, max(1, mini.score / 10 + 1))
        let obstacleProgress = min(1, max(0, (elapsed ?? 0) / 0.45))
        let obstacleY = elapsed == nil
            ? size.height * 0.28
            : size.height * CGFloat(0.18 + obstacleProgress * 0.55)
        let logicalScale = min(size.width / 30, size.height / 32)
        let logicalOrigin = CGPoint(
            x: (size.width - 30 * logicalScale) / 2,
            y: (size.height - 32 * logicalScale) / 2
        )

        ZStack {
            GameSprite(
                resource: "spr_game2_screen_dtector",
                frame: screenFrame,
                size: 130
            )
            .position(x: size.width * 0.50, y: size.height * 0.50)
            .opacity(0.78)

            if mini.round == 1, elapsed == nil, !mini.finished {
                GameSprite(resource: "spr_game2_start_dtector", size: 70)
                    .position(x: size.width * 0.50, y: size.height * 0.24)
            }

            GameSprite(resource: "spr_game2_collision_dtector", size: 36)
                .position(x: laneX(target, width: size.width), y: obstacleY)

            GameSprite(resource: "spr_game2_ship_dtector", size: 38)
                .position(
                    x: laneX(lane, width: size.width),
                    y: size.height * CGFloat(
                        reduceMotion
                            ? 0.76
                            : 0.76 + 0.02 * sin(date.timeIntervalSinceReferenceDate * 8)
                    )
                )

            if let elapsed, !actionSucceeded, elapsed >= 0.34 {
                GameSprite(resource: "spr_game2_break_dtector", size: 96)
                    .position(x: laneX(lane, width: size.width), y: size.height * 0.70)
                    .opacity(reduceMotion ? 1 : 0.65 + 0.35 * abs(sin(elapsed * 15)))
            }

            if mini.finished, actionStartedAt == nil, showsScore {
                Rectangle()
                    .fill(DetectorPalette.screen)
                    .frame(
                        width: 30 * logicalScale,
                        height: 32 * logicalScale
                    )
                    .position(x: size.width / 2, y: size.height / 2)
                ClassicLCDSprite(
                    resource: "spr_game2_score_dtector",
                    frame: 1
                )
                .frame(
                    width: 30 * logicalScale,
                    height: 32 * logicalScale
                )
                .position(x: size.width / 2, y: size.height / 2)
                ClassicLCDNumber(
                    value: mini.score,
                    white: false,
                    scale: logicalScale
                )
                .position(
                    x: logicalOrigin.x
                        + ClassicLCDNumber.logicalCenter(
                            for: mini.score,
                            leastSignificantX: 26
                        ) * logicalScale,
                    y: logicalOrigin.y + 11.5 * logicalScale
                )
                ClassicLCDNumber(
                    value: game.state.distance,
                    white: false,
                    scale: logicalScale
                )
                .position(
                    x: logicalOrigin.x
                        + ClassicLCDNumber.logicalCenter(
                            for: game.state.distance,
                            leastSignificantX: 26
                        ) * logicalScale,
                    y: logicalOrigin.y + 27.5 * logicalScale
                )
            } else if mini.finished, actionStartedAt == nil {
                Rectangle()
                    .fill(DetectorPalette.screen)
                    .frame(
                        width: 30 * logicalScale,
                        height: 32 * logicalScale
                    )
                    .position(x: size.width / 2, y: size.height / 2)
                ClassicLCDSprite(
                    resource: "spr_game2_screen_dtector",
                    frame: 0
                )
                .frame(
                    width: 30 * logicalScale,
                    height: 32 * logicalScale
                )
                .position(x: size.width / 2, y: size.height / 2)
                if Int(
                    date.timeIntervalSinceReferenceDate / 0.50
                ).isMultiple(of: 2) {
                    ClassicLCDSprite(
                        resource: mini.lives > 0
                            ? "spr_game2_goal_dtector"
                            : "spr_game2_over_dtector",
                        frame: 0
                    )
                    .frame(
                        width: 30 * logicalScale,
                        height: 32 * logicalScale
                    )
                    .position(x: size.width / 2, y: size.height / 2)
                }
            } else if mini.finished {
                ClassicLCDSprite(
                    resource: "spr_game2_finish_dtector",
                    frame: 0
                )
                .frame(
                    width: 30 * logicalScale,
                    height: 32 * logicalScale
                )
                .position(x: size.width / 2, y: size.height / 2)
            }
        }
    }

    private func laneX(_ lane: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(0.22 + Double(max(0, min(2, lane))) * 0.28)
    }

    private func play(_ choice: Int, in mini: MiniGameSession) {
        guard actionStartedAt == nil, !mini.finished else { return }
        actionTask?.cancel()
        selectedChoice = choice
        targetSnapshot = mini.targetMove
        actionSucceeded = mini.kind == .digiDigit
            ? choice == mini.targetMove
            : choice != mini.targetMove
        actionStartedAt = Date()

        GameAudio.shared.play(
            mini.kind == .digiDigit
                ? "sound_launch_attack"
                : "sound_rocket_asteroid",
            enabled: game.state.soundEnabled
        )

        let kind = mini.kind
        let succeeded = actionSucceeded
        actionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 430_000_000)
            guard !Task.isCancelled else { return }
            GameAudio.shared.play(
                kind == .digiDigit
                    ? (
                        succeeded
                            ? "sound_explode_dtector"
                            : "sound_digipower_fail_dtector"
                    )
                    : (
                        succeeded
                            ? "sound_char_happy_small"
                            : "sound_rocket_crash"
                    ),
                enabled: game.state.soundEnabled
            )

            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            if kind == .digiDigit {
                game.playDigiDigit(move: choice)
            } else {
                game.playDigiShip(lane: choice)
                if game.miniGame?.finished == true,
                   (game.miniGame?.lives ?? 0) > 0 {
                    GameAudio.shared.play(
                        "sound_rocket_goal",
                        enabled: game.state.soundEnabled
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            actionStartedAt = nil
            selectedChoice = nil
            targetSnapshot = nil
            actionTask = nil
        }
    }

    private var gameTitle: String {
        game.miniGame?.kind == .digiDigit ? "SCAN BREAK" : "DIGI-SHIP"
    }

    private func moveName(_ move: Int) -> String {
        switch move {
        case 0: "ENE"
        case 1: "CRU"
        default: "ABI"
        }
    }
}

struct ConnectBattleView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        VStack(spacing: 7) {
            ScreenHeader(title: "OFFLINE LINK") {
                game.navigate(.connect)
            }
            DetectorScreen(
                content: {
                    VStack(spacing: 4) {
                        HStack {
                            dockSprite(game.state.docks.first ?? -1)
                            Text("VS")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                            dockSprite(game.connectOpponent.first ?? -1)
                        }
                        HStack {
                            Text("YOU \(game.connectPlayerScore)")
                            Spacer()
                            Text("\(game.connectOpponentScore) LINK")
                        }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                    .padding(8)
                },
                accent: .purple,
                showGrid: game.state.gridEnabled
            )

            Text(game.connectMessage)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .multilineTextAlignment(.center)
            if game.connectRound <= 5 {
                HStack(spacing: 4) {
                    Button("ENE") { game.playConnectMove(0) }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .red))
                    Button("CRU") { game.playConnectMove(1) }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .orange))
                    Button("ABI") { game.playConnectMove(2) }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .cyan))
                }
            } else {
                Button("LINK END") { game.navigate(.connect) }
                    .buttonStyle(DetectorButtonStyle(tint: .purple))
            }
        }
        .onAppear {
            GameAudio.shared.play(
                "sound_ready_go",
                enabled: game.state.soundEnabled
            )
        }
        .onChange(of: game.connectRound) { oldRound, newRound in
            guard newRound > oldRound else { return }
            GameAudio.shared.play(
                newRound > 5
                    ? "sound_evo_connect_dtector"
                    : "sound_evo_con_dtector",
                enabled: game.state.soundEnabled
            )
        }
    }

    @ViewBuilder
    private func dockSprite(_ id: Int) -> some View {
        if let digimon = game.catalog.digimon.first(where: { $0.id == id }) {
            GameSprite(resource: digimon.sprite, frame: 0, size: 62)
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: 34))
                .frame(width: 62, height: 62)
        }
    }
}
