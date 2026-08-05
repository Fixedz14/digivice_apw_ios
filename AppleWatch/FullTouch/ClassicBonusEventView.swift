import SwiftUI

/// Direct port of `obj_bonus_dtector`'s 30×32 counter-driven presentation.
struct ClassicBonusEventView: View {
    @EnvironmentObject private var game: GameModel
    let presentation: BonusPresentation

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ClassicExpandedShell(
                drawsViewport: false,
                showsControls: false,
                onStageTap: {},
                onLeft: {},
                onCancel: {},
                onAccept: {}
            ) {
                bonusLCD
            }
        }
        .task(id: presentation.startedAt) {
            let remaining = max(
                0,
                8.2 - Date().timeIntervalSince(presentation.startedAt)
            )
            try? await Task.sleep(
                nanoseconds: UInt64(remaining * 1_000_000_000)
            )
            guard !Task.isCancelled,
                  game.bonusPresentation == presentation else { return }
            game.finishBonusPresentation()
        }
        .accessibilityLabel("D-Tector bonus event")
        .accessibilityValue("\(presentation.value)")
    }

    private var bonusLCD: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / 30,
                    geometry.size.height / 32
                )
                let origin = CGPoint(
                    x: (geometry.size.width - 30 * scale) / 2,
                    y: (geometry.size.height - 32 * scale) / 2
                )
                let elapsed = max(
                    0,
                    timeline.date.timeIntervalSince(presentation.startedAt)
                )
                let counter = sourceCounter(elapsed)

                ZStack {
                    DetectorPalette.screen
                    if game.state.gridEnabled {
                        PixelGrid().opacity(0.34)
                    }
                    eventFrame(
                        counter: counter,
                        scale: scale,
                        origin: origin
                    )
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
    private func eventFrame(
        counter: Int,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        if counter > 0 && counter <= 14 {
            asset(
                "spr_object_dtector",
                frame: counter,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
        }
        if counter > 6 && counter <= 14
            && (counter > 10 || counter.isMultiple(of: 2) == false) {
            bonusIcon(
                x: 7,
                y: 8,
                scale: scale,
                origin: origin
            )
        } else if counter >= 15 && counter <= 23 {
            bonusIcon(
                x: 7,
                y: CGFloat(8 - (counter - 15)),
                scale: scale,
                origin: origin
            )
        } else if counter >= 24 {
            asset(
                "spr_bonus_calc_dtector",
                frame: presentation.type == 2
                    ? 1
                    : presentation.type == 3 ? 2 : 0,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
            bonusIcon(
                x: 7,
                y: 0,
                scale: scale,
                origin: origin
            )
            if counter >= 25 {
                number(
                    presentation.value,
                    drawX: 25,
                    y: 24,
                    scale: scale,
                    origin: origin
                )
            }
        }
    }

    private func bonusIcon(
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        asset(
            "spr_bonus_dtector",
            frame: presentation.type,
            x: x,
            y: y,
            width: 16,
            height: 16,
            scale: scale,
            origin: origin
        )
    }

    private func number(
        _ value: Int,
        drawX: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicLCDNumber(value: value, white: false, scale: scale)
            .position(
                x: origin.x
                    + ClassicLCDNumber.logicalCenter(
                        for: value,
                        leastSignificantX: drawX
                    ) * scale,
                y: origin.y + (y + 2.5) * scale
            )
    }

    private func asset(
        _ resource: String,
        frame: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicPixelAsset(resource: resource, frame: frame)
            .frame(width: width * scale, height: height * scale)
            .position(
                x: origin.x + (x + width / 2) * scale,
                y: origin.y + (y + height / 2) * scale
            )
    }

    private func sourceCounter(_ elapsed: TimeInterval) -> Int {
        if elapsed < 0.5 { return 0 }
        if elapsed < 3.3 {
            return min(14, Int((elapsed - 0.5) / 0.2) + 1)
        }
        if elapsed < 4.2 {
            return min(23, Int((elapsed - 3.3) / 0.1) + 15)
        }
        if elapsed < 5.2 { return 24 }
        if elapsed < 6.2 { return 25 }
        if elapsed < 7.2 { return 26 }
        return 27
    }
}
