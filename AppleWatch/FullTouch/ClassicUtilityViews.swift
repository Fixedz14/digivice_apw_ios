import SwiftUI

struct ClassicLCDLogicalSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let scale = min(
                geometry.size.width / ClassicLCDGeometry.logicalWidth,
                geometry.size.height / ClassicLCDGeometry.logicalHeight
            )

            ZStack(alignment: .topLeading) {
                content
            }
            .frame(
                width: ClassicLCDGeometry.logicalWidth,
                height: ClassicLCDGeometry.logicalHeight
            )
            .scaleEffect(scale)
            .position(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
        }
    }
}

struct ClassicLCDText: View {
    let text: String
    let x: CGFloat
    let y: CGFloat
    var maxGlyphs: Int? = nil
    var spacing: CGFloat = 1

    private var glyphs: [Int?] {
        let mapped = text.uppercased().map { character -> Int? in
            if character == " " { return nil }
            if let scalar = character.unicodeScalars.first {
                switch scalar.value {
                case 65...90:
                    return Int(scalar.value - 65)
                case 48...57:
                    return Int(scalar.value - 48 + 26)
                default:
                    return nil
                }
            }
            return nil
        }
        if let maxGlyphs {
            return Array(mapped.prefix(maxGlyphs))
        }
        return mapped
    }

    var body: some View {
        ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
            if let glyph {
                ClassicPixelAsset(resource: "spr_font_dtector", frame: glyph)
                    .frame(width: 5, height: 7)
                    .position(
                        x: x + CGFloat(index) * (5 + spacing) + 2.5,
                        y: y + 3.5
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

struct ClassicCodeScannerView: View {
    @EnvironmentObject private var game: GameModel

    @State private var selectedGlyph = 0
    @State private var currentSlot = 0
    @State private var glyphs: [Int?] = Array(repeating: nil, count: 5)
    @State private var blink = false

    private var code: String {
        glyphs.compactMap { glyph -> String? in
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

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            onLeft: cycleGlyph,
            onCancel: cancel,
            onAccept: accept
        ) {
            ClassicLCDLogicalSurface {
                Rectangle()
                    .fill(DetectorPalette.screen)
                    .frame(width: 30, height: 32)
                    .position(x: 15, y: 16)
                ClassicLCDText(text: "DIGI", x: 3, y: 0)
                ClassicLCDText(text: "CODE", x: 2, y: 8)
                ClassicPixelAsset(resource: "spr_font_dtector", frame: selectedGlyph)
                    .frame(width: 5, height: 7)
                    .position(x: 14.5, y: 18.5)
                codeSlots
            }
        }
        .accessibilityLabel("Digi-code")
        .accessibilityValue(code.isEmpty ? "Empty" : code)
        .onAppear {
            syncFromInput()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                blink.toggle()
            }
        }
    }

    private var codeSlots: some View {
        ForEach(0..<5, id: \.self) { index in
            let x = CGFloat(index * 6)
            if let glyph = glyphs[index] {
                ClassicPixelAsset(resource: "spr_font_dtector", frame: glyph)
                    .frame(width: 5, height: 7)
                    .position(x: x + 2.5, y: 28.5)
            }
            if index != currentSlot || blink {
                ClassicPixelAsset(resource: "spr_sel_letter_dtector", frame: 0)
                    .frame(width: 5, height: 7)
                    .position(x: x + 2.5, y: 28.5)
            }
        }
    }

    private func syncFromInput() {
        let input = game.codeInput.uppercased()
        glyphs = Array(repeating: nil, count: 5)
        for (index, character) in input.prefix(5).enumerated() {
            if let scalar = character.unicodeScalars.first {
                switch scalar.value {
                case 65...90:
                    glyphs[index] = Int(scalar.value - 65)
                case 48...57:
                    glyphs[index] = Int(scalar.value - 48 + 26)
                default:
                    break
                }
            }
        }
        currentSlot = min(input.count, 4)
    }

    private func cycleGlyph() {
        selectedGlyph = (selectedGlyph + 1) % 36
        GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
    }

    private func cancel() {
        if currentSlot > 0 {
            glyphs[currentSlot] = nil
            currentSlot -= 1
            glyphs[currentSlot] = nil
        } else if glyphs[0] != nil {
            glyphs[0] = nil
        } else {
            game.navigate(.extraMenu)
        }
        game.codeInput = code
        GameAudio.shared.play("sound_cancel", enabled: game.state.soundEnabled)
    }

    private func accept() {
        glyphs[currentSlot] = selectedGlyph
        game.codeInput = code
        if currentSlot < 4 {
            currentSlot += 1
            GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
        } else {
            game.redeemCode()
            if game.codeInput.isEmpty {
                glyphs = Array(repeating: nil, count: 5)
                currentSlot = 0
            }
        }
    }
}

struct ClassicConnectSendView: View {
    @EnvironmentObject private var game: GameModel

    @State private var page = 0

    private var docked: [(Int, DigimonDefinition)] {
        game.state.docks.enumerated().compactMap { index, id in
            guard let digimon = game.catalog.digimon.first(
                where: { $0.id == id }
            ) else { return nil }
            return (index, digimon)
        }
    }

    private var pageCount: Int {
        max(1, docked.count + 1)
    }

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            onLeft: previous,
            onCancel: {
                GameAudio.shared.play(
                    "sound_cancel",
                    enabled: game.state.soundEnabled
                )
                game.navigate(.connect)
            },
            onAccept: accept
        ) {
            ClassicLCDLogicalSurface {
                Rectangle()
                    .fill(DetectorPalette.screen)
                    .frame(width: 30, height: 32)
                    .position(x: 15, y: 16)
                if page < docked.count {
                    dockPage(docked[page])
                } else {
                    receivePage
                }
            }
        }
        .accessibilityLabel("D-Tector data send")
        .onAppear {
            GameAudio.shared.play("sound_connect", enabled: game.state.soundEnabled)
            page = min(page, pageCount - 1)
        }
    }

    private func dockPage(_ item: (Int, DigimonDefinition)) -> some View {
        ZStack(alignment: .topLeading) {
            ClassicLCDText(text: "SEND", x: 3, y: 0)
            ClassicLCDText(text: "D\(item.0 + 1)", x: 20, y: 0)
            ClassicPixelAsset(resource: item.1.sprite, frame: 0)
                .frame(width: 24, height: 24)
                .position(x: 15, y: 19)
            if let code = item.1.code {
                ClassicLCDText(text: code, x: 0, y: 25, maxGlyphs: 5)
            }
        }
    }

    private var receivePage: some View {
        ZStack(alignment: .topLeading) {
            ClassicLCDText(text: "REC", x: 6, y: 0)
            ClassicLCDText(text: "DATA", x: 3, y: 8)
            ClassicLCDText(text: "CODE", x: 2, y: 17)
            ClassicLCDText(text: "EXTRA", x: 0, y: 25, maxGlyphs: 5)
        }
    }

    private func previous() {
        page = (page + pageCount - 1) % pageCount
        GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
    }

    private func accept() {
        if page == pageCount - 1 {
            game.navigate(.codeScanner)
        } else {
            page = (page + 1) % pageCount
        }
        GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
    }
}

struct ClassicSettingsView: View {
    @EnvironmentObject private var game: GameModel

    @State private var selection = 0

    private let labels = [
        "SOUND",
        "HAPTIC",
        "GRID",
        "NOTICE",
        "COLOR",
        "RESET"
    ]

    var body: some View {
        ClassicExpandedShell(
            showGrid: game.state.gridEnabled,
            onLeft: previous,
            onCancel: {
                GameAudio.shared.play(
                    "sound_cancel",
                    enabled: game.state.soundEnabled
                )
                game.navigate(.extraMenu)
            },
            onAccept: accept
        ) {
            ClassicLCDLogicalSurface {
                Rectangle()
                    .fill(DetectorPalette.screen)
                    .frame(width: 30, height: 32)
                    .position(x: 15, y: 16)
                ClassicPixelAsset(resource: "spr_config_dtector", frame: 0)
                    .frame(width: 30, height: 32)
                    .position(x: 15, y: 16)
                ClassicLCDText(
                    text: labels[selection],
                    x: 0,
                    y: 1,
                    maxGlyphs: 5
                )
                ClassicLCDText(text: valueText, x: 3, y: 17, maxGlyphs: 4)
                ClassicPixelAsset(resource: "spr_numbers", frame: selection + 1)
                    .frame(width: 4, height: 5)
                .position(x: 25, y: 28)
            }
        }
        .accessibilityLabel("D-Tector settings")
        .accessibilityValue("\(labels[selection]) \(valueText)")
    }

    private var valueText: String {
        switch selection {
        case 0:
            return game.state.soundEnabled ? "ON" : "OFF"
        case 1:
            return game.state.hapticsEnabled ? "ON" : "OFF"
        case 2:
            return game.state.gridEnabled ? "ON" : "OFF"
        case 3:
            return game.state.notificationsEnabled ? "ON" : "OFF"
        case 4:
            return "C\(game.state.paletteIndex + 1)"
        default:
            return "NO"
        }
    }

    private func previous() {
        selection = (selection + labels.count - 1) % labels.count
        GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
    }

    private func accept() {
        switch selection {
        case 0:
            game.setSoundEnabled(!game.state.soundEnabled)
        case 1:
            game.setHapticsEnabled(!game.state.hapticsEnabled)
        case 2:
            game.setGridEnabled(!game.state.gridEnabled)
        case 3:
            game.setNotificationsEnabled(!game.state.notificationsEnabled)
        case 4:
            game.setPalette((game.state.paletteIndex + 1) % 6)
        default:
            selection = 0
        }
        GameAudio.shared.play("sound_select", enabled: game.state.soundEnabled)
    }
}
