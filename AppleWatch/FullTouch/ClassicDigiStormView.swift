import SwiftUI

/// Pixel-for-pixel presentation of `obj_digistorm_dtector`.
///
/// The original route owns the whole 30×32 LCD. It has no labels, progress
/// meter, or visible buttons: Right/Down presses are counted during the first
/// 82 source ticks and the rest is a non-interactive result animation.
struct ClassicDigiStormView: View {
    @EnvironmentObject private var game: GameModel
    @State private var stormStartedAt = Date()
    @State private var outcomeStartedAt: Date?
    @State private var continuationTask: Task<Void, Never>?

    var body: some View {
        ClassicExpandedShell(
            drawsViewport: false,
            onStageTap: press,
            onLeft: press,
            onCancel: cancel,
            onAccept: press
        ) {
            stormLCD
        }
        .accessibilityLabel("Digi-Storm")
        .accessibilityValue(accessibilityValue)
        .task(id: game.storm?.deadline) {
            guard let deadline = game.storm?.deadline,
                  game.storm?.outcome == .active else { return }
            let delay = max(0, deadline.timeIntervalSinceNow)
            try? await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            guard !Task.isCancelled,
                  game.storm?.outcome == .active else { return }
            game.resolveDigiStorm()
        }
        .onAppear {
            beginPresentation(for: game.storm?.outcome)
        }
        .onChange(of: game.storm?.outcome) { _, outcome in
            beginPresentation(for: outcome)
        }
        .onDisappear {
            continuationTask?.cancel()
            continuationTask = nil
            GameAudio.shared.stop()
        }
    }

    private var stormLCD: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) {
            timeline in
            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / 30,
                    geometry.size.height / 32
                )
                let origin = CGPoint(
                    x: (geometry.size.width - 30 * scale) / 2,
                    y: (geometry.size.height - 32 * scale) / 2
                )

                ZStack {
                    DetectorPalette.screen
                    if game.state.gridEnabled {
                        PixelGrid().opacity(0.34)
                    }

                    if let storm = game.storm {
                        stage(
                            storm,
                            at: timeline.date,
                            scale: scale,
                            origin: origin
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

    @ViewBuilder
    private func stage(
        _ storm: DigiStormSession,
        at date: Date,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        switch storm.outcome {
        case .active:
            let counter = min(
                82,
                max(0, Int(date.timeIntervalSince(stormStartedAt) / 0.10))
            )
            stormSprite(
                x: CGFloat(38 - counter),
                y: 0,
                scale: scale,
                origin: origin
            )
            stormSprite(
                x: CGFloat(76 - counter),
                y: 0,
                scale: scale,
                origin: origin
            )

        case .partyRecovered(let ids):
            recoveredStage(
                ids: ids,
                elapsed: resultElapsed(at: date),
                scale: scale,
                origin: origin
            )

        case .safe:
            capturedStage(
                ids: [game.state.currentCharacter],
                captures: false,
                elapsed: resultElapsed(at: date),
                scale: scale,
                origin: origin
            )

        case .partyLost(let ids):
            capturedStage(
                ids: ids,
                captures: true,
                elapsed: resultElapsed(at: date),
                scale: scale,
                origin: origin
            )

        case .teleported:
            capturedStage(
                ids: [game.state.currentCharacter] + storm.lostParty,
                captures: true,
                teleports: true,
                elapsed: resultElapsed(at: date),
                scale: scale,
                origin: origin
            )
        }
    }

    @ViewBuilder
    private func recoveredStage(
        ids: [Int],
        elapsed: TimeInterval,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        let safeIDs = ids.isEmpty ? [game.state.currentCharacter] : ids
        let index = min(
            safeIDs.count - 1,
            max(0, Int(elapsed / 2.8))
        )
        let local = elapsed - Double(index) * 2.8
        let counter = min(27, max(0, Int(local / 0.10)))
        characterAsset(
            id: safeIDs[index],
            suffix: "_step",
            frame: counter % 2,
            x: CGFloat(counter * 2),
            y: 4,
            mirrored: true,
            scale: scale,
            origin: origin
        )
    }

    @ViewBuilder
    private func capturedStage(
        ids: [Int],
        captures: Bool,
        teleports: Bool = false,
        elapsed: TimeInterval,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        let safeIDs = ids.isEmpty ? [game.state.currentCharacter] : ids
        let duration = teleports ? 4.25 : 4.0
        let index = min(
            safeIDs.count - 1,
            max(0, Int(elapsed / duration))
        )
        let local = elapsed - Double(index) * duration
        let id = safeIDs[index]

        if teleports {
            let counter = min(65, max(0, Int(local / 0.05)))
            if counter >= 32 {
                characterAsset(
                    id: id,
                    x: 3,
                    y: 4,
                    scale: scale,
                    origin: origin
                )
            }
            pixelAsset(
                resource: "spr_catch_dtector",
                frame: 1,
                x: 0,
                y: CGFloat(-32 + counter),
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
        } else if local < 0.5 {
            characterAsset(
                id: id,
                x: 27,
                y: 4,
                mirrored: true,
                scale: scale,
                origin: origin
            )
            pixelAsset(
                resource: "spr_question_dtector",
                frame: 0,
                x: 22,
                y: 0,
                width: 8,
                height: 8,
                scale: scale,
                origin: origin
            )
        } else if local < 3.9 {
            let counter = min(38, Int((local - 0.5) / 0.10))
            characterAsset(
                id: id,
                suffix: "_step",
                frame: counter % 2,
                x: CGFloat(max(0, 3 - min(3, counter))),
                y: 4,
                scale: scale,
                origin: origin
            )
            stormSprite(
                x: captures
                    ? CGFloat(30 - counter)
                    : 15,
                y: 0,
                scale: scale,
                origin: origin
            )
        } else {
            let counter = min(26, Int((local - 3.9) / 0.10))
            characterAsset(
                id: id,
                suffix: "_step",
                frame: counter % 2,
                x: CGFloat(-counter),
                y: 4,
                scale: scale,
                origin: origin
            )
            stormSprite(
                x: CGFloat(15 + counter),
                y: 0,
                scale: scale,
                origin: origin
            )
        }
    }

    private func characterAsset(
        id: Int,
        suffix: String = "",
        frame: Int = 0,
        x: CGFloat,
        y: CGFloat,
        mirrored: Bool = false,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        let definition = game.catalog.characters.indices.contains(id)
            ? game.catalog.characters[id]
            : game.currentCharacter
        return pixelAsset(
            resource: "\(definition.sprite)\(suffix)",
            frame: frame,
            x: x,
            y: y,
            width: 24,
            height: 24,
            mirrored: mirrored,
            scale: scale,
            origin: origin
        )
    }

    private func stormSprite(
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        pixelAsset(
            resource: "spr_digistorm_dtector",
            frame: 0,
            x: x,
            y: y,
            width: 30,
            height: 32,
            scale: scale,
            origin: origin
        )
    }

    private func pixelAsset(
        resource: String,
        frame: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        mirrored: Bool = false,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicPixelAsset(resource: resource, frame: frame)
            .frame(width: width * scale, height: height * scale)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(
                x: origin.x + (x + width / 2) * scale,
                y: origin.y + (y + height / 2) * scale
            )
    }

    private func resultElapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(outcomeStartedAt ?? date))
    }

    private func press() {
        guard game.storm?.outcome == .active else { return }
        game.tapDigiStorm()
    }

    private func cancel() {
        guard game.storm?.outcome != .active else { return }
        game.continueAfterStorm()
    }

    private func beginPresentation(
        for outcome: DigiStormSession.Outcome?
    ) {
        guard let outcome else { return }
        continuationTask?.cancel()

        switch outcome {
        case .active:
            stormStartedAt = Date()
            outcomeStartedAt = nil
            GameAudio.shared.play(
                "sound_digistorm_dtector",
                enabled: game.state.soundEnabled,
                loops: true
            )
            return

        case .safe:
            outcomeStartedAt = Date()
            GameAudio.shared.stop()
            scheduleContinuation(after: 7.8)

        case .partyLost(let ids):
            outcomeStartedAt = Date()
            GameAudio.shared.stop()
            GameAudio.shared.play(
                "sound_sad",
                enabled: game.state.soundEnabled
            )
            scheduleContinuation(after: Double(max(1, ids.count)) * 4.0)

        case .teleported:
            outcomeStartedAt = Date()
            GameAudio.shared.stop()
            GameAudio.shared.play(
                "sound_catch_dtector",
                enabled: game.state.soundEnabled
            )
            let count = max(
                1,
                1 + (game.storm?.lostParty.count ?? 0)
            )
            scheduleContinuation(after: Double(count) * 4.25 + 1.0)

        case .partyRecovered(let ids):
            outcomeStartedAt = Date()
            GameAudio.shared.stop()
            GameAudio.shared.play(
                "sound_char_happy_long",
                enabled: game.state.soundEnabled
            )
            scheduleContinuation(after: Double(max(1, ids.count)) * 2.8 + 4.0)
        }
    }

    private func scheduleContinuation(after delay: TimeInterval) {
        continuationTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(delay * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            game.continueAfterStorm()
        }
    }

    private var accessibilityValue: String {
        guard let storm = game.storm else { return "" }
        if storm.outcome == .active {
            return "\(storm.taps) of \(storm.target)"
        }
        return "Result animation"
    }
}
