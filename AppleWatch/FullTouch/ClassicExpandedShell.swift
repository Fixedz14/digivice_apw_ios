import SwiftUI

/// How the detector controls share the limited vertical space on Apple Watch.
enum ClassicControlsPlacement {
    /// Keeps the entire LCD unobscured, but leaves less room for it.
    case docked

    /// Lets the LCD use the full content area and floats the controls over its
    /// lower edge. This is the intended presentation for 40 mm and 46 mm.
    case overlay
}

/// A reusable, large-screen shell for the original 30×32 presentation.
///
/// The overlay layout is deliberately the default. A separate 44-point
/// control row forces the LCD down to roughly its old 107-point width on a
/// 40 mm watch. Floating 28-point controls inside 44-point hit targets lets
/// the same watch display a roughly 135-point-wide, pixel-aligned LCD.
///
/// Pass `showsControls: false` while a non-interactive animation is running.
/// The stage does not change size, so hiding the controls cannot make an
/// attack sequence jump or re-layout between beats.
struct ClassicExpandedShell<Stage: View>: View {
    @Environment(\.displayScale) private var displayScale

    var showGrid = false
    var drawsViewport = true
    var controlsPlacement: ClassicControlsPlacement = .overlay
    var showsControls = true
    var leftEnabled = true
    var cancelEnabled = true
    var acceptEnabled = true
    var edgePadding: CGFloat = 1
    var controlGap: CGFloat = 2
    var onStageTap: (() -> Void)?
    var onLeft: () -> Void
    var onCancel: () -> Void
    var onAccept: () -> Void

    private let stage: Stage

    init(
        showGrid: Bool = false,
        drawsViewport: Bool = true,
        controlsPlacement: ClassicControlsPlacement = .overlay,
        showsControls: Bool = true,
        leftEnabled: Bool = true,
        cancelEnabled: Bool = true,
        acceptEnabled: Bool = true,
        edgePadding: CGFloat = 1,
        controlGap: CGFloat = 2,
        onStageTap: (() -> Void)? = nil,
        onLeft: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onAccept: @escaping () -> Void,
        @ViewBuilder stage: () -> Stage
    ) {
        self.showGrid = showGrid
        self.drawsViewport = drawsViewport
        self.controlsPlacement = controlsPlacement
        self.showsControls = showsControls
        self.leftEnabled = leftEnabled
        self.cancelEnabled = cancelEnabled
        self.acceptEnabled = acceptEnabled
        self.edgePadding = edgePadding
        self.controlGap = controlGap
        self.onStageTap = onStageTap
        self.onLeft = onLeft
        self.onCancel = onCancel
        self.onAccept = onAccept
        self.stage = stage()
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = ClassicExpandedLayout(
                containerSize: geometry.size,
                displayScale: displayScale,
                controlsPlacement: controlsPlacement,
                showsControls: showsControls,
                edgePadding: edgePadding,
                controlGap: controlGap
            )

            ZStack {
                fittedStage
                    .frame(
                        width: layout.stageSize.width,
                        height: layout.stageSize.height
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !showsControls {
                            onStageTap?()
                        }
                    }
                    .position(layout.stageCenter)

                if showsControls {
                    ClassicDetectorTouchZones(
                        leftEnabled: leftEnabled,
                        centerEnabled: acceptEnabled,
                        rightEnabled: onStageTap != nil || acceptEnabled,
                        cancelEnabled: cancelEnabled,
                        onLeft: onLeft,
                        onCenter: onAccept,
                        onRight: {
                            if let onStageTap {
                                onStageTap()
                            } else {
                                onAccept()
                            }
                        },
                        onCancel: onCancel
                    )
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .animation(
                .easeOut(duration: 0.16),
                value: showsControls
            )
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var fittedStage: some View {
        if drawsViewport {
            ClassicLCDViewport(
                content: {
                    stage
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                },
                showGrid: showGrid
            )
        } else {
            stage
                .aspectRatio(
                    ClassicLCDGeometry.aspectRatio,
                    contentMode: .fit
                )
        }
    }
}

/// Menu screens need the classic LCD to stay fully readable. They still use
/// the expanded pixel-aligned sizing, but reserve a real control band instead
/// of floating buttons over the original menu art.
struct ClassicMenuShell<Stage: View>: View {
    @Environment(\.displayScale) private var displayScale

    var showGrid = false
    var leftEnabled = true
    var cancelEnabled = true
    var acceptEnabled = true
    var onStageTap: () -> Void
    var onLeft: () -> Void
    var onCancel: () -> Void
    var onAccept: () -> Void

    private let stage: Stage

    init(
        showGrid: Bool = false,
        leftEnabled: Bool = true,
        cancelEnabled: Bool = true,
        acceptEnabled: Bool = true,
        onStageTap: @escaping () -> Void,
        onLeft: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onAccept: @escaping () -> Void,
        @ViewBuilder stage: () -> Stage
    ) {
        self.showGrid = showGrid
        self.leftEnabled = leftEnabled
        self.cancelEnabled = cancelEnabled
        self.acceptEnabled = acceptEnabled
        self.onStageTap = onStageTap
        self.onLeft = onLeft
        self.onCancel = onCancel
        self.onAccept = onAccept
        self.stage = stage()
    }

    var body: some View {
        GeometryReader { geometry in
            let stageSize = ClassicLCDGeometry.pixelAlignedSize(
                fitting: CGSize(
                    width: geometry.size.width,
                    height: geometry.size.height
                ),
                displayScale: displayScale
            )

            ZStack(alignment: .top) {
                ClassicLCDViewport(
                    content: {
                        stage
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                    },
                    showGrid: showGrid,
                    borderOutset: 1
                )
                .frame(width: stageSize.width, height: stageSize.height)
                .contentShape(Rectangle())
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                ClassicDetectorTouchZones(
                    leftEnabled: leftEnabled,
                    centerEnabled: acceptEnabled,
                    rightEnabled: true,
                    cancelEnabled: cancelEnabled,
                    onLeft: onLeft,
                    onCenter: onAccept,
                    onRight: onStageTap,
                    onCancel: onCancel
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .position(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
                .zIndex(1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A wide battle-only shell modelled after the roomier V2 detector screen.
///
/// Unlike the menu shell, the arena deliberately fills the available width and
/// height. Battle input is gesture-only so no visible controls can cover the
/// extracted command/menu frames on the small Watch display.
struct ClassicWideBattleShell<Stage: View>: View {
    var showsControls = true
    var leftEnabled = true
    var cancelEnabled = true
    var acceptEnabled = true
    var onStageTap: () -> Void
    var onLeft: () -> Void
    var onCancel: () -> Void
    var onAccept: () -> Void

    private let stage: Stage

    init(
        showsControls: Bool = true,
        leftEnabled: Bool = true,
        cancelEnabled: Bool = true,
        acceptEnabled: Bool = true,
        onStageTap: @escaping () -> Void,
        onLeft: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onAccept: @escaping () -> Void,
        @ViewBuilder stage: () -> Stage
    ) {
        self.showsControls = showsControls
        self.leftEnabled = leftEnabled
        self.cancelEnabled = cancelEnabled
        self.acceptEnabled = acceptEnabled
        self.onStageTap = onStageTap
        self.onLeft = onLeft
        self.onCancel = onCancel
        self.onAccept = onAccept
        self.stage = stage()
    }

    var body: some View {
        GeometryReader { geometry in
            let stageWidth = max(1, geometry.size.width - 2)
            let stageHeight = max(1, geometry.size.height - 2)

            ZStack(alignment: .top) {
                stage
                    .frame(width: stageWidth, height: stageHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !showsControls else { return }
                        onStageTap()
                    }
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )

                if showsControls {
                    ClassicDetectorTouchZones(
                        leftEnabled: leftEnabled,
                        centerEnabled: acceptEnabled,
                        rightEnabled: true,
                        cancelEnabled: cancelEnabled,
                        onLeft: onLeft,
                        onCenter: onAccept,
                        onRight: onStageTap,
                        onCancel: onCancel
                    )
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    .zIndex(1)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .animation(
                .easeInOut(duration: 0.20),
                value: showsControls
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Next") {
            guard showsControls, leftEnabled else { return }
            onLeft()
        }
        .accessibilityAction(named: "Cancel") {
            guard showsControls, cancelEnabled else { return }
            onCancel()
        }
        .accessibilityAction(named: "Accept") {
            guard showsControls, acceptEnabled else { return }
            onAccept()
        }
    }
}

private struct ClassicExpandedLayout {
    static let minimumHitDiameter: CGFloat = 44

    let stageSize: CGSize
    let stageCenter: CGPoint
    let controlsCenter: CGPoint
    let controlsWidth: CGFloat
    let controlHitDiameter: CGFloat

    init(
        containerSize: CGSize,
        displayScale: CGFloat,
        controlsPlacement: ClassicControlsPlacement,
        showsControls: Bool,
        edgePadding: CGFloat,
        controlGap: CGFloat
    ) {
        let padding = max(0, edgePadding)
        let hitDiameter = Self.minimumHitDiameter
        let availableWidth = max(
            1,
            containerSize.width - padding * 2
        )
        let dockHeight: CGFloat = 0
        let availableHeight = max(
            1,
            containerSize.height - padding * 2 - dockHeight
        )
        let availableStageSize = CGSize(
            width: availableWidth,
            height: availableHeight
        )
        let fittedStageSize = ClassicLCDGeometry.pixelAlignedSize(
            fitting: availableStageSize,
            displayScale: displayScale
        )

        stageSize = fittedStageSize
        controlHitDiameter = hitDiameter
        controlsWidth = min(
            availableWidth,
            hitDiameter * 3
        )

        stageCenter = CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height / 2
        )
        controlsCenter = CGPoint(
            x: containerSize.width / 2,
            y: max(
                hitDiameter / 2,
                containerSize.height - padding - hitDiameter / 2
            )
        )
    }
}
