import SwiftUI

// MARK: - Shared logical-pixel helpers

private struct ClassicCollectionAsset: View {
    let resource: String
    var frame = 0
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var scale: CGFloat
    var origin: CGPoint
    var mirrored = false
    var inverted = false
    var opacity = 1.0

    var body: some View {
        let asset = ClassicPixelAsset(resource: resource, frame: frame)
            .frame(width: width * scale, height: height * scale)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)

        Group {
            if inverted {
                asset.colorInvert()
            } else {
                asset
            }
        }
            .opacity(opacity)
            .position(
                x: origin.x + (x + width / 2) * scale,
                y: origin.y + (y + height / 2) * scale
            )
    }
}

private struct ClassicCollectionNumber: View {
    let value: Int
    var rightX: CGFloat
    var topY: CGFloat
    var scale: CGFloat
    var origin: CGPoint

    private var reversedDigits: [Int] {
        String(max(0, value))
            .compactMap(\.wholeNumberValue)
            .reversed()
    }

    var body: some View {
        ForEach(Array(reversedDigits.enumerated()), id: \.offset) {
            index,
            digit in
            ClassicCollectionAsset(
                resource: "spr_numbers",
                frame: digit,
                x: rightX - CGFloat(index) * 5,
                y: topY,
                width: 4,
                height: 5,
                scale: scale,
                origin: origin
            )
        }
        .accessibilityHidden(true)
    }
}

private struct ClassicCollectionMarquee: View {
    let text: String
    let time: TimeInterval
    var y: CGFloat
    var scale: CGFloat
    var origin: CGPoint

    private var glyphs: [Int?] {
        text.lowercased().compactMap { character -> Int?? in
            guard let scalar = character.unicodeScalars.first else {
                return nil
            }
            switch scalar.value {
            case 32:
                return .some(nil)
            case 97...122:
                return .some(Int(scalar.value - 97))
            case 48...57:
                return .some(Int(scalar.value - 48 + 26))
            default:
                return nil
            }
        }
    }

    private var startX: CGFloat {
        let width = max(1, glyphs.count * 6 + 30)
        let offset = Int(max(0, time) * 10) % width
        return CGFloat(30 - offset)
    }

    var body: some View {
        ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
            if let glyph {
                ClassicCollectionAsset(
                    resource: "spr_font_dtector",
                    frame: glyph,
                    x: startX + CGFloat(index * 6),
                    y: y,
                    width: 5,
                    height: 7,
                    scale: scale,
                    origin: origin
                )
            }
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private func classicCollectionSound(
    _ resource: String,
    game: GameModel
) {
    GameAudio.shared.play(
        resource,
        enabled: game.state.soundEnabled
    )
}

private func classicCollectionGeometry(
    _ size: CGSize
) -> (scale: CGFloat, origin: CGPoint) {
    let scale = min(size.width / 30, size.height / 32)
    return (
        scale,
        CGPoint(
            x: (size.width - 30 * scale) / 2,
            y: (size.height - 32 * scale) / 2
        )
    )
}

// MARK: - Map

struct ClassicMapView: View {
    @EnvironmentObject private var game: GameModel

    private enum Phase {
        case browsing
        case choosingArea
        case confirming
    }

    @State private var page = 0
    @State private var selectedArea = 0
    @State private var phase: Phase = .browsing
    @State private var appearedAt = Date()
    @State private var transitionFromPage: Int?
    @State private var transitionStartedAt: Date?
    @State private var transitionTask: Task<Void, Never>?

    private static let markerPositions: [CGPoint] = [
        CGPoint(x: 15, y: 20),
        CGPoint(x: 3, y: 26),
        CGPoint(x: 23, y: 26),
        CGPoint(x: 11, y: 6),
        CGPoint(x: 25, y: 8),
        CGPoint(x: 23, y: 18),
        CGPoint(x: 2, y: 12),
        CGPoint(x: 8, y: 2),
        CGPoint(x: 20, y: 9),
        CGPoint(x: 24, y: 26),
        CGPoint(x: 5, y: 23),
        CGPoint(x: 12, y: 17),
        CGPoint(x: 11, y: 17)
    ]

    private var isFinalMap: Bool {
        game.state.currentArea == 12
    }

    private var isTransitioning: Bool {
        transitionFromPage != nil
    }

    var body: some View {
        ClassicExpandedShell(
            drawsViewport: false,
            showsControls: !isTransitioning,
            leftEnabled: false,
            cancelEnabled: !isTransitioning,
            acceptEnabled: !isTransitioning,
            onStageTap: advanceWithDown,
            onLeft: {},
            onCancel: cancel,
            onAccept: accept
        ) {
            TimelineView(.animation(minimumInterval: 0.20)) { timeline in
                GeometryReader { geometry in
                    ZStack {
                        DetectorPalette.screen
                        mapStage(
                            at: timeline.date,
                            in: geometry.size
                        )
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digital World map")
        .accessibilityValue(mapAccessibilityValue)
        .accessibilityHint(
            "Tap right to advance, center to accept, hold to return"
        )
        .onAppear {
            appearedAt = Date()
            if isFinalMap {
                page = 4
                selectedArea = 12
            } else {
                page = max(0, min(3, game.state.currentArea / 3))
                selectedArea = game.state.currentArea
            }
        }
        .onDisappear {
            transitionTask?.cancel()
            transitionTask = nil
        }
    }

    @ViewBuilder
    private func mapStage(at date: Date, in size: CGSize) -> some View {
        let geometry = classicCollectionGeometry(size)
        let elapsed = max(0, date.timeIntervalSince(appearedAt))
        let pulse = Int(elapsed / (isFinalMap ? 0.25 : 0.20))
            .isMultiple(of: 2)

        if let transitionFromPage, let transitionStartedAt {
            drawMapTransition(
                from: transitionFromPage,
                elapsed: max(0, date.timeIntervalSince(transitionStartedAt)),
                scale: geometry.scale,
                origin: geometry.origin
            )
        } else if phase == .confirming {
            ClassicCollectionAsset(
                resource: "spr_change_map_dtector",
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )
            ClassicCollectionNumber(
                value: selectedDistance,
                rightX: 26,
                topY: 24,
                scale: geometry.scale,
                origin: geometry.origin
            )
        } else if isFinalMap {
            ClassicCollectionAsset(
                resource: "spr_map_5_dtector",
                frame: phase == .choosingArea ? 2 : 1,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )
            if pulse {
                drawMarker(
                    areaID: 12,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }
        } else {
            ClassicCollectionAsset(
                resource: "spr_map_dtector",
                frame: page,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )

            ForEach(pageAreas, id: \.id) { area in
                let cleared = game.state.areaCleared.indices.contains(area.id)
                    && game.state.areaCleared[area.id]
                let isCurrent = area.id == game.state.currentArea
                let isSelected = phase == .choosingArea
                    && area.id == selectedArea

                if cleared && !isCurrent && !isSelected {
                    drawMarker(
                        areaID: area.id,
                        frame: 0,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                }
                if (isCurrent || isSelected) && pulse {
                    drawMarker(
                        areaID: area.id,
                        frame: cleared ? 1 : 0,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                }
            }

            if phase == .choosingArea {
                ClassicCollectionAsset(
                    resource: "spr_area_dtector",
                    frame: selectedArea,
                    x: 0,
                    y: page == 1 || page == 2 ? 24 : 0,
                    width: 30,
                    height: 8,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }
        }
    }

    @ViewBuilder
    private func drawMapTransition(
        from page: Int,
        elapsed: TimeInterval,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        // The original advances one logical pixel every six 60-Hz ticks.
        let offset = CGFloat(Int(elapsed / 0.10))

        switch page {
        case 0:
            mapFrame(0, x: 0, y: -offset, scale: scale, origin: origin)
            mapFrame(1, x: 0, y: 32 - offset, scale: scale, origin: origin)
        case 1:
            mapFrame(1, x: -offset, y: 0, scale: scale, origin: origin)
            mapFrame(2, x: 30 - offset, y: 0, scale: scale, origin: origin)
        case 2:
            mapFrame(2, x: 0, y: offset, scale: scale, origin: origin)
            mapFrame(3, x: 0, y: -32 + offset, scale: scale, origin: origin)
        default:
            mapFrame(3, x: offset, y: 0, scale: scale, origin: origin)
            mapFrame(0, x: -30 + offset, y: 0, scale: scale, origin: origin)
        }
    }

    private func mapFrame(
        _ frame: Int,
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicCollectionAsset(
            resource: "spr_map_dtector",
            frame: frame,
            x: x,
            y: y,
            width: 30,
            height: 32,
            scale: scale,
            origin: origin
        )
    }

    @ViewBuilder
    private func drawMarker(
        areaID: Int,
        frame: Int = 0,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        if Self.markerPositions.indices.contains(areaID) {
            let point = Self.markerPositions[areaID]
            ClassicCollectionAsset(
                resource: "spr_map_cover_dtector",
                frame: frame,
                x: point.x,
                y: point.y,
                width: 4,
                height: 4,
                scale: scale,
                origin: origin
            )
        }
    }

    private var pageAreas: [AreaDefinition] {
        guard page >= 0, page < 4 else { return [] }
        return game.catalog.areas.filter {
            $0.id >= page * 3 && $0.id < page * 3 + 3
        }
    }

    private var selectedDistance: Int {
        guard let area = game.catalog.areas.first(
            where: { $0.id == selectedArea }
        ) else { return 0 }
        if selectedArea == game.state.currentArea {
            return game.state.distance
        }
        let cleared = game.state.areaCleared.indices.contains(selectedArea)
            && game.state.areaCleared[selectedArea]
        return cleared ? max(1, area.distance / 2) : area.distance
    }

    private var mapAccessibilityValue: String {
        switch phase {
        case .browsing:
            return isFinalMap ? "Final map" : "Map page \(page + 1)"
        case .choosingArea, .confirming:
            let name = game.catalog.areas.first(
                where: { $0.id == selectedArea }
            )?.name ?? "Area \(selectedArea + 1)"
            return "\(name), \(selectedDistance) steps"
        }
    }

    private func advanceWithDown() {
        switch phase {
        case .browsing:
            guard !isFinalMap else { return }
            playSelect()
            beginPageTransition()
        case .choosingArea:
            guard !isFinalMap else { return }
            let areas = pageAreas.map(\.id)
            guard let index = areas.firstIndex(of: selectedArea) else {
                selectedArea = areas.first ?? selectedArea
                return
            }
            selectedArea = areas[(index + 1) % areas.count]
            playSelect()
        case .confirming:
            // Down has no state transition on obj_change_map_dtector.
            playCancel()
        }
    }

    private func beginPageTransition() {
        guard transitionFromPage == nil else { return }
        let oldPage = page
        let nextPage = (oldPage + 1) % 4
        let duration = oldPage == 0 || oldPage == 2 ? 3.30 : 3.10

        transitionFromPage = oldPage
        transitionStartedAt = Date()
        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled,
                  transitionFromPage == oldPage else { return }
            page = nextPage
            selectedArea = nextPage * 3
            transitionFromPage = nil
            transitionStartedAt = nil
        }
    }

    private func cancel() {
        switch phase {
        case .browsing:
            playCancel()
            game.navigate(.mainMenu)
        case .choosingArea:
            playCancel()
            phase = .browsing
        case .confirming:
            playCancel()
            phase = .choosingArea
        }
    }

    private func accept() {
        switch phase {
        case .browsing:
            if isFinalMap {
                selectedArea = 12
            } else if game.state.currentArea / 3 == page {
                selectedArea = game.state.currentArea
            } else {
                selectedArea = page * 3
            }
            phase = .choosingArea
            playSelect()
        case .choosingArea:
            phase = .confirming
            playSelect()
        case .confirming:
            playSelect()
            game.selectArea(selectedArea)
            game.goHome()
        }
    }

    private func playSelect() {
        classicCollectionSound("sound_select", game: game)
    }

    private func playCancel() {
        classicCollectionSound("sound_cancel", game: game)
    }
}

// MARK: - Spirits

struct ClassicSpiritsView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selectedSpiritID = -1
    @State private var detailPage: Int?
    @State private var appearedAt = Date()

    private var obtainedSpiritIDs: [Int] {
        game.catalog.spirits.compactMap { spirit in
            guard game.state.spiritsObtained.indices.contains(spirit.id),
                  game.state.spiritsObtained[spirit.id] else { return nil }
            return spirit.id
        }
    }

    private var currentSpiritID: Int? {
        if obtainedSpiritIDs.contains(selectedSpiritID) {
            return selectedSpiritID
        }
        let preferred = game.state.currentCharacter * 2
        return obtainedSpiritIDs.first(where: { $0 >= preferred })
            ?? obtainedSpiritIDs.first
    }

    private var spiritDefinition: SpiritDefinition? {
        guard let currentSpiritID else { return nil }
        return game.catalog.spirits.first(where: { $0.id == currentSpiritID })
    }

    private var digimonDefinition: DigimonDefinition? {
        guard let spiritDefinition else { return nil }
        return game.catalog.digimon.first(
            where: { $0.id == spiritDefinition.digimonID }
        )
    }

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            cancelEnabled: true,
            acceptEnabled: currentSpiritID != nil,
            onStageTap: advanceWithDown,
            onLeft: {},
            onCancel: cancel,
            onAccept: accept
        ) {
            TimelineView(.animation(minimumInterval: 0.10)) {
                timeline in
                GeometryReader { geometry in
                    spiritsStage(
                        at: timeline.date,
                        in: geometry.size
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spirit database")
        .accessibilityValue(spiritAccessibilityValue)
        .accessibilityHint("Tap right to advance, center to select, hold to return")
        .onAppear {
            appearedAt = Date()
            selectedSpiritID = currentSpiritID ?? -1
        }
    }

    @ViewBuilder
    private func spiritsStage(at date: Date, in size: CGSize) -> some View {
        let geometry = classicCollectionGeometry(size)
        let elapsed = max(0, date.timeIntervalSince(appearedAt))

        if let detailPage, let digimonDefinition {
            let combatant = game.combatant(for: digimonDefinition.id)
            if detailPage == 0 {
                ClassicCollectionAsset(
                    resource: digimonDefinition.sprite,
                    frame: 0,
                    x: 3,
                    y: 8,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            } else {
                ClassicCollectionAsset(
                    resource: "spr_database_stats_dtector",
                    frame: detailPage - 1,
                    x: 0,
                    y: 0,
                    width: 30,
                    height: 32,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
                if detailPage == 1 {
                    ClassicCollectionNumber(
                        value: game.state.level,
                        rightX: 24,
                        topY: 9,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                    ClassicCollectionNumber(
                        value: combatant.maxHP,
                        rightX: 24,
                        topY: 17,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                    ClassicCollectionAsset(
                        resource: "spr_type_dtector",
                        frame: digimonDefinition.element,
                        x: 0,
                        y: 25,
                        width: 30,
                        height: 5,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                } else {
                    ClassicCollectionNumber(
                        value: combatant.energy,
                        rightX: 24,
                        topY: 9,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                    ClassicCollectionNumber(
                        value: combatant.crunch,
                        rightX: 24,
                        topY: 17,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                    ClassicCollectionNumber(
                        value: combatant.ability,
                        rightX: 24,
                        topY: 25,
                        scale: geometry.scale,
                        origin: geometry.origin
                    )
                }
            }

            ClassicCollectionMarquee(
                text: String(format: "%03d ", digimonDefinition.number)
                    + digimonDefinition.name,
                time: elapsed,
                y: 0,
                scale: geometry.scale,
                origin: geometry.origin
            )
        } else if let currentSpiritID {
            ClassicCollectionAsset(
                resource: "spr_sel_dtector",
                frame: 0,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )
            ClassicCollectionAsset(
                resource: "spr_spirits_dtector",
                frame: currentSpiritID,
                x: 3,
                y: 0,
                width: 24,
                height: 24,
                scale: geometry.scale,
                origin: geometry.origin
            )
            ClassicCollectionAsset(
                resource: "spr_type_dtector",
                frame: currentSpiritID / 2,
                x: 0,
                y: 25,
                width: 30,
                height: 5,
                scale: geometry.scale,
                origin: geometry.origin
            )
        } else {
            ClassicCollectionAsset(
                resource: "spr_sel_dtector",
                frame: 0,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )
        }
    }

    private var ownerIsInParty: Bool {
        guard let owner = spiritDefinition?.ownerCharacterID else {
            return false
        }
        return game.state.characterParty.indices.contains(owner)
            && game.state.characterParty[owner]
    }

    private var spiritAccessibilityValue: String {
        guard let digimonDefinition else { return "No obtained Spirit" }
        guard let detailPage else { return digimonDefinition.displayName }
        let combatant = game.combatant(for: digimonDefinition.id)
        switch detailPage {
        case 0:
            return digimonDefinition.displayName
        case 1:
            return "Level \(game.state.level), HP \(combatant.maxHP)"
        default:
            return "Energy \(combatant.energy), Crunch \(combatant.crunch), Ability \(combatant.ability)"
        }
    }

    private func advanceWithDown() {
        if detailPage != nil {
            advanceDetail()
            return
        }
        guard let currentSpiritID,
              let index = obtainedSpiritIDs.firstIndex(of: currentSpiritID)
        else {
            playCancel()
            return
        }
        selectedSpiritID = obtainedSpiritIDs[
            (index + 1) % obtainedSpiritIDs.count
        ]
        playSelect()
    }

    private func cancel() {
        if let detailPage {
            playCancel()
            if detailPage == 0 {
                self.detailPage = nil
            } else {
                self.detailPage = 0
            }
        } else {
            playCancel()
            game.navigate(.mainMenu)
        }
    }

    private func accept() {
        guard currentSpiritID != nil else {
            playCancel()
            return
        }
        if detailPage == nil {
            detailPage = 0
            appearedAt = Date()
            playSelect()
        } else {
            advanceDetail()
        }
    }

    private func advanceDetail() {
        guard ownerIsInParty else {
            playCancel()
            return
        }
        switch detailPage {
        case 0:
            detailPage = 1
        case 1:
            detailPage = 2
        default:
            detailPage = 1
        }
        playSelect()
    }

    private func playSelect() {
        classicCollectionSound("sound_select", game: game)
    }

    private func playCancel() {
        classicCollectionSound("sound_cancel", game: game)
    }
}

// MARK: - Camp

struct ClassicCampView: View {
    @EnvironmentObject private var game: GameModel
    @State private var appearedAt = Date()
    @State private var leavingAt: Date?
    @State private var campReady = false
    @State private var readyTask: Task<Void, Never>?
    @State private var finishTask: Task<Void, Never>?
    @State private var didRecover = false

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: isCampReady,
            cancelEnabled: isCampReady,
            acceptEnabled: isCampReady,
            onStageTap: beginLeavingIfReady,
            onLeft: beginLeavingIfReady,
            onCancel: beginLeavingIfReady,
            onAccept: beginLeavingIfReady
        ) {
            TimelineView(.animation(minimumInterval: 0.10)) {
                timeline in
                GeometryReader { geometry in
                    campStage(
                        at: timeline.date,
                        in: geometry.size
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("D-Tector camp recovery")
        .accessibilityValue(campAccessibilityValue)
        .onAppear {
            appearedAt = Date()
            campReady = false
            readyTask?.cancel()
            readyTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_400_000_000)
                guard !Task.isCancelled, leavingAt == nil else { return }
                campReady = true
            }
            if !didRecover {
                didRecover = true
                game.recoverAtCamp()
            }
        }
        .onDisappear {
            readyTask?.cancel()
            readyTask = nil
            finishTask?.cancel()
            finishTask = nil
        }
    }

    @ViewBuilder
    private func campStage(at date: Date, in size: CGSize) -> some View {
        let geometry = classicCollectionGeometry(size)
        let frame = Int(
            date.timeIntervalSinceReferenceDate / 0.10
        ).isMultiple(of: 2) ? 0 : 1

        if let leavingAt {
            let elapsed = max(0, date.timeIntervalSince(leavingAt))
            if elapsed < 2.7 {
                ClassicCollectionAsset(
                    resource: "spr_camp_dtector",
                    frame: 0,
                    x: 3 - CGFloat(elapsed * 10),
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            } else if elapsed < 5.4 {
                let progress = CGFloat((elapsed - 2.7) * 10)
                ClassicCollectionAsset(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: frame,
                    x: 3 - 27 + progress,
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin,
                    mirrored: true
                )
            } else {
                ClassicCollectionAsset(
                    resource: game.currentCharacter.sprite,
                    frame: Int(elapsed / 0.50).isMultiple(of: 2) ? 0 : 1,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }
        } else {
            let elapsed = max(0, date.timeIntervalSince(appearedAt))
            if elapsed < 2.7 {
                ClassicCollectionAsset(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: frame,
                    x: 3 - CGFloat(elapsed * 10),
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            } else if elapsed < 5.4 {
                let progress = CGFloat((elapsed - 2.7) * 10)
                ClassicCollectionAsset(
                    resource: "spr_camp_dtector",
                    frame: 0,
                    x: 3 - 27 + progress,
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            } else {
                ClassicCollectionAsset(
                    resource: "spr_camp_dtector",
                    frame: Int(elapsed / 0.50).isMultiple(of: 2) ? 0 : 1,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }
        }
    }

    private var isCampReady: Bool {
        campReady && leavingAt == nil
    }

    private var campAccessibilityValue: String {
        if leavingAt != nil { return "Leaving camp" }
        return isCampReady ? "Recovery complete" : "Recovering"
    }

    private func beginLeavingIfReady() {
        guard isCampReady, leavingAt == nil else { return }
        campReady = false
        leavingAt = Date()
        finishTask?.cancel()
        finishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_900_000_000)
            guard !Task.isCancelled else { return }
            classicCollectionSound(
                "sound_char_happy_long",
                game: game
            )
            game.goHome()
        }
    }
}

// MARK: - Database

private struct ClassicDatabaseChange {
    let oldID: Int
    let newID: Int
    let slot: Int
    let startedAt: Date
}

struct ClassicDatabaseView: View {
    @EnvironmentObject private var game: GameModel

    private enum Phase {
        case categories
        case list
        case detail
        case docks
        case dockConfirmation
        case changing
    }

    private let categoryTypes = [
        "rookie",
        "champion",
        "ultimate",
        "mega",
        "boss",
        "ancient"
    ]

    @State private var phase: Phase = .categories
    @State private var category = 0
    @State private var listIndex = 0
    @State private var detailPage = 0
    @State private var dockSlot = 0
    @State private var appearedAt = Date()
    @State private var change: ClassicDatabaseChange?
    @State private var changeTask: Task<Void, Never>?

    private var categoryDigimon: [DigimonDefinition] {
        guard categoryTypes.indices.contains(category) else { return [] }
        let type = categoryTypes[category]
        return game.catalog.digimon.filter { digimon in
            digimon.type == type
                && game.state.digimonUnlocked.indices.contains(digimon.id)
                && game.state.digimonUnlocked[digimon.id]
        }
    }

    private var selectedDigimon: DigimonDefinition? {
        guard categoryDigimon.indices.contains(listIndex) else { return nil }
        return categoryDigimon[listIndex]
    }

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            cancelEnabled: phase != .changing,
            acceptEnabled: phase != .changing,
            onStageTap: advanceWithDown,
            onLeft: {},
            onCancel: cancel,
            onAccept: accept
        ) {
            TimelineView(.animation(minimumInterval: 0.05)) {
                timeline in
                GeometryReader { geometry in
                    databaseStage(
                        at: timeline.date,
                        in: geometry.size
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digimon database")
        .accessibilityValue(databaseAccessibilityValue)
        .accessibilityHint("Tap right to advance, center to select, hold to return")
        .onAppear {
            appearedAt = Date()
        }
        .onDisappear {
            changeTask?.cancel()
            changeTask = nil
        }
    }

    @ViewBuilder
    private func databaseStage(
        at date: Date,
        in size: CGSize
    ) -> some View {
        let geometry = classicCollectionGeometry(size)
        let elapsed = max(0, date.timeIntervalSince(appearedAt))

        switch phase {
        case .categories:
            ClassicCollectionAsset(
                resource: "spr_database_dtector",
                frame: category,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )

        case .list:
            if let selectedDigimon {
                let docked = game.state.docks.contains(selectedDigimon.id)
                ClassicCollectionAsset(
                    resource: "spr_sel_dtector",
                    frame: 2,
                    x: 0,
                    y: 0,
                    width: 30,
                    height: 32,
                    scale: geometry.scale,
                    origin: geometry.origin,
                    inverted: docked
                )
                ClassicCollectionAsset(
                    resource: selectedDigimon.sprite,
                    frame: 0,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24,
                    scale: geometry.scale,
                    origin: geometry.origin,
                    inverted: docked
                )
            }

        case .detail:
            if let selectedDigimon {
                drawDatabaseDetail(
                    selectedDigimon,
                    page: detailPage,
                    elapsed: elapsed,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }

        case .docks:
            ClassicCollectionAsset(
                resource: "spr_docks_dtector",
                frame: dockSlot,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: geometry.scale,
                origin: geometry.origin
            )

        case .dockConfirmation:
            let existingID = game.state.docks.indices.contains(dockSlot)
                ? game.state.docks[dockSlot]
                : -1
            let existing = game.catalog.digimon.first(
                where: { $0.id == existingID }
            )
            ClassicCollectionAsset(
                resource: existing?.sprite ?? "spr_empty_dtector",
                frame: 0,
                x: 3,
                y: 8,
                width: 24,
                height: 24,
                scale: geometry.scale,
                origin: geometry.origin
            )
            ClassicCollectionMarquee(
                text: "DIGIMON REPLACEMENT",
                time: elapsed,
                y: 0,
                scale: geometry.scale,
                origin: geometry.origin
            )

        case .changing:
            if let change {
                drawDockChange(
                    change,
                    at: date,
                    scale: geometry.scale,
                    origin: geometry.origin
                )
            }
        }
    }

    @ViewBuilder
    private func drawDatabaseDetail(
        _ digimon: DigimonDefinition,
        page: Int,
        elapsed: TimeInterval,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        ClassicCollectionAsset(
            resource: "spr_database_stats_dtector",
            frame: page,
            x: 0,
            y: 0,
            width: 30,
            height: 32,
            scale: scale,
            origin: origin
        )
        if page == 0 {
            if digimon.level == -4 {
                ClassicCollectionAsset(
                    resource: "spr_noone_level_dtector",
                    x: 19,
                    y: 9,
                    width: 10,
                    height: 5,
                    scale: scale,
                    origin: origin
                )
            } else {
                ClassicCollectionNumber(
                    value: digimon.level,
                    rightX: 24,
                    topY: 9,
                    scale: scale,
                    origin: origin
                )
            }
            ClassicCollectionNumber(
                value: digimon.hp,
                rightX: 24,
                topY: 17,
                scale: scale,
                origin: origin
            )
            ClassicCollectionAsset(
                resource: "spr_type_dtector",
                frame: digimon.element,
                x: 0,
                y: 25,
                width: 30,
                height: 5,
                scale: scale,
                origin: origin
            )
        } else {
            ClassicCollectionNumber(
                value: digimon.energy,
                rightX: 24,
                topY: 9,
                scale: scale,
                origin: origin
            )
            ClassicCollectionNumber(
                value: digimon.crunch,
                rightX: 24,
                topY: 17,
                scale: scale,
                origin: origin
            )
            ClassicCollectionNumber(
                value: digimon.ability,
                rightX: 24,
                topY: 25,
                scale: scale,
                origin: origin
            )
        }
        ClassicCollectionMarquee(
            text: String(format: "%03d ", digimon.number) + digimon.name,
            time: elapsed,
            y: 0,
            scale: scale,
            origin: origin
        )
    }

    @ViewBuilder
    private func drawDockChange(
        _ change: ClassicDatabaseChange,
        at date: Date,
        scale: CGFloat,
        origin: CGPoint
    ) -> some View {
        let elapsed = max(0, date.timeIntervalSince(change.startedAt))
        let oldResource = game.catalog.digimon.first(
            where: { $0.id == change.oldID }
        )?.sprite ?? "spr_empty_dtector"
        let newResource = game.catalog.digimon.first(
            where: { $0.id == change.newID }
        )?.sprite ?? "spr_empty_dtector"

        if elapsed < 1.55 {
            let offset = CGFloat(elapsed / 1.55 * 32)
            ClassicCollectionAsset(
                resource: "spr_stats_menu_dtector",
                frame: change.slot + 3,
                x: 0,
                y: -offset,
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
            ClassicCollectionAsset(
                resource: oldResource,
                x: 3,
                y: 8 - offset,
                width: 24,
                height: 24,
                scale: scale,
                origin: origin
            )
        } else if elapsed < 3.60 {
            let offset = CGFloat((elapsed - 1.55) / 2.05 * 32)
            ClassicCollectionAsset(
                resource: "spr_stats_menu_dtector",
                frame: change.slot + 3,
                x: 0,
                y: -32 + offset,
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
            ClassicCollectionAsset(
                resource: newResource,
                x: 3,
                y: -24 + offset,
                width: 24,
                height: 24,
                scale: scale,
                origin: origin
            )
        } else {
            ClassicCollectionAsset(
                resource: "spr_stats_menu_dtector",
                frame: change.slot + 3,
                x: 0,
                y: 0,
                width: 30,
                height: 32,
                scale: scale,
                origin: origin
            )
            if Int((elapsed - 3.60) / 0.25).isMultiple(of: 2) {
                ClassicCollectionAsset(
                    resource: newResource,
                    frame: elapsed >= 4.35 ? 2 : 0,
                    x: 3,
                    y: 8,
                    width: 24,
                    height: 24,
                    scale: scale,
                    origin: origin
                )
            }
        }
    }

    private var databaseAccessibilityValue: String {
        switch phase {
        case .categories:
            return categoryTypes[category].uppercased()
        case .list:
            return selectedDigimon?.displayName ?? "Empty category"
        case .detail:
            guard let selectedDigimon else { return "No Digimon" }
            return detailPage == 0
                ? "\(selectedDigimon.displayName), level \(selectedDigimon.level), HP \(selectedDigimon.hp)"
                : "\(selectedDigimon.displayName), Energy \(selectedDigimon.energy), Crunch \(selectedDigimon.crunch), Ability \(selectedDigimon.ability)"
        case .docks:
            return "Dock \(dockSlot + 1)"
        case .dockConfirmation:
            return "Replace Dock \(dockSlot + 1)"
        case .changing:
            return "Replacing Digimon"
        }
    }

    private func advanceWithDown() {
        switch phase {
        case .categories:
            category = (category + 1) % categoryTypes.count
            listIndex = 0
            playSelect()
        case .list:
            guard !categoryDigimon.isEmpty else {
                playCancel()
                return
            }
            listIndex = (listIndex + 1) % categoryDigimon.count
            playSelect()
        case .detail:
            detailPage = (detailPage + 1) % 2
            appearedAt = Date()
            playSelect()
        case .docks, .dockConfirmation:
            dockSlot = (dockSlot + 1) % 4
            playSelect()
        case .changing:
            break
        }
    }

    private func cancel() {
        switch phase {
        case .categories:
            playCancel()
            game.navigate(.extraMenu)
        case .list:
            playCancel()
            phase = .categories
        case .detail:
            playCancel()
            phase = .list
        case .docks:
            playCancel()
            phase = .detail
        case .dockConfirmation:
            phase = .docks
        case .changing:
            break
        }
    }

    private func accept() {
        switch phase {
        case .categories:
            guard !categoryDigimon.isEmpty else {
                playCancel()
                return
            }
            listIndex = min(listIndex, categoryDigimon.count - 1)
            phase = .list
            playSelect()
        case .list:
            guard selectedDigimon != nil else {
                playCancel()
                return
            }
            detailPage = 0
            appearedAt = Date()
            phase = .detail
            playSelect()
        case .detail:
            guard let selectedDigimon,
                  selectedDigimon.level != -4,
                  !game.state.docks.contains(selectedDigimon.id)
            else {
                playCancel()
                return
            }
            dockSlot = 0
            phase = .docks
            playSelect()
        case .docks:
            phase = .dockConfirmation
            appearedAt = Date()
        case .dockConfirmation:
            replaceSelectedDock()
        case .changing:
            break
        }
    }

    private func replaceSelectedDock() {
        guard let selectedDigimon,
              game.state.docks.indices.contains(dockSlot)
        else { return }

        let oldID = game.state.docks[dockSlot]
        let replacement = ClassicDatabaseChange(
            oldID: oldID,
            newID: selectedDigimon.id,
            slot: dockSlot,
            startedAt: Date()
        )

        var attempts = game.dockCandidates.count + 2
        while game.state.docks[dockSlot] != selectedDigimon.id,
              attempts > 0 {
            game.cycleDock(dockSlot)
            attempts -= 1
        }
        guard game.state.docks[dockSlot] == selectedDigimon.id else {
            playCancel()
            phase = .docks
            return
        }

        change = replacement
        phase = .changing
        classicCollectionSound(
            "sound_change_dock_dtector",
            game: game
        )
        changeTask?.cancel()
        changeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_700_000_000)
            guard !Task.isCancelled else { return }
            game.navigate(.extraMenu)
        }
    }

    private func playSelect() {
        classicCollectionSound("sound_select", game: game)
    }

    private func playCancel() {
        classicCollectionSound("sound_cancel", game: game)
    }
}

// MARK: - Digital TV

struct ClassicTVView: View {
    @EnvironmentObject private var game: GameModel
    @State private var idleStartedAt = Date()
    @State private var scanStartedAt: Date?
    @State private var completionTask: Task<Void, Never>?

    private var isScanning: Bool {
        scanStartedAt != nil
    }

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: !isScanning,
            cancelEnabled: !isScanning,
            acceptEnabled: false,
            // vk_left starts reception in the original.
            onLeft: beginReception,
            // vk_up leaves only while the TV is idle/error.
            onCancel: cancel,
            onAccept: {}
        ) {
            TimelineView(.animation(minimumInterval: 0.05)) {
                timeline in
                GeometryReader { geometry in
                    tvStage(
                        at: timeline.date,
                        in: geometry.size
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digital TV")
        .accessibilityValue(isScanning ? "Receiving signal" : "Ready")
        .onAppear {
            idleStartedAt = Date()
        }
        .onDisappear {
            completionTask?.cancel()
            completionTask = nil
            scanStartedAt = nil
        }
    }

    @ViewBuilder
    private func tvStage(at date: Date, in size: CGSize) -> some View {
        let geometry = classicCollectionGeometry(size)
        if let scanStartedAt {
            let elapsed = max(0, date.timeIntervalSince(scanStartedAt))
            let counter = elapsed < 1
                ? 0
                : min(256, Int((elapsed - 1) / 0.05))

            if counter < 32 {
                tvFrame(
                    4,
                    y: CGFloat(counter),
                    geometry: geometry
                )
            }
            if counter < 64 {
                tvFrame(
                    5,
                    y: CGFloat(-32 + counter),
                    geometry: geometry
                )
            }
            if counter < 96 {
                tvFrame(
                    4,
                    y: CGFloat(-64 + counter),
                    geometry: geometry
                )
            }
            if counter < 128 {
                tvFrame(
                    5,
                    y: CGFloat(-96 + counter),
                    geometry: geometry
                )
            }
            if counter < 224 {
                tvFrame(
                    4,
                    y: CGFloat(-128 + counter),
                    geometry: geometry
                )
            }
            if counter < 256 {
                tvFrame(
                    6,
                    y: CGFloat(-160 + counter),
                    geometry: geometry
                )
            }
            if counter < 288 {
                tvFrame(
                    7,
                    y: CGFloat(-192 + counter),
                    geometry: geometry
                )
            }
            if counter < 320 {
                tvFrame(
                    6,
                    x: 0,
                    y: CGFloat(-192 + counter),
                    mirrored: true,
                    geometry: geometry
                )
            }
            if counter < 352 {
                tvFrame(
                    4,
                    y: CGFloat(-256 + counter),
                    geometry: geometry
                )
            }
            if counter == 0 {
                tvFrame(3, y: 0, geometry: geometry)
            }
        } else {
            let elapsed = max(0, date.timeIntervalSince(idleStartedAt))
            tvFrame(
                Int(elapsed / 0.50).isMultiple(of: 2) ? 1 : 0,
                y: 0,
                geometry: geometry
            )
        }
    }

    @ViewBuilder
    private func tvFrame(
        _ frame: Int,
        x: CGFloat = 0,
        y: CGFloat,
        mirrored: Bool = false,
        geometry: (scale: CGFloat, origin: CGPoint)
    ) -> some View {
        ClassicCollectionAsset(
            resource: "spr_tv_dtector",
            frame: frame,
            x: x,
            y: y,
            width: 30,
            height: 32,
            scale: geometry.scale,
            origin: geometry.origin,
            mirrored: mirrored
        )
    }

    private func beginReception() {
        guard scanStartedAt == nil else { return }
        scanStartedAt = Date()
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 13_850_000_000)
            guard !Task.isCancelled, game.screen == .tv else { return }
            scanStartedAt = nil
            idleStartedAt = Date()
            game.activateTV()
        }
    }

    private func cancel() {
        guard !isScanning else { return }
        game.navigate(.extraMenu)
    }
}
