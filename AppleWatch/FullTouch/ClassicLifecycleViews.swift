import SwiftUI

// MARK: - Shared 30×32 presentation

private struct ClassicLifecycleShell<Stage: View>: View {
    @Environment(\.displayScale) private var displayScale

    let showGrid: Bool
    let leftEnabled: Bool
    let cancelEnabled: Bool
    let acceptEnabled: Bool
    let onLeft: () -> Void
    let onCancel: () -> Void
    let onAccept: () -> Void
    @ViewBuilder let stage: Stage

    var body: some View {
        GeometryReader { geometry in
            let fittingBounds = ClassicLCDGeometry.fullscreenFittingBounds(
                geometry.size
            )
            let fullscreenBounds = CGSize(
                width: fittingBounds.width
                    * ClassicLCDGeometry.lifecycleFullscreenScale,
                height: fittingBounds.height
                    * ClassicLCDGeometry.lifecycleFullscreenScale
            )
            let stageSize = ClassicLCDGeometry.pixelAlignedSize(
                fitting: fullscreenBounds,
                displayScale: displayScale
            )
            let stageCenter = CGPoint(
                x: fullscreenBounds.width / 2,
                y: fullscreenBounds.height / 2
            )

            ZStack {
                ClassicLCDViewport(
                    content: {
                        ClassicLogicalCanvas {
                            stage
                        }
                    },
                    showGrid: showGrid
                )
                .frame(width: stageSize.width, height: stageSize.height)
                .position(stageCenter)

                ClassicDetectorTouchZones(
                    leftEnabled: leftEnabled,
                    centerEnabled: acceptEnabled,
                    rightEnabled: acceptEnabled,
                    cancelEnabled: cancelEnabled,
                    onLeft: onLeft,
                    onCenter: onAccept,
                    onRight: onAccept,
                    onCancel: onCancel
                )
                .frame(
                    width: fullscreenBounds.width,
                    height: fullscreenBounds.height
                )
                .position(stageCenter)
            }
            .frame(
                width: fullscreenBounds.width,
                height: fullscreenBounds.height
            )
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
            .ignoresSafeArea()
        }
    }
}

private struct ClassicLogicalCanvas<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / 30,
                geometry.size.height / 32
            )

            ZStack(alignment: .topLeading) {
                content
            }
            .frame(width: 30, height: 32)
            .scaleEffect(scale)
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
        }
    }
}

private struct ClassicLifecycleSprite: View {
    let resource: String
    var frame = 0
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 30
    var height: CGFloat = 32
    var mirrored = false

    var body: some View {
        ClassicPixelAsset(resource: resource, frame: frame)
            .frame(width: width, height: height)
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            .position(
                x: x + width / 2,
                y: y + height / 2
            )
    }
}

private struct ClassicLifecycleGlyph: View {
    let frame: Int
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        ClassicLifecycleSprite(
            resource: "spr_font_dtector",
            frame: frame,
            x: x,
            y: y,
            width: 5,
            height: 7
        )
    }
}

// MARK: - Original boot handoff

struct ClassicBootView: View {
    @EnvironmentObject private var game: GameModel
    @State private var handoffStartedAt: Date?
    @State private var handoffTask: Task<Void, Never>?

    var body: some View {
        let idle = handoffStartedAt == nil

        ClassicLifecycleShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: idle,
            cancelEnabled: idle,
            acceptEnabled: idle,
            onLeft: startHandoff,
            onCancel: startHandoff,
            onAccept: startHandoff
        ) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) {
                timeline in
                if let handoffStartedAt {
                    bootHandoffScene(
                        elapsed: max(
                            0,
                            timeline.date.timeIntervalSince(handoffStartedAt)
                        )
                    )
                } else {
                    bootScanScene(at: timeline.date)
                }
            }
        }
        .accessibilityLabel("D-Tector start screen")
        .accessibilityHint(idle ? "Press any detector button to start" : "")
        .onDisappear {
            handoffTask?.cancel()
            handoffTask = nil
        }
    }

    @ViewBuilder
    private func bootScanScene(at date: Date) -> some View {
        let counter = Int(
            date.timeIntervalSinceReferenceDate * 20
        ) % 64

        ZStack(alignment: .topLeading) {
            // Extracted frame 4 is a fully opaque black 30×32 plate. The
            // original renderer treats that plate as the LCD clear layer;
            // drawing it literally in SwiftUI would hide the moving scan.
            // ClassicLCDViewport already supplies the LCD clear color.
            ClassicLifecycleSprite(
                resource: "spr_scan_dtector",
                frame: 3,
                y: CGFloat(counter - 32)
            )
        }
    }

    @ViewBuilder
    private func bootHandoffScene(elapsed: TimeInterval) -> some View {
        if elapsed < 1.25 {
            let counter = min(4, Int(elapsed / 0.25))
            if !counter.isMultiple(of: 2) {
                ClassicLifecycleSprite(
                    resource: "spr_summon_dtector",
                    frame: 0
                )
            }
        } else if elapsed < 2.50 {
            let counter = min(4, Int((elapsed - 1.25) / 0.25))
            if !counter.isMultiple(of: 2) {
                ClassicLifecycleSprite(
                    resource: "spr_catch_dtector",
                    frame: 0
                )
            }
        } else {
            let counter = min(32, Int((elapsed - 2.50) / 0.05))
            ClassicLifecycleSprite(
                resource: game.currentCharacter.sprite,
                x: 3,
                y: 4,
                width: 24,
                height: 24
            )
            // The source requests catch subimage 3. The extracted two-frame
            // sprite wraps that index to subimage 1 in GameMaker.
            ClassicLifecycleSprite(
                resource: "spr_catch_dtector",
                frame: 1,
                y: CGFloat(-counter)
            )
        }
    }

    private func startHandoff() {
        guard handoffStartedAt == nil else { return }
        handoffStartedAt = Date()
        handoffTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_150_000_000)
            guard !Task.isCancelled, game.screen == .boot else { return }
            game.navigate(.characterSelect)
        }
    }
}

// MARK: - Original character and five-glyph name selection

struct ClassicCharacterSelectView: View {
    @EnvironmentObject private var game: GameModel

    private enum Phase {
        case selection
        case characterIntro
        case nameEntry
        case nameConfirmation
    }

    @State private var phase = Phase.selection
    @State private var selectedCharacterID = 0
    @State private var introStartedAt = Date()
    @State private var nameEntryStartedAt = Date()
    @State private var selectedGlyph = 0
    @State private var enteredGlyphs: [Int?] = Array(
        repeating: nil,
        count: 5
    )
    @State private var currentGlyphSlot = 0
    @State private var introTask: Task<Void, Never>?

    private var availableCharacters: [CharacterDefinition] {
        Array(
            game.catalog.characters.prefix(game.state.newGamePlus ? 6 : 5)
        )
    }

    private var selectedCharacter: CharacterDefinition {
        availableCharacters.first {
            $0.id == selectedCharacterID
        } ?? availableCharacters.first ?? game.currentCharacter
    }

    var body: some View {
        ClassicLifecycleShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: phase != .characterIntro,
            cancelEnabled: phase != .characterIntro,
            acceptEnabled: phase != .characterIntro,
            onLeft: leftPressed,
            onCancel: cancelPressed,
            onAccept: acceptPressed
        ) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) {
                timeline in
                switch phase {
                case .selection:
                    characterSelectionScene
                case .characterIntro:
                    characterIntroScene(
                        elapsed: max(
                            0,
                            timeline.date.timeIntervalSince(introStartedAt)
                        )
                    )
                case .nameEntry:
                    nameEntryScene(
                        elapsed: max(
                            0,
                            timeline.date.timeIntervalSince(nameEntryStartedAt)
                        )
                    )
                case .nameConfirmation:
                    nameConfirmationScene
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            let permitted = availableCharacters.map(\.id)
            selectedCharacterID = permitted.contains(
                game.state.currentCharacter
            )
                ? game.state.currentCharacter
                : (permitted.first ?? 0)
        }
        .onDisappear {
            introTask?.cancel()
            introTask = nil
            GameAudio.shared.stop()
        }
    }

    private var characterSelectionScene: some View {
        ZStack(alignment: .topLeading) {
            ClassicLifecycleSprite(
                resource: "spr_sel_dtector",
                frame: 1
            )
            ClassicLifecycleSprite(
                resource: selectedCharacter.sprite,
                x: 3,
                y: 4,
                width: 24,
                height: 24
            )
        }
    }

    @ViewBuilder
    private func characterIntroScene(
        elapsed: TimeInterval
    ) -> some View {
        if elapsed < 2.80 {
            let counter = min(27, Int(elapsed / 0.10))
            ClassicLifecycleSprite(
                resource: selectedCharacter.sprite,
                x: CGFloat(30 - counter),
                y: 4,
                width: 24,
                height: 24
            )
        } else {
            let counter = elapsed < 6.80
                ? min(3, Int((elapsed - 2.80) / 1.0))
                : 0

            if counter.isMultiple(of: 2) {
                ClassicLifecycleSprite(
                    resource: "\(selectedCharacter.sprite)_happy",
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_happy",
                    x: 23,
                    width: 8,
                    height: 8
                )
                ClassicLifecycleSprite(
                    resource: "spr_happy",
                    width: 8,
                    height: 8
                )
            } else {
                ClassicLifecycleSprite(
                    resource: selectedCharacter.sprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            }
        }
    }

    private func nameEntryScene(
        elapsed: TimeInterval
    ) -> some View {
        let counter = Int(elapsed / 0.10)
        let titleFrames = [13, 0, 12, 4, -1, 4, 13, 19, 17, 24]
        let titleWidth = titleFrames.count * 6 + 30
        let titleOffset = counter % titleWidth

        return ZStack(alignment: .topLeading) {
            ClassicLifecycleSprite(
                resource: "spr_text_sel_dtector",
                frame: 0
            )
            ClassicLifecycleGlyph(
                frame: selectedGlyph,
                x: 12,
                y: 8
            )

            ForEach(Array(titleFrames.enumerated()), id: \.offset) {
                index,
                frame in
                if frame >= 0 {
                    ClassicLifecycleGlyph(
                        frame: frame,
                        x: CGFloat(30 - titleOffset + index * 6),
                        y: 0
                    )
                }
            }

            enteredNameSprites

            ForEach(0..<5, id: \.self) { index in
                if index != currentGlyphSlot || (counter % 4) < 2 {
                    ClassicLifecycleSprite(
                        resource: "spr_sel_letter_dtector",
                        x: CGFloat(index * 6),
                        y: 25,
                        width: 5,
                        height: 7
                    )
                }
            }
        }
    }

    private var nameConfirmationScene: some View {
        ZStack(alignment: .topLeading) {
            ClassicLifecycleSprite(
                resource: "spr_ok_dtector",
                x: 0,
                y: 8,
                width: 30,
                height: 8
            )
            enteredNameSprites
            ForEach(0..<5, id: \.self) { index in
                ClassicLifecycleSprite(
                    resource: "spr_sel_letter_dtector",
                    x: CGFloat(index * 6),
                    y: 25,
                    width: 5,
                    height: 7
                )
            }
        }
    }

    private var enteredNameSprites: some View {
        ForEach(0..<5, id: \.self) { index in
            if let frame = enteredGlyphs[index] {
                ClassicLifecycleGlyph(
                    frame: frame,
                    x: CGFloat(index * 6),
                    y: 17
                )
            }
        }
    }

    private var accessibilityLabel: String {
        switch phase {
        case .selection:
            "Select character, \(selectedCharacter.name)"
        case .characterIntro:
            "\(selectedCharacter.name) selected"
        case .nameEntry:
            "Name entry, glyph \(selectedGlyph + 1) of 38, position \(currentGlyphSlot + 1) of 5"
        case .nameConfirmation:
            "Confirm name \(composedName)"
        }
    }

    private func leftPressed() {
        switch phase {
        case .selection:
            cycleCharacter()
        case .characterIntro:
            break
        case .nameEntry:
            selectedGlyph = (selectedGlyph + 1) % 38
            GameAudio.shared.play(
                "sound_select",
                enabled: game.state.soundEnabled
            )
        case .nameConfirmation:
            currentGlyphSlot = 4
            phase = .nameEntry
            nameEntryStartedAt = Date()
            GameAudio.shared.play(
                "sound_select",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func cancelPressed() {
        switch phase {
        case .selection:
            game.selectCharacter(0)
            game.navigate(.boot)

        case .characterIntro:
            break

        case .nameEntry:
            if currentGlyphSlot > 0 {
                currentGlyphSlot -= 1
                enteredGlyphs[currentGlyphSlot] = nil
            } else {
                phase = .selection
            }
            GameAudio.shared.play(
                "sound_cancel",
                enabled: game.state.soundEnabled
            )

        case .nameConfirmation:
            currentGlyphSlot = 4
            phase = .nameEntry
            nameEntryStartedAt = Date()
            GameAudio.shared.play(
                "sound_cancel",
                enabled: game.state.soundEnabled
            )
        }
    }

    private func acceptPressed() {
        switch phase {
        case .selection:
            startCharacterIntro()
        case .characterIntro:
            break
        case .nameEntry:
            acceptGlyph()
        case .nameConfirmation:
            GameAudio.shared.play(
                "sound_select",
                enabled: game.state.soundEnabled
            )
            game.beginNewGame(
                characterID: selectedCharacterID,
                playerName: composedName
            )
        }
    }

    private func cycleCharacter() {
        guard !availableCharacters.isEmpty else { return }
        let currentIndex = availableCharacters.firstIndex {
            $0.id == selectedCharacterID
        } ?? 0
        let next = availableCharacters[
            (currentIndex + 1) % availableCharacters.count
        ]
        selectedCharacterID = next.id
        game.selectCharacter(next.id)
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )
    }

    private func startCharacterIntro() {
        guard phase == .selection else { return }
        phase = .characterIntro
        introStartedAt = Date()
        introTask?.cancel()
        introTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, phase == .characterIntro else { return }
            GameAudio.shared.play(
                "sound_char_happy_long",
                enabled: game.state.soundEnabled
            )
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, phase == .characterIntro else { return }
            phase = .nameEntry
            nameEntryStartedAt = Date()
        }
    }

    private func acceptGlyph() {
        guard enteredGlyphs.indices.contains(currentGlyphSlot) else {
            phase = .nameConfirmation
            return
        }

        if selectedGlyph == 36 {
            if currentGlyphSlot > 0 {
                currentGlyphSlot -= 1
                enteredGlyphs[currentGlyphSlot] = nil
                GameAudio.shared.play(
                    "sound_select",
                    enabled: game.state.soundEnabled
                )
            } else {
                GameAudio.shared.play(
                    "sound_cancel",
                    enabled: game.state.soundEnabled
                )
            }
            return
        }

        if selectedGlyph != 37 {
            enteredGlyphs[currentGlyphSlot] = selectedGlyph
        }
        currentGlyphSlot += 1
        GameAudio.shared.play(
            "sound_select",
            enabled: game.state.soundEnabled
        )

        if currentGlyphSlot >= 5 {
            phase = .nameConfirmation
        }
    }

    private var composedName: String {
        enteredGlyphs.map { frame in
            guard let frame else { return " " }
            if frame <= 25 {
                return String(
                    UnicodeScalar(65 + frame) ?? UnicodeScalar(65)
                )
            }
            if frame <= 35 {
                return String(frame - 26)
            }
            return " "
        }
        .joined()
    }
}

// MARK: - Original 550-counter first-run opening

struct ClassicTutorialView: View {
    @EnvironmentObject private var game: GameModel
    @State private var openingStartedAt = Date()
    @State private var openingTask: Task<Void, Never>?

    var body: some View {
        ClassicLifecycleShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            cancelEnabled: false,
            acceptEnabled: false,
            onLeft: {},
            onCancel: {},
            onAccept: {}
        ) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) {
                timeline in
                openingScene(
                    counter: classicOpeningCounter(
                        elapsed: max(
                            0,
                            timeline.date.timeIntervalSince(openingStartedAt)
                        )
                    )
                )
            }
        }
        .accessibilityLabel("First-run D-Tector opening")
        .onAppear {
            startOpening()
        }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            GameAudio.shared.stop()
        }
    }

    @ViewBuilder
    private func openingScene(counter: Int) -> some View {
        let character = game.currentCharacter
        let starter = game.state.docks
            .first(where: { $0 >= 0 })
            .flatMap { id in
                game.catalog.digimon.first { $0.id == id }
            }
        let spirit = game.catalog.digimon.first {
            $0.id == character.humanSpiritID
        }
        let starterSprite = starter?.sprite ?? "spr_agunimon_dtector"
        let spiritSprite = spirit?.sprite ?? "spr_agunimon_dtector"
        let starterEnergy = classicEnergyFrame(starter?.energy ?? 20)
        let spiritEnergy = classicEnergyFrame(spirit?.energy ?? 20)
        let spiritIndex = min(10, max(0, character.id * 2))

        ZStack(alignment: .topLeading) {
            if counter <= 60 {
                ClassicLifecycleSprite(
                    resource: "spr_train_trail_dtector",
                    frame: 1,
                    x: CGFloat(-60 + counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_trail_dtector",
                    frame: 2,
                    x: CGFloat(-30 + counter)
                )
                // Source subimage 3 wraps to the first extracted frame.
                ClassicLifecycleSprite(
                    resource: "spr_train_trail_dtector",
                    frame: 0,
                    x: CGFloat(counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: 0,
                    x: CGFloat(30 - counter)
                )
                ForEach(0..<3, id: \.self) { index in
                    ClassicLifecycleSprite(
                        resource: "spr_train_dtector",
                        frame: 1,
                        x: CGFloat(60 + index * 30 - counter)
                    )
                }
            } else if counter <= 119 {
                ClassicLifecycleSprite(
                    resource: "spr_train_trail_dtector",
                    frame: 1
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: 0,
                    x: CGFloat(30 - counter)
                )
                ForEach(0..<3, id: \.self) { index in
                    ClassicLifecycleSprite(
                        resource: "spr_train_dtector",
                        frame: 1,
                        x: CGFloat(60 + index * 30 - counter)
                    )
                }
            } else if counter <= 122 {
                ClassicLifecycleSprite(
                    resource: "spr_train_trail_dtector",
                    frame: 1
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: counter - 119
                )
            } else if counter <= 149 {
                ClassicLifecycleSprite(
                    resource: "\(character.sprite)_step",
                    frame: counter % 2,
                    x: CGFloat(152 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 150 {
                ClassicLifecycleSprite(
                    resource: character.sprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_question_dtector"
                )
            } else if counter <= 156 {
                if counter.isMultiple(of: 2) {
                    mirroredActor(
                        resource: starterSprite,
                        frame: 0,
                        anchorX: 27,
                        y: 4
                    )
                }
            } else if counter <= 186 {
                mirroredActor(
                    resource: "spr_energy_dtector",
                    frame: starterEnergy,
                    anchorX: CGFloat(24 + counter - 156),
                    y: 4
                )
                mirroredActor(
                    resource: starterSprite,
                    frame: 1,
                    anchorX: 24,
                    y: 4
                )
            } else if counter <= 242 {
                mirroredActor(
                    resource: "spr_energy_dtector",
                    frame: starterEnergy,
                    anchorX: CGFloat(-24 + counter - 186),
                    y: 4
                )
            } else if counter <= 266 {
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: 8,
                    y: CGFloat(270 - counter),
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_spirits_stand2_dtector",
                    x: 8,
                    y: 8,
                    width: 24,
                    height: 24
                )
            } else if counter <= 273 {
                mirroredActor(
                    resource: "spr_energy_dtector",
                    frame: starterEnergy,
                    anchorX: CGFloat(counter - 266),
                    y: 4
                )
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 274 {
                ClassicLifecycleSprite(
                    resource: "spr_happy",
                    x: 1,
                    y: 8,
                    width: 8,
                    height: 8
                )
                ClassicLifecycleSprite(
                    resource: "spr_happy",
                    x: 1,
                    y: 16,
                    width: 8,
                    height: 8
                )
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 275 {
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 303 {
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: 3,
                    y: CGFloat(278 - counter),
                    width: 24,
                    height: 24
                )
            } else if counter <= 333 {
                ClassicLifecycleSprite(
                    resource: "spr_spirits_dtector",
                    frame: spiritIndex,
                    x: CGFloat(counter - 330),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: character.sprite,
                    x: CGFloat(336 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 338 {
                if counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: character.sprite,
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                } else {
                    ClassicLifecycleSprite(
                        resource: "spr_spirits_dtector",
                        frame: spiritIndex,
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                }
            } else if counter <= 341 {
                ClassicLifecycleSprite(
                    resource: spiritSprite,
                    frame: counter.isMultiple(of: 2) ? 1 : 0,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 342 {
                ClassicLifecycleSprite(
                    resource: spiritSprite,
                    frame: 1,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 373 {
                ClassicLifecycleSprite(
                    resource: "spr_energy_dtector",
                    frame: spiritEnergy,
                    x: CGFloat(350 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: spiritSprite,
                    frame: 1,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 431 {
                ClassicLifecycleSprite(
                    resource: "spr_energy_dtector",
                    frame: spiritEnergy,
                    x: CGFloat(403 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 432 {
                mirroredActor(
                    resource: starterSprite,
                    frame: 0,
                    anchorX: 27,
                    y: 4
                )
            } else if counter <= 437 {
                ClassicLifecycleSprite(
                    resource: "spr_hit_dtector",
                    frame: counter % 2,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 438 {
                ClassicLifecycleSprite(
                    resource: character.sprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 439 {
                ClassicLifecycleSprite(
                    resource: spiritSprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 440 {
                ClassicLifecycleSprite(
                    resource: character.sprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter == 441 {
                ClassicLifecycleSprite(
                    resource: "\(character.sprite)_spirit",
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 473 {
                mirroredActor(
                    resource: starterSprite,
                    frame: 0,
                    anchorX: CGFloat(-6 + counter - 441),
                    y: 4
                )
                ClassicLifecycleSprite(
                    resource: "\(character.sprite)_spirit",
                    x: CGFloat(3 + counter - 441),
                    y: 4,
                    width: 24,
                    height: 24
                )
            } else if counter <= 506 {
                ClassicLifecycleSprite(
                    resource: starterSprite,
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_catch_dtector",
                    y: CGFloat(32 - (counter - 474))
                )
            } else if counter <= 539 {
                ClassicLifecycleSprite(
                    resource: starterSprite,
                    x: 3,
                    y: CGFloat(4 - (counter - 507)),
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_catch_dtector",
                    y: CGFloat(-(counter - 507))
                )
            } else {
                if !counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "spr_dtector_catch_dtector",
                        frame: 0
                    )
                }
                ClassicLifecycleSprite(
                    resource: "spr_dtector_catch_dtector",
                    frame: 1
                )
            }
        }
    }

    private func startOpening() {
        openingTask?.cancel()
        openingStartedAt = Date()
        GameAudio.shared.play(
            "sound_game_start_dtector",
            enabled: game.state.soundEnabled
        )
        openingTask = Task { @MainActor in
            let nanoseconds = UInt64(
                classicOpeningDuration * 1_000_000_000
            )
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, game.screen == .tutorial else { return }
            game.completeTutorial()
        }
    }

    private func mirroredActor(
        resource: String,
        frame: Int,
        anchorX: CGFloat,
        y: CGFloat
    ) -> some View {
        ClassicLifecycleSprite(
            resource: resource,
            frame: frame,
            x: anchorX - 24,
            y: y,
            width: 24,
            height: 24,
            mirrored: true
        )
    }
}

// MARK: - Original route prelude and shared train credits

struct ClassicEndingView: View {
    @EnvironmentObject private var game: GameModel
    @State private var endingStartedAt = Date()
    @State private var canFinish = false
    @State private var endingTask: Task<Void, Never>?

    private enum Route {
        case koichi
        case lucemon
    }

    private var route: Route {
        game.endingMessage.localizedCaseInsensitiveContains("LUCEMON")
            ? .lucemon
            : .koichi
    }

    private var partyIDs: [Int] {
        game.state.characterParty.indices.filter {
            $0 != game.state.currentCharacter
                && game.state.characterParty[$0]
                && game.catalog.characters.indices.contains($0)
        }
    }

    private var missingIDs: [Int] {
        game.state.characterParty.indices.filter {
            $0 != game.state.currentCharacter
                && !game.state.characterParty[$0]
                && game.catalog.characters.indices.contains($0)
        }
    }

    var body: some View {
        ClassicLifecycleShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: canFinish,
            cancelEnabled: canFinish,
            acceptEnabled: canFinish,
            onLeft: finishEnding,
            onCancel: finishEnding,
            onAccept: finishEnding
        ) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) {
                timeline in
                endingScene(
                    elapsed: max(
                        0,
                        timeline.date.timeIntervalSince(endingStartedAt)
                    )
                )
            }
        }
        .accessibilityLabel(
            route == .koichi
                ? "Koichi ending and train credits"
                : "Lucemon ending and train credits"
        )
        .accessibilityHint(
            canFinish
                ? "Press any detector button to continue"
                : "Credits are playing"
        )
        .onAppear {
            startEnding()
        }
        .onDisappear {
            endingTask?.cancel()
            endingTask = nil
            GameAudio.shared.stop()
        }
    }

    @ViewBuilder
    private func endingScene(elapsed: TimeInterval) -> some View {
        let preludeDuration = route == .koichi
            ? classicKoichiPreludeDuration
            : classicLucemonPreludeDuration

        if elapsed < preludeDuration {
            switch route {
            case .koichi:
                koichiPreludeScene(
                    counter: classicSequentialCounter(
                        elapsed: elapsed,
                        terminal: 205,
                        duration: classicKoichiCounterDuration
                    )
                )
            case .lucemon:
                lucemonPreludeScene(
                    counter: classicSequentialCounter(
                        elapsed: elapsed,
                        terminal: 82,
                        duration: classicLucemonCounterDuration
                    )
                )
            }
        } else {
            let sample = classicTrainSample(
                elapsed: elapsed - preludeDuration,
                partyCount: partyIDs.count,
                missingCount: missingIDs.count
            )
            trainScene(sample: sample)
        }
    }

    @ViewBuilder
    private func koichiPreludeScene(counter: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if counter <= 8 {
                if counter.isMultiple(of: 2) {
                    mirroredEndingActor(
                        resource: "spr_ancientsphinxmon_dtector",
                        anchorX: 27
                    )
                }
            } else if counter <= 16 {
                if counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "spr_summon_dtector",
                        frame: 4
                    )
                }
            } else if counter <= 42 {
                mirroredEndingActor(
                    resource: "spr_ancientsphinxmon_dtector",
                    anchorX: CGFloat(27 - (counter - 16))
                )
                mirroredEndingActor(
                    resource: "spr_ancientsphinxmon_dtector",
                    anchorX: CGFloat(27 + (counter - 16))
                )
            } else if counter <= 74 {
                if counter > 58 {
                    ClassicLifecycleSprite(
                        resource: "spr_spirits_dtector",
                        frame: 10,
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                }
                ClassicLifecycleSprite(
                    resource: "spr_catch_dtector",
                    frame: 1,
                    y: CGFloat(-32 + (counter - 42) * 2)
                )
            } else if counter <= 106 {
                if counter > 94 {
                    ClassicLifecycleSprite(
                        resource: "spr_spirits_dtector",
                        frame: 11,
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                }
                ClassicLifecycleSprite(
                    resource: "spr_catch_dtector",
                    frame: 1,
                    y: CGFloat(-32 + (counter - 74) * 2)
                )
            } else if counter <= 112 {
                ClassicLifecycleSprite(
                    resource: "spr_ancient_dtector",
                    frame: counter.isMultiple(of: 2) ? 1 : 0
                )
                ClassicLifecycleSprite(
                    resource: "spr_ancient_cover_dtector"
                )
            } else if counter <= 118 {
                if !counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "spr_ancient_dtector"
                    )
                    ClassicLifecycleSprite(
                        resource: "spr_ancient_cover_dtector"
                    )
                }
            } else if counter <= 126 {
                if !counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "spr_summon_dtector",
                        frame: 3
                    )
                }
            } else if counter <= 132 {
                ClassicLifecycleSprite(
                    resource: "spr_koichi_defeat",
                    x: 3,
                    y: 4,
                    width: 24,
                    height: 24
                )
                if !counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "spr_summon_dtector",
                        frame: 3
                    )
                }
            } else if counter == 133 {
                endingKoichiBase(mirrored: false)
            } else if counter == 134 {
                endingKoichiBase(mirrored: false)
                ClassicLifecycleSprite(
                    resource: "spr_question_dtector"
                )
            } else if counter == 135 {
                endingKoichiBase(mirrored: false)
            } else if counter <= 142 {
                endingKoichiBase(mirrored: counter.isMultiple(of: 2))
            } else if counter <= 196 {
                ClassicLifecycleSprite(
                    resource: game.currentCharacter.sprite,
                    x: CGFloat(199 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                mirroredEndingActor(
                    resource: "spr_koichi",
                    anchorX: CGFloat(169 - counter)
                )
            } else if counter <= 204 {
                if counter.isMultiple(of: 2) {
                    ClassicLifecycleSprite(
                        resource: "\(game.currentCharacter.sprite)_happy",
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                    ClassicLifecycleSprite(
                        resource: "spr_happy",
                        x: 23,
                        width: 8,
                        height: 8
                    )
                    ClassicLifecycleSprite(
                        resource: "spr_happy",
                        width: 8,
                        height: 8
                    )
                } else {
                    ClassicLifecycleSprite(
                        resource: game.currentCharacter.sprite,
                        x: 3,
                        y: 4,
                        width: 24,
                        height: 24
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func lucemonPreludeScene(counter: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if counter <= 32 {
                mirroredEndingActor(
                    resource: "spr_lucemon_dtector",
                    anchorX: 27,
                    y: CGFloat(-28 + counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_capture_ball_dtector",
                    y: CGFloat(-32 + counter)
                )
            } else if counter <= 40 {
                mirroredEndingActor(
                    resource: "spr_lucemon_dtector",
                    frame: counter.isMultiple(of: 2) ? 4 : 0,
                    anchorX: 27
                )
                ClassicLifecycleSprite(
                    resource: "spr_capture_ball_dtector"
                )
            } else if counter <= 48 {
                if !counter.isMultiple(of: 2) {
                    mirroredEndingActor(
                        resource: "spr_lucemon_dtector",
                        frame: 4,
                        anchorX: 27
                    )
                }
                ClassicLifecycleSprite(
                    resource: "spr_capture_ball_dtector"
                )
            } else if counter <= 80 {
                ClassicLifecycleSprite(
                    resource: "spr_capture_ball_dtector",
                    y: CGFloat(counter - 48)
                )
            }
        }
    }

    @ViewBuilder
    private func trainScene(sample: ClassicTrainSample) -> some View {
        let counter = sample.counter

        ZStack(alignment: .topLeading) {
            if counter <= 59 {
                ClassicLifecycleSprite(
                    resource: "spr_train_trail2_dtector",
                    frame: 0,
                    x: CGFloat(-60 + counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_trail2_dtector",
                    frame: 1,
                    x: CGFloat(-30 + counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_trail2_dtector",
                    frame: 2,
                    x: CGFloat(counter)
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: 0,
                    x: CGFloat(30 - counter)
                )
                ForEach(0..<3, id: \.self) { index in
                    ClassicLifecycleSprite(
                        resource: "spr_train_dtector",
                        frame: 1,
                        x: CGFloat(60 + index * 30 - counter)
                    )
                }
            } else if counter <= 62 {
                ClassicLifecycleSprite(
                    resource: "spr_train_trail2_dtector",
                    frame: 0
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: counter - 59
                )
            } else if counter == 63 {
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter <= 118,
                      partyIDs.indices.contains(sample.enteringIndex) {
                let character = game.catalog.characters[
                    partyIDs[sample.enteringIndex]
                ]
                ClassicLifecycleSprite(
                    resource: "\(character.sprite)_step",
                    frame: counter % 2,
                    x: CGFloat(94 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter > 118, counter < 141 {
                ClassicLifecycleSprite(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: counter % 2,
                    x: CGFloat(149 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter == 141 {
                ClassicLifecycleSprite(
                    resource: game.currentCharacter.sprite,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter == 142 {
                mirroredEndingActor(
                    resource: game.currentCharacter.sprite,
                    anchorX: 32
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter == 143 {
                ClassicLifecycleSprite(
                    resource: game.currentCharacter.sprite,
                    x: 8,
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter <= 162 {
                ClassicLifecycleSprite(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: counter % 2,
                    x: CGFloat(151 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter <= 213,
                      missingIDs.indices.contains(sample.enteringIndex) {
                let character = game.catalog.characters[
                    missingIDs[sample.enteringIndex]
                ]
                ClassicLifecycleSprite(
                    resource: "\(character.sprite)_step",
                    frame: counter % 2,
                    x: CGFloat(193 - counter),
                    y: 4,
                    width: 24,
                    height: 24
                )
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector"
                )
            } else if counter == 214 {
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector",
                    frame: 1
                )
            } else if counter == 215 {
                ClassicLifecycleSprite(
                    resource: "spr_train_station_dtector",
                    frame: 2
                )
            } else if counter <= 305 {
                let movement = counter - 215
                ForEach(0..<4, id: \.self) { index in
                    ClassicLifecycleSprite(
                        resource: "spr_train_trail2_dtector",
                        frame: index % 3,
                        x: CGFloat(-90 + index * 30 + movement)
                    )
                }
                ClassicLifecycleSprite(
                    resource: "spr_train_dtector",
                    frame: 0,
                    x: CGFloat(-movement)
                )
                ForEach(0..<3, id: \.self) { index in
                    ClassicLifecycleSprite(
                        resource: "spr_train_dtector",
                        frame: 1,
                        x: CGFloat(30 + index * 30 - movement)
                    )
                }
            } else if counter <= 315 {
                trainTrailLoop(counter: counter, trainFrame: 1)
            } else {
                trainTrailLoop(counter: counter, trainFrame: 4)
                thankYouScroll(counter: counter)
            }
        }
    }

    @ViewBuilder
    private func trainTrailLoop(
        counter: Int,
        trainFrame: Int
    ) -> some View {
        let scroll = counter % 60
        ForEach(0..<3, id: \.self) { index in
            ClassicLifecycleSprite(
                resource: "spr_train_trail2_dtector",
                frame: 0,
                x: CGFloat(-60 + index * 30 + scroll)
            )
        }
        ClassicLifecycleSprite(
            resource: "spr_train_dtector",
            frame: trainFrame
        )
    }

    @ViewBuilder
    private func thankYouScroll(counter: Int) -> some View {
        let glyphs = [19, 7, 0, 13, 10, -1, 24, 14, 20]
        let reset = (counter - 315) % (glyphs.count * 6 + 32)

        ForEach(Array(glyphs.enumerated()), id: \.offset) {
            index,
            frame in
            if frame >= 0 {
                ClassicLifecycleGlyph(
                    frame: frame,
                    x: CGFloat(30 - reset + index * 6),
                    y: 0
                )
            }
        }
        ClassicLifecycleSprite(
            resource: "spr_question_dtector",
            x: CGFloat(84 - reset)
        )
    }

    private func endingKoichiBase(mirrored: Bool) -> some View {
        ClassicLifecycleSprite(
            resource: "spr_koichi",
            x: 3,
            y: 4,
            width: 24,
            height: 24,
            mirrored: mirrored
        )
    }

    private func mirroredEndingActor(
        resource: String,
        frame: Int = 0,
        anchorX: CGFloat,
        y: CGFloat = 4
    ) -> some View {
        ClassicLifecycleSprite(
            resource: resource,
            frame: frame,
            x: anchorX - 24,
            y: y,
            width: 24,
            height: 24,
            mirrored: true
        )
    }

    private func startEnding() {
        endingTask?.cancel()
        endingStartedAt = Date()
        canFinish = false

        let activeRoute = route
        let preludeDuration = activeRoute == .koichi
            ? classicKoichiPreludeDuration
            : classicLucemonPreludeDuration
        let finishDelay = classicTrainTime(
            toCounter: 501,
            partyCount: partyIDs.count,
            missingCount: missingIDs.count
        )

        GameAudio.shared.play(
            activeRoute == .koichi
                ? "sound_end_koichi_dtector"
                : "sound_end_lucemon_dtector",
            enabled: game.state.soundEnabled
        )

        endingTask = Task { @MainActor in
            if activeRoute == .koichi {
                let happyDelay = classicKoichiHappySoundTime
                try? await Task.sleep(
                    nanoseconds: UInt64(happyDelay * 1_000_000_000)
                )
                guard !Task.isCancelled, game.screen == .ending else {
                    return
                }
                GameAudio.shared.play(
                    "sound_char_happy_long",
                    enabled: game.state.soundEnabled
                )
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        (preludeDuration - happyDelay) * 1_000_000_000
                    )
                )
            } else {
                try? await Task.sleep(
                    nanoseconds: UInt64(
                        preludeDuration * 1_000_000_000
                    )
                )
            }

            guard !Task.isCancelled, game.screen == .ending else { return }
            GameAudio.shared.play(
                "sound_endgame_dtector",
                enabled: game.state.soundEnabled
            )
            try? await Task.sleep(
                nanoseconds: UInt64(finishDelay * 1_000_000_000)
            )
            guard !Task.isCancelled, game.screen == .ending else { return }
            canFinish = true
        }
    }

    private func finishEnding() {
        guard canFinish else { return }
        GameAudio.shared.stop()
        game.finishEnding()
    }
}

// MARK: - Source counter clocks

private func classicEnergyFrame(_ energy: Int) -> Int {
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
    case ..<160: 9
    case ...220: 10
    default: 11
    }
}

private func classicOpeningCounterDuration(_ counter: Int) -> TimeInterval {
    let ticks: Double
    switch counter {
    case 0...64: ticks = 3
    case 65...95: ticks = 6
    case 96...118: ticks = 10
    case 119...121: ticks = 30
    case 122: ticks = 3
    case 123...148: ticks = 6
    case 149: ticks = 30
    case 150...154: ticks = 15
    case 155: ticks = 3
    case 156...272: ticks = 3
    case 273...274: ticks = 15
    case 275...302: ticks = 3
    case 303...331: ticks = 6
    case 332: ticks = 15
    case 333...340: ticks = 15
    case 341: ticks = 3
    case 342...431: ticks = 3
    case 432...440: ticks = 30
    case 441: ticks = 6
    case 442...471: ticks = 6
    case 472: ticks = 30
    case 473: ticks = 3
    case 474...539: ticks = 3
    case 540...548: ticks = 20
    default: ticks = 0
    }
    return ticks / 60.0
}

private let classicOpeningDuration: TimeInterval = (0..<549)
    .reduce(0) { $0 + classicOpeningCounterDuration($1) }

private func classicOpeningCounter(elapsed: TimeInterval) -> Int {
    classicSequentialCounter(
        elapsed: elapsed,
        terminal: 549,
        duration: classicOpeningCounterDuration
    )
}

private func classicKoichiCounterDuration(_ counter: Int) -> TimeInterval {
    let ticks: Double
    switch counter {
    case 0...16: ticks = 10
    case 17...105: ticks = 6
    case 106...131: ticks = 15
    case 132...133: ticks = 30
    case 134...141: ticks = 15
    case 142...195: ticks = 6
    case 196...204: ticks = 30
    default: ticks = 0
    }
    return ticks / 60.0
}

private func classicLucemonCounterDuration(_ counter: Int) -> TimeInterval {
    let ticks: Double
    switch counter {
    case 0...31: ticks = 6
    case 32...47: ticks = 15
    case 48...80: ticks = 6
    case 81: ticks = 30
    default: ticks = 0
    }
    return ticks / 60.0
}

private let classicKoichiPreludeDuration: TimeInterval = (0..<205)
    .reduce(0) { $0 + classicKoichiCounterDuration($1) }

private let classicLucemonPreludeDuration: TimeInterval = (0..<82)
    .reduce(0) { $0 + classicLucemonCounterDuration($1) }

private let classicKoichiHappySoundTime: TimeInterval = (0...196)
    .reduce(0) { $0 + classicKoichiCounterDuration($1) }

private func classicSequentialCounter(
    elapsed: TimeInterval,
    terminal: Int,
    duration: (Int) -> TimeInterval
) -> Int {
    var remaining = max(0, elapsed)
    var counter = 0

    while counter < terminal {
        let interval = duration(counter)
        guard interval > 0, remaining >= interval else { break }
        remaining -= interval
        counter += 1
    }
    return counter
}

private struct ClassicTrainSample {
    var counter: Int
    var enteringIndex: Int
}

private struct ClassicTrainTransition {
    let duration: TimeInterval
    let counter: Int
    let enteringIndex: Int
}

private func classicTrainTransition(
    from sample: ClassicTrainSample,
    partyCount: Int,
    missingCount: Int
) -> ClassicTrainTransition {
    let counter = sample.counter
    var nextCounter = counter + 1
    var nextIndex = sample.enteringIndex
    var ticks: Double

    switch counter {
    case 0...40:
        ticks = 6
    case 41...58:
        ticks = 10
    case 59...61:
        ticks = 30
    case 62:
        ticks = 3
        if partyCount == 0 {
            nextCounter = 119
        }
    case 63...116:
        ticks = 6
    case 117:
        ticks = 3
        if nextIndex < partyCount - 1 {
            nextIndex += 1
            nextCounter = 64
        }
    case 118...139:
        ticks = 6
    case 140...141:
        ticks = 60
    case 142:
        ticks = 6
    case 143...160:
        ticks = 6
        nextIndex = 0
        if missingCount == 0, nextCounter == 160 {
            ticks = 60
            nextCounter = 214
        }
    case 161...212:
        ticks = 6
    case 213:
        if nextIndex < missingCount - 1 {
            ticks = 3
            nextIndex += 1
            nextCounter = 161
        } else {
            ticks = 60
        }
    case 214:
        ticks = 60
    default:
        ticks = 6
    }

    return ClassicTrainTransition(
        duration: ticks / 60.0,
        counter: nextCounter,
        enteringIndex: nextIndex
    )
}

private func classicTrainSample(
    elapsed: TimeInterval,
    partyCount: Int,
    missingCount: Int
) -> ClassicTrainSample {
    var remaining = max(0, elapsed)
    var sample = ClassicTrainSample(counter: 0, enteringIndex: 0)

    while true {
        if sample.counter > 215 {
            let interval = 6.0 / 60.0
            let steps = Int(remaining / interval)
            sample.counter += steps
            return sample
        }

        let transition = classicTrainTransition(
            from: sample,
            partyCount: partyCount,
            missingCount: missingCount
        )
        guard remaining >= transition.duration else { return sample }
        remaining -= transition.duration
        sample.counter = transition.counter
        sample.enteringIndex = transition.enteringIndex
    }
}

private func classicTrainTime(
    toCounter target: Int,
    partyCount: Int,
    missingCount: Int
) -> TimeInterval {
    var elapsed: TimeInterval = 0
    var sample = ClassicTrainSample(counter: 0, enteringIndex: 0)

    while sample.counter < target {
        if sample.counter > 215 {
            elapsed += Double(target - sample.counter) * (6.0 / 60.0)
            return elapsed
        }
        let transition = classicTrainTransition(
            from: sample,
            partyCount: partyCount,
            missingCount: missingCount
        )
        elapsed += transition.duration
        sample.counter = transition.counter
        sample.enteringIndex = transition.enteringIndex
    }
    return elapsed
}
