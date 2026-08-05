import SwiftUI

/// A strict 30×32 menu surface backed by the original full-screen sprite.
///
/// The original D-Tector uses Down to advance `image_index`, Left for an
/// alternate route, Up to cancel, and Right to accept. The shared detector
/// controls expose Left/Cancel/Accept; tapping the LCD itself supplies the
/// original Down/select action without adding visible non-classic UI.
struct ClassicMenuScaffold: View {
    let resource: String
    let frameCount: Int
    let optionLabels: [String]
    @Binding var selection: Int

    var showGrid = false
    var readableLabelOverlay = false
    var leftEnabled = true
    var cancelEnabled = true
    var acceptEnabled = true

    var onCycle: () -> Void
    var onLeft: () -> Void
    var onCancel: () -> Void
    var onAccept: () -> Void

    private var safeFrameCount: Int {
        max(1, frameCount)
    }

    private var normalizedSelection: Int {
        let remainder = selection % safeFrameCount
        return remainder >= 0 ? remainder : remainder + safeFrameCount
    }

    private var selectedLabel: String {
        guard optionLabels.indices.contains(normalizedSelection) else {
            return "Option \(normalizedSelection + 1)"
        }
        return optionLabels[normalizedSelection]
    }

    var body: some View {
        ClassicMenuShell(
            showGrid: showGrid,
            leftEnabled: leftEnabled,
            cancelEnabled: cancelEnabled,
            acceptEnabled: acceptEnabled,
            onStageTap: cycleSelection,
            onLeft: onLeft,
            onCancel: onCancel,
            onAccept: onAccept
        ) {
            ZStack {
                ClassicLCDSprite(
                    resource: resource,
                    frame: normalizedSelection
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if readableLabelOverlay {
                    ClassicMenuReadableLabel(text: selectedLabel)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("D-Tector menu")
        .accessibilityValue(selectedLabel)
        .accessibilityHint("Tap the LCD to select the next option")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                cycleSelection()
            case .decrement:
                selection = (
                    normalizedSelection - 1 + safeFrameCount
                ) % safeFrameCount
                onCycle()
            @unknown default:
                break
            }
        }
        .onAppear {
            selection = normalizedSelection
        }
    }

    private func cycleSelection() {
        selection = (normalizedSelection + 1) % safeFrameCount
        onCycle()
    }
}

private struct ClassicMenuReadableLabel: View {
    let text: String

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / ClassicLCDGeometry.logicalWidth,
                geometry.size.height / ClassicLCDGeometry.logicalHeight
            )
            let bandHeight = 11 * scale
            let bottomPadding = 1 * scale

            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    DetectorPalette.screen
                    Text(text.uppercased())
                        .font(
                            .system(
                                size: 6.3 * scale,
                                weight: .black,
                                design: .monospaced
                            )
                        )
                        .minimumScaleFactor(0.45)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DetectorPalette.ink)
                        .frame(maxWidth: geometry.size.width - 2 * scale)
                        .allowsTightening(true)
                }
                .frame(height: bandHeight)
                .padding(.bottom, bottomPadding)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// Original `obj_main_menu_dtector` presentation.
///
/// Frames: Map, Status, Spirits, Camp, Connect.
struct ClassicMainMenuView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection: Int

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ClassicMenuScaffold(
            resource: "spr_main_menu_dtector",
            frameCount: 5,
            optionLabels: [
                "Map",
                "Status",
                "Spirits",
                "Camp",
                "Connect"
            ],
            selection: $selection,
            showGrid: game.state.gridEnabled,
            onCycle: playSelect,
            // vk_left: switch to the extra menu.
            onLeft: {
                playSelect()
                game.openExtraMenu()
            },
            // vk_up: return to the character/home screen.
            onCancel: {
                playSelect()
                game.goHome()
            },
            // vk_right: accept the current full-screen frame.
            onAccept: acceptSelection
        )
        .onAppear {
            playClassicMenuSound("sound_alert_old")
        }
    }

    private func acceptSelection() {
        if game.state.defeated, selection != 3 {
            playCancel()
            return
        }

        switch selection {
        case 0:
            playSelect()
            game.navigate(.map)
        case 1:
            playSelect()
            game.navigate(.status)
        case 2:
            guard game.state.spiritsUnlocked.contains(true) else {
                playCancel()
                return
            }
            playSelect()
            game.navigate(.spirits)
        case 3:
            playSelect()
            game.navigate(.camp)
        case 4:
            playSelect()
            game.navigate(.connect)
        default:
            break
        }
    }

    private func playSelect() {
        playClassicMenuSound("sound_select")
    }

    private func playCancel() {
        playClassicMenuSound("sound_cancel")
    }

    private func playClassicMenuSound(_ resource: String) {
        GameAudio.shared.play(
            resource,
            enabled: game.state.soundEnabled
        )
    }
}

/// Original `obj_menu_extra_dtector` presentation.
///
/// Frames: Database, Digi-Digits, Games, Digital TV.
struct ClassicExtraMenuView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection: Int

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ClassicMenuScaffold(
            resource: "spr_menu_extra_dtector",
            frameCount: 4,
            optionLabels: [
                "Database",
                "Digi-Code",
                "Games",
                "Digital TV"
            ],
            selection: $selection,
            showGrid: game.state.gridEnabled,
            readableLabelOverlay: true,
            onCycle: playSelect,
            // vk_left: switch back to the main menu.
            onLeft: {
                playSelect()
                game.navigate(.mainMenu)
            },
            // vk_up: return directly to the character/home screen.
            onCancel: {
                playSelect()
                game.goHome()
            },
            onAccept: acceptSelection
        )
    }

    private func acceptSelection() {
        guard !game.state.defeated else {
            playCancel()
            return
        }

        let destination: FullGameScreen
        switch selection {
        case 0:
            destination = .database
        case 1:
            destination = .codeScanner
        case 2:
            destination = .games
        case 3:
            destination = .tv
        default:
            return
        }

        playSelect()
        game.navigate(destination)
    }

    private func playSelect() {
        playClassicMenuSound("sound_select")
    }

    private func playCancel() {
        playClassicMenuSound("sound_cancel")
    }

    private func playClassicMenuSound(_ resource: String) {
        GameAudio.shared.play(
            resource,
            enabled: game.state.soundEnabled
        )
    }
}

/// Original `obj_menu_game_dtector` presentation.
///
/// Frames: Scan Break and Digi-Ship.
struct ClassicGamesMenuView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection: Int

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ClassicMenuScaffold(
            resource: "spr_menu_game_dtector",
            frameCount: 2,
            optionLabels: [
                "Scan Break",
                "Digi-Ship"
            ],
            selection: $selection,
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            onCycle: playSelect,
            // No vk_left handler exists on the original game menu.
            onLeft: {},
            // vk_up: return to Extra at its Games frame.
            onCancel: {
                playCancel()
                game.navigate(.extraMenu)
            },
            onAccept: acceptSelection
        )
    }

    private func acceptSelection() {
        guard !game.state.defeated else {
            playCancel()
            return
        }

        playSelect()
        switch selection {
        case 0:
            game.startMiniGame(.digiDigit)
        case 1:
            game.startMiniGame(.digiShip)
        default:
            break
        }
    }

    private func playSelect() {
        playClassicMenuSound("sound_select")
    }

    private func playCancel() {
        playClassicMenuSound("sound_cancel")
    }

    private func playClassicMenuSound(_ resource: String) {
        GameAudio.shared.play(
            resource,
            enabled: game.state.soundEnabled
        )
    }
}

/// Original `obj_menu_con_dtector` presentation mapped onto the port's
/// supported offline battle and data-send routes.
///
/// Frames: Battle and Send.
struct ClassicConnectMenuView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection: Int

    init(initialSelection: Int = 0) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ClassicMenuScaffold(
            resource: "spr_menu_con_dtector",
            frameCount: 2,
            optionLabels: [
                "Battle",
                "Send"
            ],
            selection: $selection,
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            onCycle: playSelect,
            // No vk_left handler exists on the original connect menu.
            onLeft: {},
            // vk_up: return to Main at its Connect frame.
            onCancel: {
                playCancel()
                game.navigate(.mainMenu)
            },
            onAccept: acceptSelection
        )
    }

    private func acceptSelection() {
        playSelect()
        switch selection {
        case 0:
            playClassicMenuSound("sound_connect")
            game.quickLinkBattle()
        case 1:
            playClassicMenuSound("sound_connect")
            game.navigate(.connectSend)
        default:
            break
        }
    }

    private func playSelect() {
        playClassicMenuSound("sound_select")
    }

    private func playCancel() {
        playClassicMenuSound("sound_cancel")
    }

    private func playClassicMenuSound(_ resource: String) {
        GameAudio.shared.play(
            resource,
            enabled: game.state.soundEnabled
        )
    }
}

/// Original status selector and four-page status detail flow.
///
/// `obj_status_dtector` keeps the selector frame fixed and changes only the
/// 24×24 character at logical `(3,4)`. Accept opens
/// `spr_status_detail_dtector`; tapping the LCD advances its four pages just
/// like the original Down input.
struct ClassicStatusSelectorView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selectedCharacterID = -1
    @State private var detailPage: Int?

    private var availableCharacterIDs: [Int] {
        let available = game.catalog.characters.indices.filter { index in
            game.state.characterParty.indices.contains(index)
                && game.state.characterParty[index]
        }
        return available.isEmpty
            ? [game.state.currentCharacter]
            : available
    }

    private var currentCharacterID: Int {
        availableCharacterIDs.contains(selectedCharacterID)
            ? selectedCharacterID
            : (
                availableCharacterIDs.contains(game.state.currentCharacter)
                    ? game.state.currentCharacter
                    : availableCharacterIDs[0]
            )
    }

    private var currentCharacter: CharacterDefinition {
        guard game.catalog.characters.indices.contains(currentCharacterID) else {
            return game.currentCharacter
        }
        return game.catalog.characters[currentCharacterID]
    }

    private var currentStats: CharacterStats {
        guard game.state.characterStats.indices.contains(currentCharacterID) else {
            return .initial(from: currentCharacter)
        }
        return game.state.characterStats[currentCharacterID]
    }

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            leftEnabled: false,
            cancelEnabled: true,
            acceptEnabled: detailPage == nil,
            onStageTap: advanceLCD,
            onLeft: {},
            onCancel: cancel,
            onAccept: openDetail
        ) {
            GeometryReader { geometry in
                statusStage(in: geometry.size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            detailPage == nil
                ? "Character status selector"
                : "Character status detail"
        )
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tap right to advance, center to select, hold to return")
        .onAppear {
            selectedCharacterID = currentCharacterID
        }
    }

    @ViewBuilder
    private func statusStage(in size: CGSize) -> some View {
        let scale = min(size.width / 30, size.height / 32)
        let originX = (size.width - 30 * scale) / 2
        let originY = (size.height - 32 * scale) / 2

        if let detailPage {
            ClassicPixelAsset(
                resource: "spr_status_detail_dtector",
                frame: detailPage
            )
            .frame(width: 30 * scale, height: 32 * scale)
            .position(
                x: originX + 15 * scale,
                y: originY + 16 * scale
            )

            switch detailPage {
            case 0:
                ClassicLogicalNumber(
                    value: game.state.level,
                    rightX: 24,
                    topY: 10,
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
                ClassicLogicalNumber(
                    value: currentStats.hp,
                    rightX: 24,
                    topY: 23,
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
            case 1:
                ClassicLogicalNumber(
                    value: currentStats.spirit,
                    rightX: 24,
                    topY: 23,
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
            case 2:
                ClassicLogicalNumber(
                    value: currentStats.stamina,
                    rightX: 24,
                    topY: 23,
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
            default:
                ClassicLogicalNumber(
                    value: currentStats.skill,
                    rightX: 24,
                    topY: 23,
                    scale: scale,
                    origin: CGPoint(x: originX, y: originY)
                )
            }
        } else {
            ClassicPixelAsset(resource: "spr_sel_dtector", frame: 1)
                .frame(width: 30 * scale, height: 32 * scale)
                .position(
                    x: originX + 15 * scale,
                    y: originY + 16 * scale
                )

            ClassicPixelAsset(
                resource: currentCharacter.sprite,
                frame: 0
            )
            .frame(width: 24 * scale, height: 24 * scale)
            .position(
                x: originX + 15 * scale,
                y: originY + 16 * scale
            )
        }
    }

    private var accessibilityValue: String {
        guard let detailPage else {
            return currentCharacter.name
        }
        switch detailPage {
        case 0:
            return "\(currentCharacter.name), level \(game.state.level), HP \(currentStats.hp)"
        case 1:
            return "\(currentCharacter.name), spirit \(currentStats.spirit)"
        case 2:
            return "\(currentCharacter.name), stamina \(currentStats.stamina)"
        default:
            return "\(currentCharacter.name), skill \(currentStats.skill)"
        }
    }

    private func advanceLCD() {
        if let detailPage {
            self.detailPage = (detailPage + 1) % 4
        } else {
            guard let position = availableCharacterIDs.firstIndex(
                of: currentCharacterID
            ) else { return }
            selectedCharacterID = availableCharacterIDs[
                (position + 1) % availableCharacterIDs.count
            ]
        }
        playClassicMenuSound("sound_select")
    }

    private func cancel() {
        playClassicMenuSound("sound_cancel")
        if detailPage != nil {
            detailPage = nil
        } else {
            game.navigate(.mainMenu)
        }
    }

    private func openDetail() {
        guard detailPage == nil else { return }
        playClassicMenuSound("sound_select")
        detailPage = 0
    }

    private func playClassicMenuSound(_ resource: String) {
        GameAudio.shared.play(
            resource,
            enabled: game.state.soundEnabled
        )
    }
}

/// Draws the original right-to-left number spacing used by
/// `draw_number_with_sprite`: 4-pixel glyphs with a 1-pixel gap.
private struct ClassicLogicalNumber: View {
    let value: Int
    let rightX: CGFloat
    let topY: CGFloat
    let scale: CGFloat
    let origin: CGPoint

    private var reversedDigits: [Int] {
        String(max(0, value))
            .compactMap(\.wholeNumberValue)
            .reversed()
    }

    var body: some View {
        ForEach(Array(reversedDigits.enumerated()), id: \.offset) {
            index,
            digit in
            ClassicPixelAsset(resource: "spr_numbers", frame: digit)
                .frame(width: 4 * scale, height: 5 * scale)
                .position(
                    x: origin.x
                        + (rightX - CGFloat(index) * 5 + 2) * scale,
                    y: origin.y + (topY + 2.5) * scale
                )
        }
        .accessibilityHidden(true)
    }
}
