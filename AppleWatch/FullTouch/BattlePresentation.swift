import SwiftUI

// MARK: - Integration overview

/// A self-contained, timeline-driven presentation layer for a D-Tector battle.
///
/// The engine intentionally does not depend on `GameModel`, `BattleSession`, or
/// `PixelComponents`. A battle screen owns one `BattlePresentationDirector`,
/// renders a `BattlePresentationStage`, and starts a timeline when gameplay
/// produces a visual event:
///
///     @StateObject private var battleFX = BattlePresentationDirector()
///
///     BattlePresentationStage(
///         director: battleFX,
///         player: .init(resource: playerSprite),
///         enemy: .init(resource: enemySprite, mirrored: true)
///     )
///
///     battleFX.play(
///         .attack(attacker: .player, move: .energy, hits: true)
///     )
///
/// `BattlePresentationDemoView` is a one-line preview/demo surface that can be
/// embedded in `ContentView` without any gameplay state.

enum BattlePresentationSide: String, CaseIterable, Hashable {
    case player
    case enemy

    var opponent: BattlePresentationSide {
        self == .player ? .enemy : .player
    }

    fileprivate var direction: CGFloat {
        self == .player ? 1 : -1
    }
}

enum BattlePresentationMove: Int, CaseIterable, Hashable {
    case energy = 0
    case crunch = 1
    case ability = 2

    init(moveID: Int) {
        self = BattlePresentationMove(rawValue: moveID) ?? .energy
    }

    var moveID: Int { rawValue }

    fileprivate var primaryColor: Color {
        Color(red: 0.15, green: 0.15, blue: 0.15)
    }

    fileprivate var secondaryColor: Color {
        Color(red: 0.86, green: 0.86, blue: 0.86)
    }
}

struct BattlePresentationSprite: Hashable {
    var resource: String
    var idleFrames: [Int]
    var attackFrames: [Int]
    var hitFrames: [Int]
    var victoryFrames: [Int]
    var defeatFrames: [Int]
    var framesPerSecond: Double
    var size: CGFloat
    var mirrored: Bool
    var accessibilityLabel: String

    init(
        resource: String,
        idleFrames: [Int] = [0, 1],
        attackFrames: [Int]? = nil,
        hitFrames: [Int]? = nil,
        victoryFrames: [Int]? = nil,
        defeatFrames: [Int]? = nil,
        framesPerSecond: Double = 7,
        size: CGFloat = 48,
        mirrored: Bool = false,
        accessibilityLabel: String = ""
    ) {
        let safeIdle = idleFrames.isEmpty ? [0] : idleFrames
        self.resource = resource
        self.idleFrames = safeIdle
        self.attackFrames = Self.nonempty(attackFrames, fallback: safeIdle)
        self.hitFrames = Self.nonempty(hitFrames, fallback: safeIdle)
        self.victoryFrames = Self.nonempty(victoryFrames, fallback: safeIdle)
        self.defeatFrames = Self.nonempty(defeatFrames, fallback: safeIdle)
        self.framesPerSecond = max(1, framesPerSecond)
        self.size = max(1, size)
        self.mirrored = mirrored
        self.accessibilityLabel = accessibilityLabel
    }

    private static func nonempty(_ frames: [Int]?, fallback: [Int]) -> [Int] {
        guard let frames, !frames.isEmpty else { return fallback }
        return frames
    }
}

struct BattleSpiritEvolutionSpec: Hashable {
    var oldCharacterResource: String
    var newCharacterResource: String
    var spiritFrame: Int
    var evolvedResource: String
    var swapsCharacter: Bool

    var newCharacterSpiritResource: String {
        "\(newCharacterResource)_spirit"
    }
}

struct BattleAncientEvolutionSpec: Hashable {
    var characterResource: String
    var firstSpiritFrame: Int
    var secondSpiritFrame: Int
    var evolvedResource: String

    var characterSpiritResource: String {
        "\(characterResource)_spirit"
    }
}

struct BattleEnemyEvolutionSpec: Hashable {
    var oldResource: String
    var newResource: String
}

struct BattleSpiritOffSpec: Hashable {
    var evolvedResource: String
    var characterResource: String
}

struct BattleDigiPowerSpec: Hashable {
    var helperResource: String
    var spiritResource: String
    var succeeds: Bool
}

// MARK: - Phase and timeline model

enum BattlePresentationPhase: Hashable {
    case idle
    case intro
    case summon(BattlePresentationSide)
    case ready
    case windUp(attacker: BattlePresentationSide, move: BattlePresentationMove)
    case projectile(attacker: BattlePresentationSide, move: BattlePresentationMove)
    case collision(
        playerMove: BattlePresentationMove,
        enemyMove: BattlePresentationMove
    )
    case impact(
        target: BattlePresentationSide,
        move: BattlePresentationMove,
        critical: Bool
    )
    case evade(BattlePresentationSide)
    case recovery
    case callPower(Int)
    case spiritCheck(Int)
    case spiritPower(Int)
    case spiritReady
    case digiPower(BattleDigiPowerSpec)
    case evolution(BattlePresentationSide)
    case spiritEvolution(
        BattlePresentationSide,
        BattleSpiritEvolutionSpec
    )
    case ancientEvolution(
        BattlePresentationSide,
        BattleAncientEvolutionSpec
    )
    case enemyEvolution(BattleEnemyEvolutionSpec)
    case spiritOff(BattlePresentationSide, BattleSpiritOffSpec)
    case characterReturn(String)
    case capture(BattlePresentationSide)
    case deport(BattlePresentationSide)
    case victory(BattlePresentationSide)
    case defeat(BattlePresentationSide)
}

struct BattlePresentationBeat: Hashable {
    var phase: BattlePresentationPhase
    var duration: TimeInterval
    var collisionOutcome: Int?

    init(
        _ phase: BattlePresentationPhase,
        duration: TimeInterval,
        collisionOutcome: Int? = nil
    ) {
        self.phase = phase
        self.duration = max(0.01, duration)
        self.collisionOutcome = collisionOutcome
    }
}

struct BattlePresentationSample: Equatable {
    var phase: BattlePresentationPhase
    var beatIndex: Int
    var beatProgress: Double
    var timelineProgress: Double
    var elapsed: TimeInterval
    var isFinished: Bool
    var collisionOutcome: Int? = nil

    static let idle = BattlePresentationSample(
        phase: .idle,
        beatIndex: 0,
        beatProgress: 0,
        timelineProgress: 0,
        elapsed: 0,
        isFinished: false,
        collisionOutcome: nil
    )
}

private enum BattleOriginalTiming {
    static let neutral: TimeInterval = 0.25
    static let anticipation: TimeInterval = 0.50
    static let launchTravel: TimeInterval = 1.60
    static let collisionHit: TimeInterval = 3.05
    static let collisionTie: TimeInterval = 1.55

    static func impactDuration(for move: BattlePresentationMove) -> TimeInterval {
        switch move {
        case .energy:
            return 6.07
        case .crunch:
            return 8.37
        case .ability:
            return 6.32
        }
    }

    static func hitBurstInterval(
        for move: BattlePresentationMove
    ) -> Range<TimeInterval>? {
        switch move {
        case .energy:
            return 0.50..<3.00
        case .crunch:
            return 2.75..<5.25
        case .ability:
            // The original Ability branches bypass spr_hit.
            return nil
        }
    }

    static func showsHitBurst(
        move: BattlePresentationMove,
        progress: Double,
        duration: TimeInterval? = nil
    ) -> Bool {
        guard let interval = hitBurstInterval(for: move) else { return false }
        let elapsed = min(1, max(0, progress))
            * (duration ?? impactDuration(for: move))
        return interval.contains(elapsed)
    }

    static func incomingTravelDuration(
        for move: BattlePresentationMove,
        impactDuration: TimeInterval
    ) -> TimeInterval {
        switch move {
        case .energy:
            return 0.50
        case .crunch:
            return 2.75
        case .ability:
            // Ability vs. Crunch skips the long incoming-travel branch.
            return impactDuration < 4.50 ? 0.05 : 2.80
        }
    }

    static func targetIsVisible(
        move: BattlePresentationMove,
        elapsed: TimeInterval,
        impactDuration: TimeInterval
    ) -> Bool {
        if let burst = hitBurstInterval(for: move),
           burst.contains(elapsed) {
            return false
        }

        switch move {
        case .energy:
            return true
        case .crunch:
            // The source draws the target's frame 2 as the incoming Crunch
            // streak; the stationary target returns after the hit burst.
            return elapsed >= (hitBurstInterval(for: .crunch)?.upperBound ?? 5.25)
        case .ability:
            let travelDuration = incomingTravelDuration(
                for: move,
                impactDuration: impactDuration
            )
            if travelDuration <= 0.05 {
                return true
            }

            // Only the incoming attacker pass is visible here. Keeping the
            // target hidden preserves the original sequential-side staging.
            return elapsed >= travelDuration
        }
    }
}

/// Keeps all movement on the original 30×32 logical pixel lattice. Curves are
/// used only to make anticipation readable; launch and collision travel retain
/// the source's fixed one-pixel-per-tick cadence.
private enum BattlePixelMotion {
    static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func sourceTick(
        progress: Double,
        maximum: Int
    ) -> Int {
        guard maximum > 0 else { return 0 }
        let clamped = clamp(progress)
        return min(
            maximum,
            max(0, Int(floor(clamped * Double(maximum + 1))))
        )
    }

    static func steppedEaseOut(
        progress: Double,
        distance: Int
    ) -> CGFloat {
        guard distance > 0 else { return 0 }
        let clamped = clamp(progress)
        let eased = 1 - pow(1 - clamped, 2)
        return CGFloat(
            min(distance, max(0, Int(floor(eased * Double(distance + 1)))))
        )
    }
}

struct BattlePresentationTimeline: Hashable {
    var beats: [BattlePresentationBeat]

    init(beats: [BattlePresentationBeat]) {
        self.beats = beats.isEmpty
            ? [BattlePresentationBeat(.idle, duration: 0.01)]
            : beats
    }

    var totalDuration: TimeInterval {
        beats.reduce(0) { $0 + $1.duration }
    }

    func sample(elapsed rawElapsed: TimeInterval) -> BattlePresentationSample {
        let elapsed = max(0, rawElapsed)
        let total = max(0.01, totalDuration)
        var cursor: TimeInterval = 0

        for (index, beat) in beats.enumerated() {
            let end = cursor + beat.duration
            if elapsed < end || index == beats.count - 1 {
                let localElapsed = min(beat.duration, max(0, elapsed - cursor))
                return BattlePresentationSample(
                    phase: beat.phase,
                    beatIndex: index,
                    beatProgress: Self.clamp(localElapsed / beat.duration),
                    timelineProgress: Self.clamp(elapsed / total),
                    elapsed: min(elapsed, total),
                    isFinished: elapsed >= total,
                    collisionOutcome: beat.collisionOutcome
                )
            }
            cursor = end
        }

        return .idle
    }

    func appending(_ timeline: BattlePresentationTimeline) -> BattlePresentationTimeline {
        BattlePresentationTimeline(beats: beats + timeline.beats)
    }

    static func sequence(
        _ timelines: [BattlePresentationTimeline]
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(beats: timelines.flatMap(\.beats))
    }

    static let idle = BattlePresentationTimeline(
        beats: [BattlePresentationBeat(.idle, duration: 0.01)]
    )

    static func intro(duration: TimeInterval = 0.55) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(.intro, duration: duration),
                BattlePresentationBeat(.ready, duration: 0.16)
            ]
        )
    }

    static func summon(
        _ side: BattlePresentationSide,
        duration: TimeInterval = 8.17
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(.summon(side), duration: duration)
            ]
        )
    }

    static func attack(
        attacker: BattlePresentationSide,
        move: BattlePresentationMove,
        hits: Bool,
        critical: Bool = false
    ) -> BattlePresentationTimeline {
        var beats = [
            BattlePresentationBeat(
                .windUp(attacker: attacker, move: move),
                duration: BattleOriginalTiming.neutral
                    + BattleOriginalTiming.anticipation
            ),
            BattlePresentationBeat(
                .projectile(attacker: attacker, move: move),
                duration: BattleOriginalTiming.launchTravel
            )
        ]

        if hits {
            beats.append(
                BattlePresentationBeat(
                    .impact(target: attacker.opponent, move: move, critical: critical),
                    duration: BattleOriginalTiming.impactDuration(for: move)
                )
            )
        } else {
            beats.append(
                BattlePresentationBeat(.evade(attacker.opponent), duration: 0.24)
            )
        }

        beats.append(BattlePresentationBeat(.recovery, duration: 0.18))
        return BattlePresentationTimeline(beats: beats)
    }

    static func round(
        playerMove: BattlePresentationMove,
        enemyMove: BattlePresentationMove,
        outcome: Int,
        critical: Bool = false
    ) -> BattlePresentationTimeline {
        var beats = [
            BattlePresentationBeat(
                .windUp(attacker: .player, move: playerMove),
                duration: BattleOriginalTiming.neutral
                    + BattleOriginalTiming.anticipation
            ),
            BattlePresentationBeat(
                .projectile(attacker: .player, move: playerMove),
                duration: BattleOriginalTiming.launchTravel
            ),
            BattlePresentationBeat(
                .windUp(attacker: .enemy, move: enemyMove),
                duration: BattleOriginalTiming.neutral
                    + BattleOriginalTiming.anticipation
            ),
            BattlePresentationBeat(
                .projectile(attacker: .enemy, move: enemyMove),
                duration: BattleOriginalTiming.launchTravel
            ),
            BattlePresentationBeat(
                .collision(playerMove: playerMove, enemyMove: enemyMove),
                duration: outcome == 0
                    ? BattleOriginalTiming.collisionTie
                    : BattleOriginalTiming.collisionHit,
                collisionOutcome: outcome
            )
        ]

        if outcome > 0 {
            let impactDuration = playerMove == .ability && enemyMove == .crunch
                ? 3.57
                : BattleOriginalTiming.impactDuration(for: playerMove)
            beats.append(
                BattlePresentationBeat(
                    .impact(
                        target: .enemy,
                        move: playerMove,
                        critical: critical
                    ),
                    duration: impactDuration
                )
            )
        } else if outcome < 0 {
            let impactDuration = enemyMove == .ability && playerMove == .crunch
                ? 3.57
                : BattleOriginalTiming.impactDuration(for: enemyMove)
            beats.append(
                BattlePresentationBeat(
                    .impact(
                        target: .player,
                        move: enemyMove,
                        critical: critical
                    ),
                    duration: impactDuration
                )
            )
        }

        // Leave the director on the menu/blank stage rather than freezing the
        // final impact frame after playback completes.
        beats.append(BattlePresentationBeat(.ready, duration: 0.01))
        return BattlePresentationTimeline(beats: beats)
    }

    static func evolution(
        _ side: BattlePresentationSide,
        duration: TimeInterval = 5.50
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(.evolution(side), duration: duration)
            ]
        )
    }

    static func spiritEvolution(
        _ side: BattlePresentationSide,
        spec: BattleSpiritEvolutionSpec
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .spiritEvolution(side, spec),
                    duration: spec.swapsCharacter ? 24.35 : 21.30
                )
            ]
        )
    }

    static func spiritPower(_ remainingValue: Int) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .spiritPower(max(0, remainingValue)),
                    duration: 5.50
                )
            ]
        )
    }

    static func callPower(_ remainingValue: Int) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .callPower(max(0, min(8, remainingValue))),
                    duration: 1.0
                )
            ]
        )
    }

    static func spiritCheck(
        _ remainingValue: Int
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .spiritCheck(max(0, remainingValue)),
                    duration: 2.50
                )
            ]
        )
    }

    static let spiritReady = BattlePresentationTimeline(
        beats: [
            BattlePresentationBeat(.spiritReady, duration: 3.60)
        ]
    )

    static func digiPower(
        spec: BattleDigiPowerSpec
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .digiPower(spec),
                    duration: spec.succeeds ? 13.32 : 7.95
                )
            ]
        )
    }

    static func ancientEvolution(
        _ side: BattlePresentationSide,
        spec: BattleAncientEvolutionSpec
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .ancientEvolution(side, spec),
                    duration: 18.28
                )
            ]
        )
    }

    static func enemyEvolution(
        spec: BattleEnemyEvolutionSpec
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .enemyEvolution(spec),
                    duration: 13.97
                )
            ]
        )
    }

    static func spiritOff(
        _ side: BattlePresentationSide,
        spec: BattleSpiritOffSpec
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .spiritOff(side, spec),
                    duration: 8.30
                )
            ]
        )
    }

    static func characterReturn(
        resource: String
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(
                    .characterReturn(resource),
                    duration: 2.50
                )
            ]
        )
    }

    static func capture(
        _ side: BattlePresentationSide
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(.capture(side), duration: 6.35)
            ]
        )
    }

    static func deport(
        _ side: BattlePresentationSide
    ) -> BattlePresentationTimeline {
        BattlePresentationTimeline(
            beats: [
                BattlePresentationBeat(.deport(side), duration: 2.80)
            ]
        )
    }

    static func result(
        winner: BattlePresentationSide,
        loser: BattlePresentationSide? = nil
    ) -> BattlePresentationTimeline {
        var beats = [BattlePresentationBeat(.victory(winner), duration: 0.62)]
        if let loser {
            beats.insert(BattlePresentationBeat(.defeat(loser), duration: 0.48), at: 0)
        }
        return BattlePresentationTimeline(beats: beats)
    }

    static let demo = BattlePresentationTimeline.sequence([
        .intro(duration: 0.42),
        .summon(.player, duration: 0.48),
        .attack(attacker: .player, move: .energy, hits: true, critical: true),
        .result(winner: .player, loser: .enemy)
    ])

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

// MARK: - Playback director

@MainActor
final class BattlePresentationDirector: ObservableObject {
    @Published private(set) var timeline: BattlePresentationTimeline
    @Published private(set) var startedAt: Date?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackID = UUID()

    private var completionTask: Task<Void, Never>?

    init(timeline: BattlePresentationTimeline = .idle) {
        self.timeline = timeline
    }

    func play(
        _ timeline: BattlePresentationTimeline,
        completion: (() -> Void)? = nil
    ) {
        completionTask?.cancel()

        let playbackID = UUID()
        self.timeline = timeline
        self.playbackID = playbackID
        startedAt = Date()
        isPlaying = true

        completionTask = Task { @MainActor [weak self] in
            // TimelineView redraws the stage, but labels and other sibling
            // views also need an ObservableObject update at each phase change.
            for beat in timeline.beats {
                let nanoseconds = UInt64(beat.duration * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled,
                      let self,
                      self.playbackID == playbackID else { return }
                self.objectWillChange.send()
            }

            guard let self, self.playbackID == playbackID else { return }
            self.isPlaying = false
            self.completionTask = nil
            completion?()
        }
    }

    func replay(completion: (() -> Void)? = nil) {
        play(timeline, completion: completion)
    }

    func stop(resetToIdle: Bool = false) {
        completionTask?.cancel()
        completionTask = nil
        isPlaying = false
        if resetToIdle {
            timeline = .idle
            startedAt = nil
            playbackID = UUID()
        }
    }

    func sample(at date: Date) -> BattlePresentationSample {
        guard let startedAt else { return .idle }
        return timeline.sample(elapsed: date.timeIntervalSince(startedAt))
    }
}

// MARK: - Pixel sprite animator

/// Selects a pixel-art frame from normalized timeline progress.
///
/// The view is deliberately progress-driven rather than timer-owned. This keeps
/// multiple combatants, projectiles, flashes, and hit reactions synchronized to
/// the same battle timeline.
struct BattlePixelSpriteAnimator: View {
    var resource: String
    var frames: [Int]
    var progress: Double
    var loops: Bool
    var size: CGFloat
    var mirrored: Bool
    var opacity: Double
    var scale: CGFloat
    var rotation: Angle
    var accessibilityLabel: String

    init(
        resource: String,
        frames: [Int],
        progress: Double,
        loops: Bool = false,
        size: CGFloat = 48,
        mirrored: Bool = false,
        opacity: Double = 1,
        scale: CGFloat = 1,
        rotation: Angle = .zero,
        accessibilityLabel: String = "Battle sprite"
    ) {
        self.resource = resource
        self.frames = frames.isEmpty ? [0] : frames
        self.progress = min(1, max(0, progress))
        self.loops = loops
        self.size = max(1, size)
        self.mirrored = mirrored
        self.opacity = min(1, max(0, opacity))
        self.scale = max(0, scale)
        self.rotation = rotation
        self.accessibilityLabel = accessibilityLabel
    }

    private var frame: Int {
        guard frames.count > 1 else { return frames[0] }
        let scaled = progress * Double(frames.count)
        if loops {
            return frames[Int(scaled) % frames.count]
        }
        return frames[min(frames.count - 1, Int(scaled))]
    }

    var body: some View {
        Group {
            if resource.isEmpty {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.20)
            } else {
                GameSprite(resource: resource, frame: frame, size: size)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(
            x: (mirrored ? -1 : 1) * scale,
            y: scale,
            anchor: .center
        )
        .rotationEffect(rotation)
        .opacity(opacity)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

// MARK: - Reusable effects

private struct BattleLogicalMetrics {
    static let width: CGFloat = 30
    static let height: CGFloat = 32
    static let actorSize: CGFloat = 24
    static let collisionSize: CGFloat = 8

    let scale: CGFloat
    let viewportOrigin: CGPoint
    let viewportSize: CGSize

    init(size: CGSize, displayScale: CGFloat) {
        let safeWidth = max(1, size.width)
        let safeHeight = max(1, size.height)
        let rawScale = min(
            safeWidth / Self.width,
            safeHeight / Self.height
        )
        let safeDisplayScale = max(1, displayScale)
        let alignedScale = floor(rawScale * safeDisplayScale)
            / safeDisplayScale
        scale = alignedScale > 0 ? alignedScale : rawScale
        // The source scene stays on its original square-pixel 30×32 lattice,
        // but the physical arena may be wider on Apple Watch. Keeping the
        // entire container as the clip viewport exposes those side gutters
        // for launch/collision travel without stretching any sprite.
        viewportSize = CGSize(width: safeWidth, height: safeHeight)
        let rawOriginX = (safeWidth - Self.width * scale) / 2
        let rawOriginY = (safeHeight - Self.height * scale) / 2
        viewportOrigin = CGPoint(
            x: round(rawOriginX * safeDisplayScale) / safeDisplayScale,
            y: round(rawOriginY * safeDisplayScale) / safeDisplayScale
        )
    }

    var viewportCenter: CGPoint {
        CGPoint(
            x: viewportSize.width / 2,
            y: viewportSize.height / 2
        )
    }

    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: viewportOrigin.x + x * scale,
            y: viewportOrigin.y + y * scale
        )
    }

    func length(_ logicalPixels: CGFloat) -> CGFloat {
        logicalPixels * scale
    }
}

struct BattleProjectileOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var attacker: BattlePresentationSide
    var move: BattlePresentationMove
    var progress: Double
    var reducedMotion = false
    var spriteResource: String
    var mirrored = false
    var collisionMode = false

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let rawProgress = min(1, max(0, progress))
            // Positions 0...31 are each held for one three-step Alarm tick;
            // position 32 hands off to the other side before another Draw.
            let tick = BattlePixelMotion.sourceTick(
                progress: rawProgress,
                maximum: 31
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let launchCenterX: CGFloat = attacker == .player ? 19 : 11

            ZStack {
                switch move {
                case .energy:
                    GameSprite(
                        resource: "spr_energy_dtector",
                        frame: 7,
                        size: actorSize
                    )
                    .scaleEffect(
                        x: attacker == .player ? 1 : -1,
                        y: 1
                    )
                    .position(
                        metrics.point(
                            x: launchCenterX
                                + (attacker == .player ? -1 : 1)
                                * CGFloat(tick),
                            y: 16
                        )
                    )

                case .crunch:
                    // GML draws one frame-2 copy every four logical pixels.
                    // Copies after index seven are entirely outside 30×32.
                    ForEach(0...min(tick, 7), id: \.self) { index in
                        GameSprite(
                            resource: spriteResource,
                            frame: 2,
                            size: actorSize
                        )
                        .scaleEffect(
                            x: attacker == .enemy ? -1 : 1,
                            y: 1
                        )
                        .position(
                            metrics.point(
                                x: launchCenterX
                                    + (attacker == .player ? -1 : 1)
                                    * CGFloat(index * 4),
                                y: 16
                            )
                        )
                    }

                case .ability:
                    GameSprite(
                        resource: spriteResource,
                        frame: 3,
                        size: actorSize
                    )
                    .scaleEffect(
                        x: attacker == .enemy ? -1 : 1,
                        y: 1
                    )
                    .position(
                        metrics.point(
                            x: launchCenterX
                                + (attacker == .player ? -1 : 1)
                                * CGFloat(tick),
                            y: 16
                        )
                    )
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BattleImpactOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var target: BattlePresentationSide
    var move: BattlePresentationMove
    var progress: Double
    var critical = false
    var duration: TimeInterval
    var targetSprite: BattlePresentationSprite
    var attackerSprite: BattlePresentationSprite

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let clamped = min(1, max(0, progress))
            let elapsed = clamped * duration
            let travelDuration = BattleOriginalTiming.incomingTravelDuration(
                for: move,
                impactDuration: duration
            )

            ZStack {
                if move == .crunch, elapsed < travelDuration {
                    incomingSprite(
                        sprite: targetSprite,
                        frame: targetSprite.attackFrames[
                            min(1, targetSprite.attackFrames.count - 1)
                        ],
                        mirrored: target == .enemy,
                        elapsed: elapsed,
                        travelDuration: travelDuration,
                        metrics: metrics
                    )
                } else if move == .ability,
                          elapsed < travelDuration {
                    incomingSprite(
                        sprite: attackerSprite,
                        frame: attackerSprite.attackFrames[
                            min(2, attackerSprite.attackFrames.count - 1)
                        ],
                        mirrored: target == .player,
                        elapsed: elapsed,
                        travelDuration: travelDuration,
                        metrics: metrics
                    )
                }

                if let interval = BattleOriginalTiming.hitBurstInterval(for: move),
                   interval.contains(elapsed) {
                    let hitFrame = Int(
                        floor((elapsed - interval.lowerBound) / 0.50)
                    ).isMultiple(of: 2) ? 1 : 0

                    GameSprite(
                        resource: "spr_hit_dtector",
                        frame: hitFrame,
                        size: metrics.length(BattleLogicalMetrics.actorSize)
                    )
                    .position(metrics.point(x: 15, y: 16))
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func incomingSprite(
        sprite: BattlePresentationSprite,
        frame: Int,
        mirrored: Bool,
        elapsed: TimeInterval,
        travelDuration: TimeInterval,
        metrics: BattleLogicalMetrics
    ) -> some View {
        let tick = min(
            55,
            max(
                0,
                Int(floor(
                    elapsed / max(0.001, travelDuration) * 56
                ))
            )
        )
        let centerX = target == .player
            ? CGFloat(-12 + tick)
            : CGFloat(42 - tick)

        return GameSprite(
            resource: sprite.resource,
            frame: frame,
            size: metrics.length(BattleLogicalMetrics.actorSize)
        )
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .position(metrics.point(x: centerX, y: 16))
    }
}

// MARK: - Composite battle stage

struct BattlePresentationTheme {
    var backgroundTop: Color
    var backgroundBottom: Color
    var grid: Color
    var border: Color
    var shadow: Color

    static let detector = BattlePresentationTheme(
        backgroundTop: Color(red: 0.86, green: 0.86, blue: 0.86),
        backgroundBottom: Color(red: 0.65, green: 0.67, blue: 0.66),
        grid: Color(red: 0.15, green: 0.15, blue: 0.15).opacity(0.075),
        border: Color(red: 0.10, green: 0.10, blue: 0.10),
        shadow: Color.black.opacity(0.55)
    )
}

private struct BattlePresentationPixelGrid: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let columns = 30
            let rows = 32

            for column in 0...columns {
                let x = size.width * CGFloat(column) / CGFloat(columns)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for row in 0...rows {
                let y = size.height * CGFloat(row) / CGFloat(rows)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BattlePresentationSpritePose {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 1
    var rotation: Angle = .zero
    var opacity: Double = 1
}

private struct BattlePresentationFrameState {
    var frames: [Int]
    var progress: Double
    var loops: Bool
}

private struct BattleSplitAbilityProjectile: View {
    var resource: String
    var size: CGFloat
    var mirrored: Bool
    var separation: CGFloat

    var body: some View {
        ZStack {
            GameSprite(resource: resource, frame: 3, size: size)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .mask(alignment: .top) {
                    Rectangle().frame(height: size / 2)
                }
                .offset(y: -separation)

            GameSprite(resource: resource, frame: 3, size: size)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .mask(alignment: .bottom) {
                    Rectangle().frame(height: size / 2)
                }
                .offset(y: separation)
        }
        .frame(width: size, height: size)
    }
}

private struct BattleCollisionOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var progress: Double
    var playerMove: BattlePresentationMove
    var enemyMove: BattlePresentationMove
    var playerSprite: BattlePresentationSprite
    var enemySprite: BattlePresentationSprite
    var reducedMotion: Bool
    var outcome = 0

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let clamped = min(1, max(0, progress))
            let maximumPosition = outcome == 0 ? 30 : 60
            let movePosition = BattlePixelMotion.sourceTick(
                progress: clamped,
                maximum: maximumPosition
            )

            ZStack {
                collisionProjectile(
                    side: .player,
                    move: playerMove,
                    opposingMove: enemyMove,
                    resource: playerSprite.resource,
                    movePosition: movePosition,
                    metrics: metrics
                )
                collisionProjectile(
                    side: .enemy,
                    move: enemyMove,
                    opposingMove: playerMove,
                    resource: enemySprite.resource,
                    movePosition: movePosition,
                    metrics: metrics
                )
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sideLoses(
        _ side: BattlePresentationSide,
        move: BattlePresentationMove,
        opposingMove: BattlePresentationMove
    ) -> Bool {
        if outcome == 0 {
            return move == opposingMove
        }
        return side == .player ? outcome < 0 : outcome > 0
    }

    @ViewBuilder
    private func collisionProjectile(
        side: BattlePresentationSide,
        move: BattlePresentationMove,
        opposingMove: BattlePresentationMove,
        resource: String,
        movePosition: Int,
        metrics: BattleLogicalMetrics
    ) -> some View {
        let loses = sideLoses(
            side,
            move: move,
            opposingMove: opposingMove
        )
        let sameMove = move == opposingMove

        switch move {
        case .energy:
            if loses, (15...16).contains(movePosition) {
                collisionSparks(
                    side: side,
                    move: move,
                    metrics: metrics
                )
            } else if !(loses && movePosition >= 16) {
                standardProjectile(
                    side: side,
                    move: move,
                    resource: resource,
                    movePosition: movePosition,
                    metrics: metrics
                )
            }

        case .crunch:
            if loses, sameMove, movePosition >= 14 {
                let centerX = side == .player
                    ? CGFloat(movePosition + 12)
                    : CGFloat(15 - movePosition)
                projectileSprite(
                    side: side,
                    move: move,
                    resource: resource,
                    centerX: centerX,
                    metrics: metrics
                )
            } else if !(loses
                        && opposingMove == .ability
                        && movePosition >= 26) {
                standardProjectile(
                    side: side,
                    move: move,
                    resource: resource,
                    movePosition: movePosition,
                    metrics: metrics
                )
            }

        case .ability:
            if loses, sameMove, (15...16).contains(movePosition) {
                collisionSparks(
                    side: side,
                    move: move,
                    metrics: metrics
                )
            } else if loses, sameMove, movePosition >= 16 {
                EmptyView()
            } else if loses,
                      opposingMove == .energy,
                      movePosition >= 14 {
                let centerX = standardCenterX(
                    side: side,
                    move: move,
                    movePosition: movePosition
                )
                BattleSplitAbilityProjectile(
                    resource: resource,
                    size: metrics.length(BattleLogicalMetrics.actorSize),
                    mirrored: side == .enemy,
                    separation: metrics.length(
                        CGFloat(movePosition - 14) * 3
                    )
                )
                .position(metrics.point(x: centerX, y: 16))
            } else {
                standardProjectile(
                    side: side,
                    move: move,
                    resource: resource,
                    movePosition: movePosition,
                    metrics: metrics
                )
            }
        }
    }

    @ViewBuilder
    private func standardProjectile(
        side: BattlePresentationSide,
        move: BattlePresentationMove,
        resource: String,
        movePosition: Int,
        metrics: BattleLogicalMetrics
    ) -> some View {
        projectileSprite(
            side: side,
            move: move,
            resource: resource,
            centerX: standardCenterX(
                side: side,
                move: move,
                movePosition: movePosition
            ),
            metrics: metrics
        )
    }

    private func standardCenterX(
        side: BattlePresentationSide,
        move: BattlePresentationMove,
        movePosition: Int
    ) -> CGFloat {
        if side == .player {
            let startingCenter: CGFloat = move == .energy ? 42 : 39
            return startingCenter - CGFloat(movePosition)
        }
        return CGFloat(movePosition) - 12
    }

    @ViewBuilder
    private func projectileSprite(
        side: BattlePresentationSide,
        move: BattlePresentationMove,
        resource: String,
        centerX: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        let spriteSize = metrics.length(BattleLogicalMetrics.actorSize)

        if move == .energy {
            GameSprite(
                resource: "spr_energy_dtector",
                frame: 7,
                size: spriteSize
            )
            .scaleEffect(x: side == .enemy ? -1 : 1, y: 1)
            .position(metrics.point(x: centerX, y: 16))
        } else {
            GameSprite(
                resource: resource,
                frame: move == .crunch ? 2 : 3,
                size: spriteSize
            )
            .scaleEffect(x: side == .enemy ? -1 : 1, y: 1)
            .position(metrics.point(x: centerX, y: 16))
        }
    }

    private func collisionSparks(
        side: BattlePresentationSide,
        move: BattlePresentationMove,
        metrics: BattleLogicalMetrics
    ) -> some View {
        let x: CGFloat = side == .player ? 19 : 10
        let yPositions: [CGFloat] = move == .energy
            ? [12, 20]
            : [4, 12, 20, 28]

        return ForEach(Array(yPositions.enumerated()), id: \.offset) { item in
            GameSprite(
                resource: "spr_collision_dtector",
                frame: 0,
                size: metrics.length(BattleLogicalMetrics.collisionSize)
            )
            .position(metrics.point(x: x, y: item.element))
        }
    }
}

private struct BattleSummonFrameState {
    var actorFrame: Int?
    var effectFrame: Int?
    var effectYOffset: CGFloat = 0
}

/// Replays the original Alarm-driven summon counters instead of spreading the
/// six summon frames uniformly across the beat. This keeps the blank flashes,
/// actor/effect alternation, and long final holds that give each reveal weight.
private struct BattleSummonSequence: View {
    @Environment(\.displayScale) private var displayScale

    var side: BattlePresentationSide
    var sprite: BattlePresentationSprite
    var progress: Double
    var duration: TimeInterval

    private static let bossResources: Set<String> = [
        "spr_grumblemon_dtector",
        "spr_gigasmon_dtector",
        "spr_arbormon_dtector",
        "spr_petaldramon_dtector",
        "spr_mercurymon_dtector",
        "spr_sephirotmon_dtector",
        "spr_ranamon_dtector",
        "spr_calmaramon_dtector",
        "spr_duskmon_dtector",
        "spr_velgrmon_dtector"
    ]

    private var isFinalBossSequence: Bool {
        side == .enemy && duration > 9
    }

    private var sourceSchedule: [(counter: Int, steps: Int)] {
        if side == .player {
            return [(0, 10)]
                + (1...16).map { ($0, 15) }
                + [
                    (17, 30),
                    (18, 60),
                    (19, 30),
                    (20, 30),
                    (21, 90)
                ]
        }

        if isFinalBossSequence {
            return [(0, 10)]
                + (1...16).map { ($0, 10) }
                + (17...33).map { ($0, 20) }
                + [
                    // Counter 34 is incremented through in the same Alarm
                    // event in the original, so it never reaches Draw.
                    (35, 60),
                    (36, 60),
                    (37, 60)
                ]
        }

        return [(0, 10)]
            + (1...21).map { ($0, 15) }
            + [
                (22, 30),
                (23, 30),
                (24, 60)
            ]
    }

    private var counter: Int {
        let schedule = sourceSchedule
        let totalSteps = max(1, schedule.reduce(0) { $0 + $1.steps })
        let sourceStep = min(
            totalSteps - 1,
            max(
                0,
                Int(floor(
                    BattlePixelMotion.clamp(progress)
                        * Double(totalSteps)
                ))
            )
        )
        var cursor = 0

        for item in schedule {
            cursor += item.steps
            if sourceStep < cursor {
                return item.counter
            }
        }
        return schedule.last?.counter ?? 0
    }

    private var frameState: BattleSummonFrameState {
        if side == .player {
            switch counter {
            case 0...5:
                return BattleSummonFrameState(
                    actorFrame: nil,
                    effectFrame: counter.isMultiple(of: 2) ? nil : 0
                )
            case 6...11:
                return BattleSummonFrameState(
                    actorFrame: nil,
                    effectFrame: counter.isMultiple(of: 2) ? 1 : 0
                )
            case 12...16:
                return BattleSummonFrameState(
                    actorFrame: nil,
                    effectFrame: counter % 3
                )
            case 17:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: 3
                )
            case 18:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: nil
                )
            case 19:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: 3
                )
            case 20:
                return BattleSummonFrameState(
                    actorFrame: 2,
                    effectFrame: nil
                )
            default:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: nil
                )
            }
        }

        if isFinalBossSequence {
            switch counter {
            case 0...16:
                return BattleSummonFrameState(
                    actorFrame: nil,
                    effectFrame: 4,
                    effectYOffset: counter.isMultiple(of: 2) ? 16 : -16
                )
            case 17...29:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: 4,
                    effectYOffset: counter.isMultiple(of: 2) ? 16 : -16
                )
            case 30...33:
                return BattleSummonFrameState(
                    actorFrame: counter.isMultiple(of: 2) ? 0 : nil,
                    effectFrame: nil
                )
            case 35:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: nil
                )
            case 36:
                return BattleSummonFrameState(
                    actorFrame: 1,
                    effectFrame: nil
                )
            default:
                return BattleSummonFrameState(
                    actorFrame: 0,
                    effectFrame: nil
                )
            }
        }

        let summonFrame = Self.bossResources.contains(sprite.resource) ? 4 : 3
        switch counter {
        case 0...8:
            return BattleSummonFrameState(
                actorFrame: nil,
                effectFrame: counter.isMultiple(of: 2) ? nil : summonFrame
            )
        case 9...17:
            return BattleSummonFrameState(
                actorFrame: counter.isMultiple(of: 2) ? nil : 0,
                effectFrame: counter.isMultiple(of: 2) ? summonFrame : nil
            )
        case 18...20:
            return BattleSummonFrameState(
                actorFrame: counter.isMultiple(of: 2) ? nil : 0,
                effectFrame: nil
            )
        default:
            return BattleSummonFrameState(
                actorFrame: counter.isMultiple(of: 2) ? 1 : 0,
                effectFrame: nil
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let state = frameState

            ZStack {
                if let actorFrame = state.actorFrame {
                    GameSprite(
                        resource: sprite.resource,
                        frame: actorFrame,
                        size: metrics.length(BattleLogicalMetrics.actorSize)
                    )
                    .scaleEffect(x: side == .enemy ? -1 : 1, y: 1)
                    .position(metrics.point(x: 15, y: 16))
                }

                if let effectFrame = state.effectFrame {
                    GameSprite(
                        resource: "spr_summon_dtector",
                        frame: effectFrame,
                        size: metrics.length(BattleLogicalMetrics.height)
                    )
                    .position(
                        metrics.point(
                            x: 15,
                            y: 16 + state.effectYOffset
                        )
                    )
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BattleSourceCounterSchedule {
    var holds: [(counter: Int, steps: Int)]

    func counter(progress: Double) -> Int {
        let total = max(1, holds.reduce(0) { $0 + $1.steps })
        let sourceStep = min(
            total - 1,
            max(
                0,
                Int(
                    floor(
                        BattlePixelMotion.clamp(progress)
                            * Double(total)
                    )
                )
            )
        )
        var cursor = 0

        for hold in holds {
            cursor += hold.steps
            if sourceStep < cursor {
                return hold.counter
            }
        }
        return holds.last?.counter ?? 0
    }
}

/// Exact counter-driven presentation of `obj_digipower_dtector`.
private struct BattleDigiPowerSequence: View {
    @Environment(\.displayScale) private var displayScale

    var spec: BattleDigiPowerSpec
    var progress: Double

    private var schedule: BattleSourceCounterSchedule {
        var holds: [(counter: Int, steps: Int)] = [
            (0, 6),
            (1, 6),
            (2, 30),
            (3, 6),
            (4, 6),
            (5, 30)
        ]

        if spec.succeeds {
            holds += (6...70).map { ($0, 5) }
            holds += (71...135).map { ($0, 3) }
            holds += (136...142).map { ($0, 15) }
            holds += [(143, 90)]
        } else {
            holds += (6...8).map { ($0, 30) }
            holds += [(9, 15)]
            holds += (10...18).map { ($0, 15) }
            holds += [(19, 90)]
        }
        return BattleSourceCounterSchedule(holds: holds)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let counter = schedule.counter(progress: progress)
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let fullSize = metrics.length(BattleLogicalMetrics.height)

            ZStack {
                if counter == 0 || counter == 3 {
                    fullEffect(
                        resource: "spr_summon_dtector",
                        frame: 1,
                        size: fullSize,
                        metrics: metrics
                    )
                } else if counter == 1 || counter == 4 {
                    fullEffect(
                        resource: "spr_summon_dtector",
                        frame: 2,
                        size: fullSize,
                        metrics: metrics
                    )
                } else if counter == 2 || counter == 5 {
                    actor(
                        resource: spec.helperResource,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if !spec.succeeds {
                    if counter <= 18 && counter.isMultiple(of: 2) == false {
                        actor(
                            resource: spec.helperResource,
                            size: actorSize,
                            metrics: metrics
                        )
                    }
                } else if (6...38).contains(counter) {
                    actor(
                        resource: spec.helperResource,
                        size: actorSize,
                        metrics: metrics
                    )
                    catchEffect(
                        frame: 1,
                        y: CGFloat(counter - 38),
                        size: fullSize,
                        metrics: metrics
                    )
                } else if (39...70).contains(counter) {
                    catchEffect(
                        frame: 1,
                        y: CGFloat(counter - 38),
                        size: fullSize,
                        metrics: metrics
                    )
                } else if (71...134).contains(counter) {
                    actor(
                        resource: spec.spiritResource,
                        size: actorSize,
                        metrics: metrics
                    )
                    catchEffect(
                        frame: 0,
                        y: 48 - CGFloat(counter - 71),
                        size: fullSize,
                        metrics: metrics
                    )
                } else {
                    actor(
                        resource: spec.spiritResource,
                        size: actorSize,
                        metrics: metrics
                    )
                    if counter.isMultiple(of: 2) {
                        fullEffect(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize,
                            metrics: metrics
                        )
                    }
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func actor(
        resource: String,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: 0, size: size)
            .position(metrics.point(x: 15, y: 16))
    }

    private func fullEffect(
        resource: String,
        frame: Int,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: frame, size: size)
            .position(metrics.point(x: 15, y: 16))
    }

    private func catchEffect(
        frame: Int,
        y: CGFloat,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(
            resource: "spr_catch_dtector",
            frame: frame,
            size: size
        )
        .position(metrics.point(x: 15, y: y))
    }
}

/// Exact port of obj_spirit_dtector. The counter ranges, alarm holds, blank
/// flashes, four-way spirit split, character lift, catch sweep and final
/// 0/1/0 pose are taken directly from the decompiled GML.
private struct BattleSpiritEvolutionSequence: View {
    @Environment(\.displayScale) private var displayScale

    var side: BattlePresentationSide
    var spec: BattleSpiritEvolutionSpec
    var progress: Double

    private var schedule: BattleSourceCounterSchedule {
        var holds: [(counter: Int, steps: Int)] = [(0, 30)]

        if spec.swapsCharacter {
            holds += (1...61).map { ($0, 3) }
        }

        holds += (62...69).map { ($0, 15) }
        holds += [(70, 15), (71, 15), (72, 45), (73, 15)]
        holds += (74...77).map { ($0, 15) }
        holds += [(78, 30)]
        holds += (79...110).map { ($0, 6) }
        holds += [(111, 3)]
        holds += (112...143).map { ($0, 3) }
        holds += (144...162).map { ($0, 15) }
        holds += [(163, 60)]
        holds += (164...195).map { ($0, 6) }
        holds += (196...199).map { ($0, 30) }
        return BattleSourceCounterSchedule(holds: holds)
    }

    private var counter: Int {
        schedule.counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let fullSize = metrics.length(BattleLogicalMetrics.height)
            let counter = counter

            ZStack {
                if counter == 0 {
                    actor(
                        resource: spec.oldCharacterResource,
                        frame: 0,
                        mirrored: false,
                        x: 15,
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (1...30).contains(counter) {
                    actor(
                        resource: spec.oldCharacterResource,
                        frame: 0,
                        mirrored: true,
                        x: 39 - CGFloat(counter),
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (31...61).contains(counter) {
                    actor(
                        resource: spec.newCharacterResource,
                        frame: 0,
                        mirrored: false,
                        x: 45 - CGFloat(counter - 31),
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (62...68).contains(counter) {
                    actor(
                        resource: spec.newCharacterResource,
                        frame: 0,
                        mirrored: false,
                        x: 15,
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                    if counter.isMultiple(of: 2) {
                        fullEffect(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize,
                            metrics: metrics
                        )
                    }
                } else if (69...72).contains(counter) {
                    actor(
                        resource: spec.newCharacterSpiritResource,
                        frame: 0,
                        mirrored: false,
                        x: 15,
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                    if counter.isMultiple(of: 2) {
                        fullEffect(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize,
                            metrics: metrics
                        )
                    }
                } else if (73...77).contains(counter) {
                    if !counter.isMultiple(of: 2) {
                        actor(
                            resource: "spr_spirits_dtector",
                            frame: spec.spiritFrame,
                            mirrored: false,
                            x: 15,
                            y: 16,
                            size: actorSize,
                            metrics: metrics
                        )
                    }
                } else if (78...110).contains(counter) {
                    let distance = CGFloat(counter - 78)
                    ForEach(0..<4, id: \.self) { index in
                        let point: CGPoint = {
                            switch index {
                            case 0:
                                return CGPoint(x: 15 - distance, y: 16)
                            case 1:
                                return CGPoint(x: 15 + distance, y: 16)
                            case 2:
                                return CGPoint(x: 15, y: 16 - distance)
                            default:
                                return CGPoint(x: 15, y: 16 + distance)
                            }
                        }()
                        actor(
                            resource: "spr_spirits_dtector",
                            frame: spec.spiritFrame,
                            mirrored: false,
                            x: point.x,
                            y: point.y,
                            size: actorSize,
                            metrics: metrics
                        )
                    }
                } else if (111...143).contains(counter) {
                    actor(
                        resource: spec.newCharacterResource,
                        frame: 0,
                        mirrored: false,
                        x: 15,
                        y: 48 - CGFloat(counter - 111) * 2,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (144...150).contains(counter) {
                    fullEffect(
                        resource: "spr_summon_dtector",
                        frame: counter.isMultiple(of: 2) ? 2 : 0,
                        size: fullSize,
                        metrics: metrics
                    )
                } else if (151...162).contains(counter) {
                    fullEffect(
                        resource: "spr_summon_dtector",
                        frame: 0,
                        size: fullSize,
                        metrics: metrics
                    )
                    if counter.isMultiple(of: 2) {
                        actor(
                            resource: spec.evolvedResource,
                            frame: 4,
                            mirrored: false,
                            x: 15,
                            y: 16,
                            size: actorSize,
                            metrics: metrics
                        )
                    }
                } else if (163...196).contains(counter) {
                    actor(
                        resource: spec.evolvedResource,
                        frame: 0,
                        mirrored: false,
                        x: 15,
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                    fullEffect(
                        resource: "spr_catch_dtector",
                        frame: 0,
                        y: 48 - CGFloat(counter - 163) * 2,
                        size: fullSize,
                        metrics: metrics
                    )
                } else {
                    actor(
                        resource: spec.evolvedResource,
                        frame: counter == 197 ? 1 : 0,
                        mirrored: false,
                        x: 15,
                        y: 16,
                        size: actorSize,
                        metrics: metrics
                    )
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func actor(
        resource: String,
        frame: Int,
        mirrored: Bool,
        x: CGFloat,
        y: CGFloat,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: frame, size: size)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(metrics.point(x: x, y: y))
    }

    private func fullEffect(
        resource: String,
        frame: Int,
        y: CGFloat = 16,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: frame, size: size)
            .position(metrics.point(x: 15, y: y))
    }
}

/// Exact port of obj_ancient_evo_dtector. Both required spirits enter and
/// leave separately before the Ancient cover opens over the character.
private struct BattleAncientEvolutionSequence: View {
    @Environment(\.displayScale) private var displayScale

    var spec: BattleAncientEvolutionSpec
    var progress: Double

    private var schedule: BattleSourceCounterSchedule {
        var holds: [(counter: Int, steps: Int)] = [(0, 3)]
        holds += (1...28).map { ($0, 2) }
        holds += (29...35).map { ($0, 6) }
        holds += (36...65).map { ($0, 2) }
        holds += (66...93).map { ($0, 2) }
        holds += (94...100).map { ($0, 6) }
        holds += (101...129).map { ($0, 2) }
        holds += (130...136).map { ($0, 15) }
        holds += [(137, 60)]
        holds += (138...144).map { ($0, 15) }
        holds += [(145, 30), (146, 30)]
        holds += (147...166).map { ($0, 15) }
        holds += (167...171).map { ($0, 30) }
        return BattleSourceCounterSchedule(holds: holds)
    }

    private var counter: Int {
        schedule.counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let fullSize = metrics.length(BattleLogicalMetrics.height)
            let counter = counter

            ZStack {
                if (0...28).contains(counter) {
                    spirit(
                        frame: spec.firstSpiritFrame,
                        y: 48 - CGFloat(counter),
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if (29...35).contains(counter) {
                    spirit(
                        frame: spec.firstSpiritFrame,
                        y: 16,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                    if !counter.isMultiple(of: 2) {
                        effect(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            fullSize: fullSize,
                            metrics: metrics
                        )
                    }
                } else if (36...64).contains(counter) {
                    spirit(
                        frame: spec.firstSpiritFrame,
                        y: 16 - CGFloat(counter - 36),
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if (65...93).contains(counter) {
                    spirit(
                        frame: spec.secondSpiritFrame,
                        y: 48 - CGFloat(counter - 65),
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if (94...100).contains(counter) {
                    spirit(
                        frame: spec.secondSpiritFrame,
                        y: 16,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                    if !counter.isMultiple(of: 2) {
                        effect(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            fullSize: fullSize,
                            metrics: metrics
                        )
                    }
                } else if (101...129).contains(counter) {
                    spirit(
                        frame: spec.secondSpiritFrame,
                        y: 16 - CGFloat(counter - 101),
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if (130...136).contains(counter) {
                    ancientBase(
                        frame: counter.isMultiple(of: 2) ? 1 : 0,
                        coverFrame: 0,
                        fullSize: fullSize,
                        metrics: metrics
                    )
                } else if counter == 137 || counter == 145 {
                    actor(
                        resource: spec.characterResource,
                        frame: 0,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (138...144).contains(counter) {
                    ancientBase(
                        frame: counter.isMultiple(of: 2) ? 1 : 0,
                        coverFrame: 0,
                        fullSize: fullSize,
                        metrics: metrics
                    )
                } else if counter == 146 {
                    actor(
                        resource: spec.characterSpiritResource,
                        frame: 0,
                        size: actorSize,
                        metrics: metrics
                    )
                } else if (147...154).contains(counter) {
                    ancientBase(
                        frame: counter.isMultiple(of: 2) ? 1 : 0,
                        coverFrame: min(3, (counter - 147) / 2),
                        fullSize: fullSize,
                        metrics: metrics
                    )
                } else if (155...161).contains(counter) {
                    if !counter.isMultiple(of: 2) {
                        effect(
                            resource: "spr_ancient_cover_dtector",
                            frame: 3,
                            fullSize: fullSize,
                            metrics: metrics
                        )
                    }
                } else if (162...166).contains(counter) {
                    if !counter.isMultiple(of: 2) {
                        actor(
                            resource: spec.evolvedResource,
                            frame: 0,
                            size: actorSize,
                            metrics: metrics
                        )
                    }
                } else {
                    actor(
                        resource: spec.evolvedResource,
                        frame: counter == 168 ? 1 : 0,
                        size: actorSize,
                        metrics: metrics
                    )
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func spirit(
        frame: Int,
        y: CGFloat,
        actorSize: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(
            resource: "spr_spirits_dtector",
            frame: frame,
            size: actorSize
        )
        .position(metrics.point(x: 15, y: y))
    }

    private func actor(
        resource: String,
        frame: Int,
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: frame, size: size)
            .position(metrics.point(x: 15, y: 16))
    }

    private func effect(
        resource: String,
        frame: Int,
        fullSize: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: frame, size: fullSize)
            .position(metrics.point(x: 15, y: 16))
    }

    private func ancientBase(
        frame: Int,
        coverFrame: Int,
        fullSize: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        ZStack {
            GameSprite(
                resource: "spr_ancient_dtector",
                frame: frame,
                size: fullSize
            )
            GameSprite(
                resource: "spr_ancient_cover_dtector",
                frame: coverFrame,
                size: fullSize
            )
        }
        .position(metrics.point(x: 15, y: 16))
    }
}

/// obj_evo_enemy_dtector used by the chained final bosses. The old body splits
/// horizontally, blinks and lifts away; the evolved body then converges from
/// both sides before its final idle hold.
private struct BattleEnemyEvolutionSequence: View {
    @Environment(\.displayScale) private var displayScale

    var spec: BattleEnemyEvolutionSpec
    var progress: Double

    private var schedule: BattleSourceCounterSchedule {
        var holds: [(counter: Int, steps: Int)] = [(0, 10)]
        holds += (1...25).map { ($0, 6) }
        holds += [(26, 6), (27, 30)]
        holds += (28...31).map { ($0, 12) }
        holds += [(32, 6)]
        holds += (33...45).map { ($0, 6) }
        holds += (46...74).map { ($0, 6) }
        holds += [(75, 12), (76, 12)]
        holds += (77...91).map { ($0, 12) }
        holds += (92...103).map { ($0, 6) }
        holds += [(104, 60)]
        return BattleSourceCounterSchedule(holds: holds)
    }

    private var counter: Int {
        schedule.counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let counter = counter

            ZStack {
                if counter <= 26 {
                    let spread = counter == 26
                        ? CGFloat(0)
                        : CGFloat(min(25, counter))
                    ForEach(0..<3, id: \.self) { index in
                        enemyActor(
                            resource: spec.oldResource,
                            x: 15 + CGFloat(index - 1) * spread,
                            y: 16,
                            actorSize: actorSize,
                            metrics: metrics
                        )
                    }
                } else if counter <= 31 {
                    if !counter.isMultiple(of: 2) {
                        enemyActor(
                            resource: spec.oldResource,
                            x: 15,
                            y: 16,
                            actorSize: actorSize,
                            metrics: metrics
                        )
                    }
                } else if counter <= 44 {
                    enemyActor(
                        resource: spec.oldResource,
                        x: 15,
                        y: 16 - CGFloat(counter - 32) * 2,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if counter <= 75 {
                    let travel = CGFloat(min(29, max(0, counter - 45)))
                    enemyActor(
                        resource: spec.newResource,
                        x: -14 + travel,
                        y: 16,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                    enemyActor(
                        resource: spec.newResource,
                        x: 44 - travel,
                        y: 16,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                } else if counter <= 86 {
                    if !counter.isMultiple(of: 2) {
                        enemyActor(
                            resource: spec.newResource,
                            x: 15,
                            y: 16,
                            actorSize: actorSize,
                            metrics: metrics
                        )
                    }
                } else {
                    enemyActor(
                        resource: spec.newResource,
                        x: 15,
                        y: 16,
                        actorSize: actorSize,
                        metrics: metrics
                    )
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func enemyActor(
        resource: String,
        x: CGFloat,
        y: CGFloat,
        actorSize: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: resource, frame: 0, size: actorSize)
            .scaleEffect(x: -1, y: 1)
            .position(metrics.point(x: x, y: y))
    }
}

/// obj_spirit_check_dtector: ten 15-step alternating checks before selection.
private struct BattleSpiritCheckSequence: View {
    @Environment(\.displayScale) private var displayScale

    var remainingValue: Int
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let counter = min(
                9,
                max(0, Int(BattlePixelMotion.clamp(progress) * 10))
            )

            ZStack {
                GameSprite(
                    resource: "spr_spirit_power_dtector",
                    frame: counter.isMultiple(of: 2) ? 5 : 4,
                    size: metrics.length(BattleLogicalMetrics.height)
                )
                .position(metrics.point(x: 15, y: 16))

                ClassicLCDNumber(
                    value: remainingValue,
                    white: true,
                    scale: metrics.scale
                )
                .position(
                    metrics.point(
                        x: ClassicLCDNumber.logicalCenter(
                            for: remainingValue,
                            leastSignificantX: 23
                        ),
                        y: 26.5
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// obj_spirit_ready_dtector: seven half-second ready flashes.
private struct BattleSpiritReadySequence: View {
    @Environment(\.displayScale) private var displayScale

    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let counter = min(
                7,
                max(0, Int(BattlePixelMotion.clamp(progress) * 8))
            )

            GameSprite(
                resource: "spr_spirit_ready_dtector",
                frame: counter.isMultiple(of: 2) ? 1 : 0,
                size: metrics.length(BattleLogicalMetrics.height)
            )
            .position(metrics.point(x: 15, y: 16))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// obj_spirit_power_reduce_dtector: 5.5 seconds of alternating power frames,
/// with the remaining D-Power displayed only after the charge settles.
private struct BattleSpiritPowerSpendSequence: View {
    @Environment(\.displayScale) private var displayScale

    var remainingValue: Int
    var progress: Double

    private var counter: Int {
        var holds = [(0, 15)]
        holds += (1...12).map { ($0, 15) }
        holds += (14...22).map { ($0, 15) }
        return BattleSourceCounterSchedule(holds: holds)
            .counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let fullSize = metrics.length(BattleLogicalMetrics.height)
            let scale = metrics.scale
            let counter = counter
            let frame: Int = {
                if counter <= 8 {
                    return counter.isMultiple(of: 2) ? 1 : 0
                }
                if counter <= 13 {
                    return counter.isMultiple(of: 2) ? 3 : 2
                }
                return counter.isMultiple(of: 2) ? 5 : 4
            }()

            ZStack {
                GameSprite(
                    resource: "spr_spirit_power_dtector",
                    frame: frame,
                    size: fullSize
                )
                .position(metrics.point(x: 15, y: 16))

                if counter > 13 {
                    ClassicLCDNumber(
                        value: remainingValue,
                        white: true,
                        scale: scale
                    )
                    .position(
                        metrics.point(
                            x: ClassicLCDNumber.logicalCenter(
                                for: remainingValue,
                                leastSignificantX: 23
                            ),
                            y: 26.5
                        )
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// obj_evo_dtector: the ordinary called Digimon flashes out, changes form at
/// counter 10, then returns with one full-screen summon flash.
private struct BattleSimpleEvolutionSequence: View {
    @Environment(\.displayScale) private var displayScale

    var sprite: BattlePresentationSprite
    var mirrored: Bool
    var progress: Double

    private var counter: Int {
        var holds = (0...17).map { ($0, 15) }
        holds.append((18, 60))
        return BattleSourceCounterSchedule(holds: holds)
            .counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let fullSize = metrics.length(BattleLogicalMetrics.height)
            let counter = counter

            ZStack {
                if counter <= 4 {
                    actor(size: actorSize, metrics: metrics)
                    if !counter.isMultiple(of: 2) {
                        summon(size: fullSize, metrics: metrics)
                    }
                } else if counter <= 14 {
                    if !counter.isMultiple(of: 2) {
                        actor(size: actorSize, metrics: metrics)
                    }
                } else {
                    actor(size: actorSize, metrics: metrics)
                    if counter == 16 {
                        summon(size: fullSize, metrics: metrics)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func actor(
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(resource: sprite.resource, frame: 0, size: size)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(metrics.point(x: 15, y: 16))
    }

    private func summon(
        size: CGFloat,
        metrics: BattleLogicalMetrics
    ) -> some View {
        GameSprite(
            resource: "spr_summon_dtector",
            frame: 3,
            size: size
        )
        .position(metrics.point(x: 15, y: 16))
    }
}

/// obj_deport_dtector: three initial flashes followed by four alpha copies
/// spreading one logical pixel per three source steps.
private struct BattleDeportSequence: View {
    @Environment(\.displayScale) private var displayScale

    var sprite: BattlePresentationSprite
    var progress: Double

    private var state: (display: Int, movement: Int) {
        let totalSteps = 168
        let step = min(
            totalSteps - 1,
            max(
                0,
                Int(
                    floor(
                        BattlePixelMotion.clamp(progress)
                            * Double(totalSteps)
                    )
                )
            )
        )
        if step < 60 {
            return (min(5, step / 10), 0)
        }
        return (5, min(35, (step - 60) / 3))
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let state = state

            ZStack {
                if !state.display.isMultiple(of: 2) {
                    let distance = CGFloat(state.movement)
                    ForEach(0..<4, id: \.self) { index in
                        let point: CGPoint = {
                            switch index {
                            case 0:
                                return CGPoint(x: 15 - distance, y: 16)
                            case 1:
                                return CGPoint(x: 15 + distance, y: 16)
                            case 2:
                                return CGPoint(x: 15, y: 16 - distance)
                            default:
                                return CGPoint(x: 15, y: 16 + distance)
                            }
                        }()
                        GameSprite(
                            resource: sprite.resource,
                            frame: 0,
                            size: actorSize
                        )
                        .position(metrics.point(x: point.x, y: point.y))
                    }
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// obj_spirit_off_dtector: the Spirit splits vertically, flashes out, then the
/// owning character returns in its two attack poses.
private struct BattleSpiritOffSequence: View {
    @Environment(\.displayScale) private var displayScale

    var spec: BattleSpiritOffSpec
    var progress: Double

    private var counter: Int {
        var holds = [(0, 6)]
        holds += (1...17).map { ($0, 6) }
        holds += (18...31).map { ($0, 15) }
        holds += [(32, 60), (33, 60), (34, 60)]
        return BattleSourceCounterSchedule(holds: holds)
            .counter(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let fullSize = metrics.length(BattleLogicalMetrics.height)
            let counter = counter

            ZStack {
                if counter <= 16 {
                    let distance = CGFloat(counter)
                    ForEach([-1, 1], id: \.self) { direction in
                        GameSprite(
                            resource: spec.evolvedResource,
                            frame: 0,
                            size: actorSize
                        )
                        .position(
                            metrics.point(
                                x: 15,
                                y: 16 + CGFloat(direction) * distance
                            )
                        )
                    }
                } else if counter <= 21 {
                    if !counter.isMultiple(of: 2) {
                        ForEach([-1, 1], id: \.self) { direction in
                            GameSprite(
                                resource: spec.evolvedResource,
                                frame: 0,
                                size: actorSize
                            )
                            .position(
                                metrics.point(
                                    x: 15,
                                    y: 16 + CGFloat(direction) * 16
                                )
                            )
                        }
                    }
                } else if counter <= 26 {
                    if !counter.isMultiple(of: 2) {
                        GameSprite(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize
                        )
                        .position(metrics.point(x: 15, y: 16))
                    }
                } else if counter <= 31 {
                    GameSprite(
                        resource: spec.characterResource,
                        frame: 0,
                        size: actorSize
                    )
                    .position(metrics.point(x: 15, y: 16))
                    if !counter.isMultiple(of: 2) {
                        GameSprite(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize
                        )
                        .position(metrics.point(x: 15, y: 16))
                    }
                } else if counter == 32 {
                    GameSprite(
                        resource: spec.characterResource,
                        frame: 0,
                        size: actorSize
                    )
                    .position(metrics.point(x: 15, y: 16))
                } else {
                    GameSprite(
                        resource: "\(spec.characterResource)_attack",
                        frame: counter == 33 ? 0 : 1,
                        size: actorSize
                    )
                    .position(metrics.point(x: 15, y: 16))
                    if counter == 33 {
                        GameSprite(
                            resource: "spr_summon_dtector",
                            frame: 5,
                            size: fullSize
                        )
                        .position(metrics.point(x: 15, y: 16))
                    }
                }
            }
            .mask {
                Rectangle()
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// obj_position_dtector: the character crosses the LCD from the right in
/// 24 one-pixel steps before the happy/sad idle state takes over.
private struct BattleCharacterReturnSequence: View {
    @Environment(\.displayScale) private var displayScale

    var resource: String
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let actorSize = metrics.length(BattleLogicalMetrics.actorSize)
            let counter = min(
                24,
                max(
                    0,
                    Int(
                        floor(
                            BattlePixelMotion.clamp(progress) * 25
                        )
                    )
                )
            )

            GameSprite(resource: resource, frame: 0, size: actorSize)
                .scaleEffect(x: -1, y: 1)
                .position(
                    metrics.point(
                        x: 39 - CGFloat(counter),
                        y: 16
                    )
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct BattleFullScreenSequence: View {
    @Environment(\.displayScale) private var displayScale

    var resource: String
    var frames: [Int]
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let safeFrames = frames.isEmpty ? [0] : frames
            let index = min(
                safeFrames.count - 1,
                Int(min(0.999, max(0, progress)) * Double(safeFrames.count))
            )

            GameSprite(
                resource: resource,
                frame: safeFrames[index],
                size: metrics.length(BattleLogicalMetrics.height)
            )
            .position(metrics.point(x: 15, y: 16))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Recreates the original capture cadence: the scanner travels from below the
/// display, carries the target off the top edge, then reveals the D-Tector
/// confirmation graphic.
private struct BattleCaptureSequence: View {
    @Environment(\.displayScale) private var displayScale

    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let progress = min(1, max(0, progress))
            let captureEnd = 0.86
            let size = metrics.length(BattleLogicalMetrics.height)

            ZStack {
                if progress < captureEnd {
                    let travel = CGFloat(progress / captureEnd)

                    GameSprite(
                        resource: "spr_catch_dtector",
                        frame: 0,
                        size: size
                    )
                    .position(
                        metrics.point(
                            x: 15,
                            y: 48 - travel * 64
                        )
                    )
                } else {
                    let confirmationProgress =
                        (progress - captureEnd) / (1 - captureEnd)

                    if Int(confirmationProgress * 10).isMultiple(of: 2) {
                        GameSprite(
                            resource: "spr_dtector_catch_dtector",
                            frame: 0,
                            size: size
                        )
                        .position(metrics.point(x: 15, y: 16))
                    }

                    GameSprite(
                        resource: "spr_dtector_catch_dtector",
                        frame: 1,
                        size: size
                    )
                    .position(metrics.point(x: 15, y: 16))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BattlePresentationStage: View {
    @ObservedObject private var director: BattlePresentationDirector
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private let player: BattlePresentationSprite
    private let enemy: BattlePresentationSprite
    private let theme: BattlePresentationTheme
    private let showsGrid: Bool
    private let cornerRadius: CGFloat

    init(
        director: BattlePresentationDirector,
        player: BattlePresentationSprite,
        enemy: BattlePresentationSprite,
        theme: BattlePresentationTheme = .detector,
        showsGrid: Bool = true,
        cornerRadius: CGFloat = 5
    ) {
        _director = ObservedObject(wrappedValue: director)
        self.player = player
        self.enemy = enemy
        self.theme = theme
        self.showsGrid = showsGrid
        self.cornerRadius = max(0, cornerRadius)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let sample = director.sample(at: context.date)
            stage(sample: sample, date: context.date)
        }
        .accessibilityElement(children: .contain)
    }

    private func stage(
        sample: BattlePresentationSample,
        date: Date
    ) -> some View {
        GeometryReader { geometry in
            let metrics = BattleLogicalMetrics(
                size: geometry.size,
                displayScale: displayScale
            )
            let beatDuration = duration(for: sample)
            let playerPose = pose(
                for: .player,
                sample: sample,
                beatDuration: beatDuration
            )
            let enemyPose = pose(
                for: .enemy,
                sample: sample,
                beatDuration: beatDuration
            )
            let playerFrames = frameState(
                for: player,
                side: .player,
                sample: sample,
                date: date
            )
            let enemyFrames = frameState(
                for: enemy,
                side: .enemy,
                sample: sample,
                date: date
            )

            ZStack {
                Rectangle()
                    .fill(theme.backgroundBottom)

                if showsGrid {
                    BattlePresentationPixelGrid(color: theme.grid)
                }

                BattlePixelSpriteAnimator(
                    resource: player.resource,
                    frames: playerFrames.frames,
                    progress: playerFrames.progress,
                    loops: playerFrames.loops,
                    size: metrics.length(BattleLogicalMetrics.actorSize),
                    mirrored: false,
                    opacity: playerPose.opacity,
                    scale: playerPose.scale,
                    rotation: playerPose.rotation,
                    accessibilityLabel: player.accessibilityLabel.isEmpty
                        ? "Player battle sprite"
                        : player.accessibilityLabel
                )
                .position(
                    metrics.point(
                        x: 15 + playerPose.x,
                        y: 16 + playerPose.y
                    )
                )

                BattlePixelSpriteAnimator(
                    resource: enemy.resource,
                    frames: enemyFrames.frames,
                    progress: enemyFrames.progress,
                    loops: enemyFrames.loops,
                    size: metrics.length(BattleLogicalMetrics.actorSize),
                    mirrored: true,
                    opacity: enemyPose.opacity,
                    scale: enemyPose.scale,
                    rotation: enemyPose.rotation,
                    accessibilityLabel: enemy.accessibilityLabel.isEmpty
                        ? "Enemy battle sprite"
                        : enemy.accessibilityLabel
                )
                .position(
                    metrics.point(
                        x: 15 + enemyPose.x,
                        y: 16 + enemyPose.y
                    )
                )

                if let projectile = projectileDescriptor(for: sample) {
                    let attackingSprite = projectile.attacker == .player
                        ? player
                        : enemy
                    BattleProjectileOverlay(
                        attacker: projectile.attacker,
                        move: projectile.move,
                        progress: sample.beatProgress,
                        reducedMotion: reduceMotion,
                        spriteResource: attackingSprite.resource,
                        mirrored: projectile.attacker == .enemy
                    )
                }

                if let impact = impactDescriptor(for: sample) {
                    BattleImpactOverlay(
                        target: impact.target,
                        move: impact.move,
                        progress: sample.beatProgress,
                        critical: impact.critical,
                        duration: beatDuration,
                        targetSprite: impact.target == .player
                            ? player
                            : enemy,
                        attackerSprite: impact.target == .player
                            ? enemy
                            : player
                    )
                }

                if case let .collision(playerMove, enemyMove) = sample.phase {
                    BattleCollisionOverlay(
                        progress: sample.beatProgress,
                        playerMove: playerMove,
                        enemyMove: enemyMove,
                        playerSprite: player,
                        enemySprite: enemy,
                        reducedMotion: reduceMotion,
                        outcome: sample.collisionOutcome ?? 0
                    )
                }

                switch sample.phase {
                case .callPower(let remainingValue):
                    ClassicPixelAsset(
                        resource: "spr_battle_call_dtector",
                        frame: max(0, min(8, remainingValue))
                    )
                    .frame(
                        width: metrics.viewportSize.width,
                        height: metrics.viewportSize.height
                    )
                    .position(metrics.viewportCenter)
                case .spiritCheck(let remainingValue):
                    BattleSpiritCheckSequence(
                        remainingValue: remainingValue,
                        progress: sample.beatProgress
                    )
                case .summon(let side):
                    BattleSummonSequence(
                        side: side,
                        sprite: side == .player ? player : enemy,
                        progress: sample.beatProgress,
                        duration: beatDuration
                    )
                case .evolution:
                    BattleSimpleEvolutionSequence(
                        sprite: visibleEvolutionSide(for: sample.phase) == .enemy
                            ? enemy
                            : player,
                        mirrored: visibleEvolutionSide(for: sample.phase) == .enemy,
                        progress: sample.beatProgress
                    )
                case .spiritEvolution(_, let spec):
                    BattleSpiritEvolutionSequence(
                        side: .player,
                        spec: spec,
                        progress: sample.beatProgress
                    )
                case .ancientEvolution(_, let spec):
                    BattleAncientEvolutionSequence(
                        spec: spec,
                        progress: sample.beatProgress
                    )
                case .enemyEvolution(let spec):
                    BattleEnemyEvolutionSequence(
                        spec: spec,
                        progress: sample.beatProgress
                    )
                case .spiritOff(_, let spec):
                    BattleSpiritOffSequence(
                        spec: spec,
                        progress: sample.beatProgress
                    )
                case .characterReturn(let resource):
                    BattleCharacterReturnSequence(
                        resource: resource,
                        progress: sample.beatProgress
                    )
                case .spiritPower(let remainingValue):
                    BattleSpiritPowerSpendSequence(
                        remainingValue: remainingValue,
                        progress: sample.beatProgress
                    )
                case .spiritReady:
                    BattleSpiritReadySequence(
                        progress: sample.beatProgress
                    )
                case .digiPower(let spec):
                    BattleDigiPowerSequence(
                        spec: spec,
                        progress: sample.beatProgress
                    )
                case .capture:
                    BattleCaptureSequence(progress: sample.beatProgress)
                        .blendMode(.multiply)
                case .deport:
                    BattleDeportSequence(
                        sprite: player,
                        progress: sample.beatProgress
                    )
                default:
                    EmptyView()
                }
            }
            .frame(
                width: metrics.viewportSize.width,
                height: metrics.viewportSize.height
            )
            .clipped()
        }
    }

    private func pose(
        for side: BattlePresentationSide,
        sample: BattlePresentationSample,
        beatDuration: TimeInterval
    ) -> BattlePresentationSpritePose {
        let progress = CGFloat(min(1, max(0, sample.beatProgress)))
        var pose = BattlePresentationSpritePose()

        guard visibleSide(for: sample.phase) == side else {
            pose.opacity = 0
            return pose
        }

        switch sample.phase {
        case .windUp(let attacker, _) where attacker == side:
            let neutralFraction = CGFloat(
                BattleOriginalTiming.neutral
                    / (BattleOriginalTiming.neutral
                        + BattleOriginalTiming.anticipation)
            )
            let anticipation = max(
                0,
                min(1, (progress - neutralFraction) / (1 - neutralFraction))
            )
            pose.x = side.direction * BattlePixelMotion.steppedEaseOut(
                progress: Double(anticipation),
                distance: 4
            )

        case .projectile(let attacker, _) where attacker == side:
            pose.x = side.direction * 4

        case .impact(let target, let move, _) where target == side:
            let elapsed = sample.beatProgress * beatDuration
            if !BattleOriginalTiming.targetIsVisible(
                move: move,
                elapsed: elapsed,
                impactDuration: beatDuration
            ) {
                pose.opacity = 0
            }

        case .capture(let captured) where captured == side:
            let liftStart = CGFloat(0.43)
            let liftEnd = CGFloat(0.86)
            if progress >= liftEnd {
                pose.opacity = 0
            } else if progress >= liftStart {
                let lift = (progress - liftStart) / (liftEnd - liftStart)
                if reduceMotion {
                    pose.opacity = 1 - Double(lift)
                } else {
                    pose.y = -lift * 32
                }
            }

        case .deport(let deported) where deported == side:
            pose.opacity = max(0, 1 - Double(progress))

        default:
            break
        }

        return pose
    }

    private func visibleSide(
        for phase: BattlePresentationPhase
    ) -> BattlePresentationSide? {
        switch phase {
        case .capture(let side),
             .evade(let side),
             .victory(let side),
             .defeat(let side):
            return side
        case .windUp(let attacker, _),
             .projectile(let attacker, _):
            return attacker
        case .impact(let target, _, _):
            return target
        case .idle, .intro, .summon, .ready, .collision, .callPower,
             .spiritCheck, .spiritPower, .spiritReady, .digiPower,
             .deport,
             .evolution,
             .spiritEvolution, .ancientEvolution, .enemyEvolution, .spiritOff,
             .characterReturn, .recovery:
            return nil
        }
    }

    private func visibleEvolutionSide(
        for phase: BattlePresentationPhase
    ) -> BattlePresentationSide {
        if case let .evolution(side) = phase {
            return side
        }
        return .player
    }

    private func duration(
        for sample: BattlePresentationSample
    ) -> TimeInterval {
        guard director.timeline.beats.indices.contains(sample.beatIndex) else {
            return 0.01
        }
        return director.timeline.beats[sample.beatIndex].duration
    }

    private func frameState(
        for sprite: BattlePresentationSprite,
        side: BattlePresentationSide,
        sample: BattlePresentationSample,
        date: Date
    ) -> BattlePresentationFrameState {
        let actionFrames: [Int]?

        switch sample.phase {
        case .windUp(let attacker, _) where attacker == side:
            actionFrames = [sprite.idleFrames[0]]
        case .projectile(let attacker, let move) where attacker == side:
            // Energy and Ability keep frame 1 on the attacker; frame 3 is
            // the Ability projectile. Crunch uses frame 2 for both body/trail.
            let frameIndex = min(
                sprite.attackFrames.count - 1,
                move == .crunch ? 1 : 0
            )
            actionFrames = [sprite.attackFrames[frameIndex]]
        case .impact(let target, _, _) where target == side:
            actionFrames = [sprite.idleFrames[0]]
        case .victory(let winner) where winner == side:
            actionFrames = sprite.victoryFrames
        case .defeat(let loser) where loser == side:
            actionFrames = sprite.defeatFrames
        default:
            actionFrames = nil
        }

        if let actionFrames {
            return BattlePresentationFrameState(
                frames: actionFrames,
                progress: sample.beatProgress,
                loops: sample.phase.isVictory
            )
        }

        let frameCount = max(1, sprite.idleFrames.count)
        let cycle = date.timeIntervalSinceReferenceDate
            * sprite.framesPerSecond
            / Double(frameCount)
        let loopProgress = cycle - floor(cycle)
        return BattlePresentationFrameState(
            frames: sprite.idleFrames,
            progress: loopProgress,
            loops: true
        )
    }

    private func projectileDescriptor(
        for sample: BattlePresentationSample
    ) -> (attacker: BattlePresentationSide, move: BattlePresentationMove)? {
        guard case let .projectile(attacker, move) = sample.phase else {
            return nil
        }
        return (attacker, move)
    }

    private func impactDescriptor(
        for sample: BattlePresentationSample
    ) -> (
        target: BattlePresentationSide,
        move: BattlePresentationMove,
        critical: Bool
    )? {
        guard case let .impact(target, move, critical) = sample.phase else {
            return nil
        }
        return (target, move, critical)
    }

}

private extension BattlePresentationPhase {
    var isVictory: Bool {
        if case .victory = self { return true }
        return false
    }
}

// MARK: - Drop-in demo / preview API

/// A ready-to-run demonstration surface for `ContentView` or an Xcode preview.
///
///     BattlePresentationDemoView()
///         .frame(height: 108)
///
/// Custom resources can be supplied without connecting the gameplay model:
///
///     BattlePresentationDemoView(
///         playerResource: "spr_agunimon_dtector",
///         enemyResource: "spr_duskmon_dtector"
///     )
struct BattlePresentationDemoView: View {
    @StateObject private var director = BattlePresentationDirector()

    private let player: BattlePresentationSprite
    private let enemy: BattlePresentationSprite

    init(
        playerResource: String = "spr_agumon_dtector",
        enemyResource: String = "spr_gazimon_dtector"
    ) {
        player = BattlePresentationSprite(
            resource: playerResource,
            idleFrames: [0, 1],
            attackFrames: [2, 3],
            hitFrames: [1, 0],
            victoryFrames: [0, 1],
            defeatFrames: [1, 0],
            framesPerSecond: 7,
            size: 48,
            accessibilityLabel: "Demo player"
        )
        enemy = BattlePresentationSprite(
            resource: enemyResource,
            idleFrames: [0, 1],
            attackFrames: [2, 3],
            hitFrames: [1, 0],
            victoryFrames: [0, 1],
            defeatFrames: [1, 0],
            framesPerSecond: 7,
            size: 48,
            mirrored: true,
            accessibilityLabel: "Demo enemy"
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            BattlePresentationStage(
                director: director,
                player: player,
                enemy: enemy
            )
            .frame(minHeight: 92)

            Button(director.isPlaying ? "PLAYING…" : "REPLAY FX") {
                director.play(.demo)
            }
            .disabled(director.isPlaying)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            guard !director.isPlaying else { return }
            director.play(.demo)
        }
    }
}
