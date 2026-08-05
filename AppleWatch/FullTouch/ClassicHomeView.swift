import SwiftUI

struct ClassicHomeView: View {
    @EnvironmentObject private var game: GameModel
    @StateObject private var wristShake = WristShakeService()
    @State private var walkingUntil: Date?
    @State private var lastPendingEncounter: EncounterKind?

    var body: some View {
        ClassicExpandedShell(
            drawsViewport: false,
            onStageTap: {
                openQuickStats()
            },
            onLeft: {
                openMenu()
            },
            onCancel: {
                // Home is already the root. A hold is intentionally a no-op;
                // short taps remain available for detector navigation.
            },
            onAccept: {
                simulateWalkingStep()
            }
        ) {
            classicCharacterLCD
        }
        .accessibilityLabel("D-Tector character screen")
        .accessibilityHint(
            "Tap left for menu, center to walk, right for stats, or shake your wrist"
        )
        .onAppear {
            wristShake.start {
                simulateWalkingStep()
            }
        }
        .onDisappear {
            wristShake.stop()
        }
        .onChange(of: game.pendingEncounter) { _, pending in
            guard pending != nil, pending != lastPendingEncounter else {
                lastPendingEncounter = pending
                return
            }
            lastPendingEncounter = pending
            GameAudio.shared.play(
                "sound_event_2",
                enabled: game.state.soundEnabled
            )
        }
    }

    private var classicCharacterLCD: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / 30,
                    geometry.size.height / 32
                )
                let viewportWidth = 30 * scale
                let viewportHeight = 32 * scale
                let originX = (geometry.size.width - viewportWidth) / 2
                let originY = (geometry.size.height - viewportHeight) / 2
                let walking = walkingUntil.map {
                    timeline.date < $0
                } ?? false
                let idleState = Int(
                    timeline.date.timeIntervalSinceReferenceDate * 2
                ) % 4
                let hasEncounter = game.pendingEncounter != nil
                let frame = game.state.defeated
                    ? 0
                    : walking
                    ? Int(
                        timeline.date.timeIntervalSinceReferenceDate / 0.12
                    ) % 2
                    : idleState % 2
                let mirrored = !walking && !hasEncounter && idleState >= 2

                ZStack {
                    DetectorPalette.screen

                    if game.state.gridEnabled {
                        PixelGrid()
                            .opacity(0.34)
                    }

                    ClassicPixelAsset(
                        resource: game.state.defeated
                            ? "\(game.currentCharacter.sprite)_defeat"
                            : walking
                            ? "\(game.currentCharacter.sprite)_step"
                            : hasEncounter
                                ? "\(game.currentCharacter.sprite)_attack"
                                : game.currentCharacter.sprite,
                        frame: frame
                    )
                    .frame(width: 24 * scale, height: 24 * scale)
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                    .position(
                        x: originX + 15 * scale,
                        y: originY + 16 * scale
                    )

                    if game.state.defeated && idleState.isMultiple(of: 2) {
                        ClassicLCDSprite(
                            resource: "spr_defeat_dtector",
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
                    } else if game.state.lastBossUnlocked {
                        ClassicLCDSprite(
                            resource: "spr_last_boss_char_dtector",
                            frame: idleState % 2
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

                    if game.pendingEncounter != nil,
                       Int(
                        timeline.date.timeIntervalSinceReferenceDate * 6
                       ).isMultiple(of: 2) {
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
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(DetectorPalette.ink, lineWidth: 2)
        }
    }

    private func simulateWalkingStep() {
        guard game.pendingEncounter == nil else {
            game.acceptEncounter()
            return
        }
        game.addSteps(1)
        walkingUntil = Date().addingTimeInterval(2.0)
    }

    private func openMenu() {
        guard game.pendingEncounter == nil else { return }
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
        game.openMainMenu()
    }

    private func openQuickStats() {
        guard game.pendingEncounter == nil else {
            game.acceptEncounter()
            return
        }
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
        game.navigate(.stats)
    }
}

/// The original `obj_stats_dtector` route opened directly from the character
/// screen's Right input. It is intentionally separate from the character
/// status selector in the main menu.
struct ClassicQuickStatsView: View {
    @EnvironmentObject private var game: GameModel
    @State private var page = 0

    var body: some View {
        ClassicExpandedShell(
            drawsViewport: false,
            onStageTap: nextPage,
            onLeft: previousPage,
            onCancel: close,
            onAccept: nextPage
        ) {
            statsLCD
        }
        .accessibilityLabel("D-Tector quick stats")
        .accessibilityValue("Page \(page + 1) of 7")
        .accessibilityHint(
            "Tap left for previous, center or right for next, hold to return"
        )
    }

    private var statsLCD: some View {
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

                if game.state.gridEnabled {
                    PixelGrid()
                        .opacity(0.34)
                }

                ClassicPixelAsset(
                    resource: "spr_stats_menu_dtector",
                    frame: page
                )
                .frame(width: viewportWidth, height: viewportHeight)
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                statsPageOverlay(
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(DetectorPalette.ink, lineWidth: 2)
        }
    }

    @ViewBuilder
    private func statsPageOverlay(
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        switch page {
        case 0:
            logicalNumber(
                game.state.distance,
                rightX: 25,
                topY: 8,
                scale: scale,
                origin: origin
            )
            logicalNumber(
                game.state.steps,
                rightX: 25,
                topY: 24,
                scale: scale,
                origin: origin
            )
        case 1:
            let percentage = game.state.battles > 0
                ? Int(
                    (Double(game.state.wins)
                        / Double(game.state.battles) * 100).rounded()
                )
                : 0
            logicalNumber(
                percentage,
                rightX: 18,
                topY: 8,
                scale: scale,
                origin: origin
            )
            logicalNumber(
                game.state.wins,
                rightX: 18,
                topY: 24,
                scale: scale,
                origin: origin
            )
        case 2:
            logicalNumber(
                game.state.dPower,
                rightX: 24,
                topY: 24,
                scale: scale,
                origin: origin
            )
        default:
            let dockIndex = page - 3
            if game.state.docks.indices.contains(dockIndex),
               game.state.docks[dockIndex] >= 0 {
                ClassicPixelAsset(
                    resource: game.combatant(
                        for: game.state.docks[dockIndex]
                    ).sprite,
                    frame: 0
                )
                .frame(width: 24 * scale, height: 24 * scale)
                .position(
                    x: origin.x + 15 * scale,
                    y: origin.y + 20 * scale
                )
            } else {
                ClassicPixelAsset(
                    resource: "spr_empty_dtector",
                    frame: 0
                )
                .frame(width: 24 * scale, height: 24 * scale)
                .position(
                    x: origin.x + 15 * scale,
                    y: origin.y + 20 * scale
                )
            }
        }
    }

    private func logicalNumber(
        _ value: Int,
        rightX: CGFloat,
        topY: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        return ClassicLCDNumber(
            value: value,
            white: false,
            scale: scale
        )
        .position(
            x: origin.x
                + ClassicLCDNumber.logicalCenter(
                    for: value,
                    leastSignificantX: rightX
                ) * scale,
            y: origin.y + (topY + 2.5) * scale
        )
    }

    private func nextPage() {
        page = (page + 1) % 7
        playSelect()
    }

    private func previousPage() {
        page = (page + 6) % 7
        playSelect()
    }

    private func close() {
        playSelect()
        game.goHome()
    }

    private func playSelect() {
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
    }
}
