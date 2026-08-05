import SwiftUI

/// Full-LCD connect presentation based on `obj_start_con_dtector`.
struct ClassicConnectBattleView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection = 0
    @State private var startedAt = Date()

    var body: some View {
        ClassicExpandedShell(
            drawsViewport: false,
            onStageTap: next,
            onLeft: previous,
            onCancel: cancel,
            onAccept: accept
        ) {
            connectLCD
        }
        .accessibilityLabel("D-Tector connect battle")
        .accessibilityValue(game.connectMessage)
        .onAppear {
            startedAt = Date()
            GameAudio.shared.play(
                "sound_alert_old",
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

    private var connectLCD: some View {
        TimelineView(.animation(minimumInterval: 0.10)) { timeline in
            GeometryReader { _ in
                let elapsed = max(
                    0,
                    timeline.date.timeIntervalSince(startedAt)
                )
                let counter = elapsed < 2.0
                    ? 0
                    : min(8, Int((elapsed - 2.0) / 0.20) + 1)
                let activeID = game.state.docks.first(where: { $0 >= 0 })
                    ?? 32
                let active = game.combatant(for: activeID)

                ZStack {
                    DetectorPalette.screen
                    if game.state.gridEnabled {
                        PixelGrid().opacity(0.34)
                    }

                    if counter == 0 {
                        ClassicLCDSprite(
                            resource: "spr_ok_con_dtector",
                            frame: 0
                        )
                    } else if counter < 6 {
                        ClassicLCDSprite(
                            resource: "spr_summon_dtector",
                            frame: counter.isMultiple(of: 2) ? 2 : 1
                        )
                    } else if counter < 8 {
                        ClassicBattleActorScreen(
                            resource: active.sprite,
                            frame: 0,
                            mirrored: false,
                            alert: false
                        )
                    } else if game.connectRound <= 5 {
                        ClassicLCDSprite(
                            resource: "spr_select_attack_dtector",
                            frame: selection
                        )
                    } else {
                        ClassicPostBattleCharacterScreen(
                            characterResource: game.currentCharacter.sprite,
                            enemyResource: active.sprite,
                            won: game.connectPlayerScore
                                > game.connectOpponentScore,
                            levelChange: 0,
                            lostSpiritID: nil
                        )
                    }
                }
            }
        }
        .aspectRatio(30.0 / 32.0, contentMode: .fit)
        .clipped()
        .overlay {
            Rectangle().stroke(DetectorPalette.ink, lineWidth: 2)
        }
    }

    private var introFinished: Bool {
        Date().timeIntervalSince(startedAt) >= 3.4
    }

    private func previous() {
        guard introFinished, game.connectRound <= 5 else { return }
        selection = (selection + 2) % 3
        playSelect()
    }

    private func next() {
        guard introFinished else { return }
        guard game.connectRound <= 5 else {
            game.navigate(.connect)
            return
        }
        selection = (selection + 1) % 3
        playSelect()
    }

    private func accept() {
        guard introFinished else { return }
        guard game.connectRound <= 5 else {
            game.navigate(.connect)
            return
        }
        game.playConnectMove(selection)
    }

    private func cancel() {
        guard introFinished else { return }
        GameAudio.shared.play(
            "sound_cancel",
            enabled: game.state.soundEnabled
        )
        game.navigate(.connect)
    }

    private func playSelect() {
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
    }
}
