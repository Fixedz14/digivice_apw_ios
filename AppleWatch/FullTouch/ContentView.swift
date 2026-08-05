import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameModel

    private var accent: Color {
        DetectorPalette.accent(for: game.state.paletteIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Group {
                switch game.screen {
                case .boot:
                    ClassicBootView()
                case .characterSelect:
                    ClassicCharacterSelectView()
                case .tutorial:
                    ClassicTutorialView()
                case .home:
                    ClassicHomeView()
                case .stats:
                    ClassicQuickStatsView()
                case .mainMenu:
                    ClassicMainMenuView()
                case .map:
                    ClassicMapView()
                case .status:
                    ClassicStatusSelectorView()
                case .spirits:
                    ClassicSpiritsView()
                case .camp:
                    ClassicCampView()
                case .connect:
                    ClassicConnectMenuView()
                case .extraMenu:
                    ClassicExtraMenuView()
                case .database:
                    ClassicDatabaseView()
                case .codeScanner:
                    ClassicCodeScannerView()
                case .games:
                    ClassicGamesMenuView()
                case .digiDigit, .digiShip:
                    MiniGameView()
                case .digiStorm:
                    ClassicDigiStormView()
                case .tv:
                    ClassicTVView()
                case .battle, .capture:
                    BattleView()
                case .connectBattle:
                    ClassicConnectBattleView()
                case .connectSend:
                    ClassicConnectSendView()
                case .ending:
                    ClassicEndingView()
                case .settings:
                    ClassicSettingsView()
                }
            }
            .ignoresSafeArea()
            .persistentSystemOverlays(.hidden)

            if let bonus = game.bonusPresentation {
                ClassicBonusEventView(presentation: bonus)
                    .zIndex(100)
            }
        }
        .tint(accent)
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.55)
                .onEnded { _ in
                    game.goBack()
                },
            including: usesRootBackGesture ? .all : .none
        )
    }

    private var usesRootBackGesture: Bool {
        guard game.bonusPresentation == nil else { return false }
        return switch game.screen {
        case .digiDigit,
             .digiShip,
             .connectBattle,
             .connectSend:
            true
        default:
            false
        }
    }
}

private struct TutorialView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openingStartedAt = Date()
    @State private var openingAudioTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("SYSTEM CALIBRATION")
                    .font(.system(size: 12, weight: .black, design: .monospaced))

                DetectorScreen(
                    content: {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                            GeometryReader { geometry in
                                openingStage(
                                    elapsed: max(
                                        0,
                                        timeline.date.timeIntervalSince(openingStartedAt)
                                    ),
                                    size: geometry.size
                                )
                            }
                        }
                    },
                    accent: DetectorPalette.accent(for: game.state.paletteIndex),
                    showGrid: game.state.gridEnabled
                )
                .frame(height: 122)

                Text("WALK • DETECT • SCAN • BATTLE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .multilineTextAlignment(.center)
                Text("100 STEPS = +1 D‑POWER\n500 STEPS = NEW SIGNAL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)

                Button("ENTER DIGITAL WORLD") {
                    game.completeTutorial()
                }
                .buttonStyle(DetectorButtonStyle(tint: .green))
            }
        }
        .onAppear {
            #if DEBUG
            let isOpeningQA = ProcessInfo.processInfo.arguments.contains(
                "-qa-opening"
            )
            openingStartedAt = Date().addingTimeInterval(isOpeningQA ? 10 : 0)
            #else
            openingStartedAt = Date()
            #endif
            playOpeningAudio()
        }
        .onDisappear {
            openingAudioTask?.cancel()
            openingAudioTask = nil
            GameAudio.shared.stop()
        }
    }

    @ViewBuilder
    private func openingStage(elapsed rawElapsed: TimeInterval, size: CGSize) -> some View {
        let elapsed = min(4.2, rawElapsed)
        let starter = game.state.docks.first.flatMap { id in
            game.catalog.digimon.first(where: { $0.id == id })
        }
        let spirit = game.catalog.digimon.first(
            where: { $0.id == game.currentCharacter.humanSpiritID }
        )

        ZStack {
            if elapsed < 0.60 {
                let progress = reduceMotion ? 0.50 : elapsed / 0.60
                GameSprite(
                    resource: "spr_train_trail_dtector",
                    frame: Int(elapsed / 0.10) % 3,
                    size: 116
                )
                GameSprite(
                    resource: "spr_train_dtector",
                    frame: Int(elapsed / 0.12) % 5,
                    size: 108
                )
                .position(
                    x: size.width * CGFloat(0.16 + progress * 0.68),
                    y: size.height * 0.47
                )
            } else if elapsed < 1.00 {
                let progress = reduceMotion ? 1 : (elapsed - 0.60) / 0.40
                GameSprite(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: Int(elapsed / 0.12) % 2,
                    size: 70
                )
                .position(
                    x: size.width * CGFloat(0.18 + progress * 0.32),
                    y: size.height * 0.52
                )
            } else if elapsed < 1.50 {
                if let starter {
                    GameSprite(
                        resource: starter.sprite,
                        frame: Int(elapsed / 0.14) % 2,
                        size: 70
                    )
                }
                GameSprite(
                    resource: "spr_energy_dtector",
                    frame: Int(elapsed / 0.05) % 12,
                    size: 82
                )
            } else if elapsed < 2.10 {
                GameSprite(
                    resource: "spr_spirits_dtector",
                    frame: max(
                        0,
                        min(11, game.currentCharacter.humanSpiritID - 100)
                    ),
                    size: 106
                )
                .offset(
                    y: reduceMotion
                        ? 0
                        : CGFloat(max(0, 2.10 - elapsed) * -28)
                )
                GameSprite(resource: "spr_spirit_stand_dtector", size: 106)
            } else if elapsed < 3.10 {
                GameSprite(
                    resource: "\(game.currentCharacter.sprite)_spirit",
                    size: 66
                )
                .opacity(Int(elapsed / 0.12).isMultiple(of: 2) ? 1 : 0.30)
                GameSprite(
                    resource: "spr_summon_dtector",
                    frame: 5,
                    size: 108
                )
                if let spirit {
                    GameSprite(
                        resource: spirit.sprite,
                        frame: 4,
                        size: 76
                    )
                    .opacity(min(1, (elapsed - 2.10) * 1.8))
                }
            } else if elapsed < 3.70 {
                if let starter {
                    GameSprite(resource: starter.sprite, frame: 0, size: 70)
                }
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: Int((elapsed - 3.10) / 0.12) % 2,
                    size: 110
                )
            } else {
                GameSprite(
                    resource: "spr_dtector_catch_dtector",
                    frame: Int((elapsed - 3.70) / 0.16) % 2,
                    size: 104
                )
            }

            VStack {
                Spacer()
                Text(openingCaption(elapsed))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .padding(.horizontal, 4)
                    .background(DetectorPalette.screenBright.opacity(0.80))
            }
            .padding(.bottom, 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Digital World calibration animation")
        .accessibilityValue(openingCaption(elapsed))
    }

    private func openingCaption(_ elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<0.60: "TRAILMON LINK"
        case ..<1.00: "TAMER DETECTED"
        case ..<1.50: "PARTNER DATA"
        case ..<2.10: "SPIRIT SCAN"
        case ..<3.10: "DIGIVOLUTION"
        case ..<3.70: "DIGITIZE"
        default: "D‑TECTOR READY"
        }
    }

    private func playOpeningAudio() {
        openingAudioTask?.cancel()
        GameAudio.shared.play(
            "sound_summon_digimon_dtector",
            enabled: game.state.soundEnabled
        )
        openingAudioTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard !Task.isCancelled, game.screen == .tutorial else { return }
            GameAudio.shared.play(
                "sound_evo_dtector",
                enabled: game.state.soundEnabled
            )
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, game.screen == .tutorial else { return }
            GameAudio.shared.play(
                "sound_catch_dtector",
                enabled: game.state.soundEnabled
            )
        }
    }
}

private struct BootView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate: Date?
    @State private var startTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            DetectorScreen(
                content: {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                        GeometryReader { geometry in
                            bootStage(at: timeline.date, size: geometry.size)
                        }
                    }
                    .frame(height: 126)
                },
                accent: DetectorPalette.accent(for: game.state.paletteIndex),
                showGrid: game.state.gridEnabled
            )
            Text("watchOS EDITION")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.secondary)
            Button(startDate == nil ? "SYSTEM START" : "INITIALIZING…") {
                startSystem()
            }
            .buttonStyle(DetectorButtonStyle(tint: DetectorPalette.accent(for: game.state.paletteIndex)))
            .disabled(startDate != nil)
        }
        .onDisappear {
            startTask?.cancel()
            startTask = nil
            GameAudio.shared.stop()
        }
    }

    @ViewBuilder
    private func bootStage(at date: Date, size: CGSize) -> some View {
        let idleTime = date.timeIntervalSinceReferenceDate
        let elapsed = startDate.map { max(0, date.timeIntervalSince($0)) }

        ZStack {
            if let elapsed {
                if elapsed < 0.36 {
                    scanLayer(time: elapsed, size: size)
                } else if elapsed < 0.82 {
                    let frames = [0, 1, 2, 1]
                    let index = min(3, Int((elapsed - 0.36) / 0.115))
                    GameSprite(
                        resource: "spr_summon_dtector",
                        frame: frames[index],
                        size: 124
                    )
                    .position(x: size.width * 0.50, y: size.height * 0.46)
                } else {
                    GameSprite(
                        resource: "spr_catch_dtector",
                        frame: Int((elapsed - 0.82) / 0.12) % 2,
                        size: 124
                    )
                    .position(x: size.width * 0.50, y: size.height * 0.46)
                }
            } else {
                scanLayer(time: idleTime, size: size)
            }

            VStack(spacing: 1) {
                Spacer()
                Text("D‑TECTOR")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                Text(elapsed == nil ? "DIGITAL SCAN READY" : "SYSTEM LINK")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
            }
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("D-Tector system")
        .accessibilityValue(elapsed == nil ? "Ready" : "Initializing")
    }

    @ViewBuilder
    private func scanLayer(time: TimeInterval, size: CGSize) -> some View {
        let progress = reduceMotion
            ? 0.50
            : time.truncatingRemainder(dividingBy: 1.60) / 1.60

        ZStack {
            GameSprite(resource: "spr_scan_dtector", frame: 4, size: 124)
            GameSprite(resource: "spr_scan_dtector", frame: 3, size: 124)
                .offset(y: size.height * CGFloat(-0.42 + progress * 0.84))
                .opacity(0.82)
        }
        .position(x: size.width * 0.50, y: size.height * 0.46)
    }

    private func startSystem() {
        guard startDate == nil else { return }
        startDate = Date()
        GameAudio.shared.play(
            "sound_event_2",
            enabled: game.state.soundEnabled
        )
        startTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            guard !Task.isCancelled, game.screen == .boot else { return }
            game.navigate(.characterSelect)
        }
    }
}

private struct CharacterSelectView: View {
    @EnvironmentObject private var game: GameModel
    @State private var selection = 0
    @State private var name = "TAMER"

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ScreenHeader(title: "SELECT CHARACTER") {
                    game.navigate(.boot)
                }

                let character = game.catalog.characters[selection]
                DetectorScreen(
                    content: {
                        VStack(spacing: 0) {
                            GameSprite(resource: character.sprite, frame: 0, size: 82)
                            Text(character.name)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                        }
                        .padding(8)
                    },
                    accent: DetectorPalette.accent(for: selection),
                    showGrid: game.state.gridEnabled
                )
                .frame(height: 112)

                Picker("CHARACTER", selection: $selection) {
                    ForEach(Array(game.catalog.characters.prefix(game.state.newGamePlus ? 6 : 5))) { value in
                        Text(value.name).tag(value.id)
                    }
                }
                .labelsHidden()

                TextField("TAMER NAME", text: $name)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)

                Button("CONFIRM") {
                    game.beginNewGame(characterID: selection, playerName: name)
                }
                .buttonStyle(DetectorButtonStyle(tint: DetectorPalette.accent(for: selection)))
            }
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var game: GameModel
    @State private var walkingUntil: Date?

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                StatPill(icon: "figure.walk", value: "\(game.state.steps)")
                Spacer()
                StatPill(icon: "bolt.fill", value: "\(game.state.dPower)")
            }

            DetectorScreen(
                content: {
                    TimelineView(.animation(minimumInterval: 0.12)) { timeline in
                        let isWalking = walkingUntil.map {
                            timeline.date < $0
                        } ?? false
                        let idlePose = Int(
                            timeline.date.timeIntervalSinceReferenceDate * 2
                        ) % 4
                        let frame = isWalking
                            ? Int(
                                timeline.date.timeIntervalSinceReferenceDate
                                    / 0.12
                            ) % 2
                            : idlePose % 2
                        let mirrored = idlePose >= 2
                        VStack(spacing: 1) {
                            HStack {
                                Text(game.currentArea.name)
                                Spacer()
                                Text("LV \(game.state.level)")
                            }
                            .font(.system(size: 9, weight: .black, design: .monospaced))

                            ZStack {
                                GameSprite(
                                    resource: isWalking
                                        ? "\(game.currentCharacter.sprite)_step"
                                        : game.currentCharacter.sprite,
                                    frame: frame,
                                    size: 106
                                )
                                .scaleEffect(
                                    x: !isWalking && mirrored ? -1 : 1,
                                    y: 1
                                )
                                .offset(
                                    x: isWalking
                                        ? CGFloat(
                                            sin(
                                                timeline.date
                                                    .timeIntervalSinceReferenceDate
                                                    * 11
                                            ) * 7
                                        )
                                        : 0
                                )

                                if game.pendingEncounter != nil,
                                   Int(
                                    timeline.date.timeIntervalSinceReferenceDate
                                        * 4
                                   ).isMultiple(of: 2) {
                                    GameSprite(
                                        resource: "spr_alert_dtector",
                                        frame: 0,
                                        size: 112
                                    )
                                    .blendMode(.multiply)
                                }
                            }
                            .frame(maxHeight: .infinity)

                            HStack(spacing: 4) {
                                Text("BOSS")
                                Meter(value: game.areaProgress, color: DetectorPalette.ink)
                                Text("\(game.state.distance)")
                            }
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                        }
                        .padding(8)
                    }
                },
                accent: DetectorPalette.accent(for: game.state.paletteIndex),
                showGrid: game.state.gridEnabled
            )

            if !game.banner.isEmpty {
                Text(game.banner)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(DetectorPalette.accent(for: game.state.paletteIndex))
                    .lineLimit(1)
            }

            if game.state.defeated {
                Text("SYSTEM DOWN • CAMP REQUIRED")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.red)
                Button("RECOVER AT CAMP") {
                    game.navigate(.camp)
                }
                .buttonStyle(DetectorButtonStyle(tint: .red))
            } else if game.pendingEncounter != nil {
                HStack(spacing: 5) {
                    Button(game.pendingEncounter == .battle ? "BATTLE!" : "STORM!") {
                        game.acceptEncounter()
                    }
                    .buttonStyle(CompactDetectorButtonStyle(tint: DetectorPalette.danger))
                    if !(game.pendingEncounter == .battle && game.state.distance == 0) {
                        Button("DELAY") {
                            game.dismissEncounter()
                        }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .gray))
                    }
                }
            } else {
                HStack(spacing: 5) {
                    Button("WALK +50") {
                        game.addSteps(50)
                        walkingUntil = Date().addingTimeInterval(0.82)
                        GameAudio.shared.play(
                            "sound_select",
                            enabled: game.state.soundEnabled
                        )
                    }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .green))
                    Button("MENU") {
                        game.openMainMenu()
                    }
                    .buttonStyle(CompactDetectorButtonStyle(tint: DetectorPalette.accent(for: game.state.paletteIndex)))
                    Button("EXTRA") {
                        game.openExtraMenu()
                    }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .cyan))
                }
            }
        }
    }
}

private struct MainMenuView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "MAIN MENU") { game.goHome() }
                menuButton("MAP", "map.fill", .map, .green)
                menuButton("STATUS", "chart.bar.fill", .status, .white)
                menuButton("SPIRITS", "flame.fill", .spirits, .orange)
                menuButton("CAMP", "person.3.fill", .camp, .cyan)
                menuButton("CONNECT", "link", .connect, .purple)
            }
        }
    }

    private func menuButton(
        _ title: String,
        _ icon: String,
        _ destination: FullGameScreen,
        _ tint: Color
    ) -> some View {
        Button {
            game.navigate(destination)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(DetectorButtonStyle(tint: tint))
    }
}

private struct ExtraMenuView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "EXTRA") { game.goHome() }
                extraButton("DATABASE", "square.grid.2x2.fill", .database, .cyan)
                extraButton("DIGI-CODE", "barcode.viewfinder", .codeScanner, .orange)
                extraButton("GAMES", "gamecontroller.fill", .games, .green)
                extraButton("TV", "tv.fill", .tv, .purple)
                extraButton("SETTINGS", "gearshape.fill", .settings, .white)
            }
        }
    }

    private func extraButton(
        _ title: String,
        _ icon: String,
        _ destination: FullGameScreen,
        _ tint: Color
    ) -> some View {
        Button {
            game.navigate(destination)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(DetectorButtonStyle(tint: tint))
    }
}

private struct MapView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "DIGITAL WORLD") { game.navigate(.mainMenu) }
                DetectorScreen(
                    content: {
                        TimelineView(.animation(minimumInterval: 0.20)) { timeline in
                            let pulse = Int(
                                timeline.date.timeIntervalSinceReferenceDate / 0.20
                            ).isMultiple(of: 2)
                            ZStack {
                                if game.currentArea.id == 12 {
                                    GameSprite(
                                        resource: "spr_map_5_dtector",
                                        frame: pulse ? 1 : 2,
                                        size: 106
                                    )
                                } else {
                                    GameSprite(
                                        resource: "spr_map_dtector",
                                        frame: max(0, min(3, game.currentArea.map)),
                                        size: 106
                                    )
                                    GameSprite(
                                        resource: "spr_map_cover_dtector",
                                        frame: pulse ? 0 : 1,
                                        size: 106
                                    )
                                    .opacity(0.46)
                                    GameSprite(
                                        resource: "spr_area_dtector",
                                        frame: max(0, min(11, game.currentArea.id)),
                                        size: 106
                                    )
                                    .opacity(pulse ? 1 : 0.72)
                                }

                                VStack {
                                    Spacer()
                                    Text(game.currentArea.name)
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .background(DetectorPalette.screenBright.opacity(0.82))
                                }
                                .padding(.bottom, 2)
                            }
                        }
                        .frame(height: 86)
                    },
                    accent: .green,
                    showGrid: game.state.gridEnabled
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Digital World map")
                .accessibilityValue(game.currentArea.name)

                ForEach(game.catalog.areas) { area in
                    let cleared = game.state.areaCleared.indices.contains(area.id)
                        && game.state.areaCleared[area.id]
                    let available = game.availableAreas.contains(where: { $0.id == area.id })
                    Button {
                        game.selectArea(area.id)
                    } label: {
                        HStack {
                            Image(systemName: cleared ? "checkmark.seal.fill" : available ? "location.fill" : "lock.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(area.name)
                                Text("\(area.distance) STEPS")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                            }
                            Spacer()
                            if game.state.currentArea == area.id {
                                Text("NOW")
                            }
                        }
                    }
                    .buttonStyle(CompactDetectorButtonStyle(
                        tint: cleared ? .gray : available ? .green : Color.white.opacity(0.55)
                    ))
                    .disabled(!available)
                }
            }
        }
    }
}

private struct StatusView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "STATUS") { game.navigate(.mainMenu) }
                GameSprite(resource: game.currentCharacter.sprite, frame: 0, size: 66)
                Text("\(game.state.playerName) / \(game.currentCharacter.name)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                DataRow(label: "LEVEL", value: "\(game.state.level)")
                DataRow(label: "D-POWER", value: "\(game.state.dPower)/99")
                DataRow(label: "HP BASE", value: "\(game.currentCharacterStats.hp)")
                DataRow(label: "SPIRIT", value: "\(game.currentCharacterStats.spirit)")
                DataRow(label: "STAMINA", value: "\(game.currentCharacterStats.stamina)")
                DataRow(label: "SKILL", value: "\(game.currentCharacterStats.skill)")
                DataRow(label: "BATTLES", value: "\(game.state.battles)")
                DataRow(label: "WINS", value: "\(game.state.wins) • \(game.winRate)%")
                DataRow(label: "DATABASE", value: "\(game.unlockedDigimon.count)/\(game.catalog.digimon.count)")
                DataRow(label: "RUNS", value: "\(game.state.completedRuns)")
            }
            .padding(.horizontal, 6)
        }
    }
}

private struct SpiritsView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ScreenHeader(title: "SPIRITS") { game.navigate(.mainMenu) }
                ForEach(game.catalog.spirits) { spirit in
                    let obtained = game.state.spiritsObtained.indices.contains(spirit.id)
                        && game.state.spiritsObtained[spirit.id]
                    let unlocked = game.state.spiritsUnlocked.indices.contains(spirit.id)
                        && game.state.spiritsUnlocked[spirit.id]
                    let digimon = game.catalog.digimon.first(where: { $0.id == spirit.digimonID })
                    HStack(spacing: 6) {
                        if let digimon {
                            GameSprite(resource: digimon.sprite, frame: 0, size: 42, locked: !unlocked)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(unlocked ? (digimon?.displayName ?? "SPIRIT") : "UNKNOWN SPIRIT")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                            Text("\(spirit.kind.uppercased()) • \(game.catalog.characters[spirit.ownerCharacterID].name)")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                        Image(systemName: obtained ? "checkmark.circle.fill" : unlocked ? "arrow.clockwise.circle" : "lock.fill")
                            .foregroundStyle(obtained ? .green : .secondary)
                    }
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.09)))
                }

                Text("ANCIENT FORMS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                ForEach(game.catalog.characters) { character in
                    HStack {
                        Text(character.name)
                        Spacer()
                        Text(game.canUseAncient(character.id) ? "READY" : "LOCKED")
                            .foregroundStyle(game.canUseAncient(character.id) ? .green : .secondary)
                    }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                }
            }
        }
    }
}

private struct CampView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "CAMP") { game.goHome() }
                if game.state.defeated {
                    DetectorScreen(
                        content: {
                            VStack(spacing: 5) {
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 31))
                                Text("SYSTEM RECOVERY")
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                            }
                        },
                        accent: .red,
                        showGrid: game.state.gridEnabled
                    )
                    Button("RECOVER NOW") {
                        game.recoverAtCamp()
                    }
                    .buttonStyle(DetectorButtonStyle(tint: .green))
                }
                Text("ACTIVE CHARACTER")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                ForEach(game.catalog.characters) { character in
                    let unlocked = game.state.charactersUnlocked.indices.contains(character.id)
                        && game.state.charactersUnlocked[character.id]
                    let inParty = game.state.characterParty.indices.contains(character.id)
                        && game.state.characterParty[character.id]
                    Button {
                        game.selectCharacter(character.id)
                    } label: {
                        HStack {
                            GameSprite(resource: character.sprite, frame: 0, size: 32, locked: !unlocked)
                            Text(unlocked ? character.name : "LOCKED")
                            Spacer()
                            if !inParty && unlocked {
                                Text("MISSING")
                                    .font(.system(size: 7, weight: .black, design: .monospaced))
                            } else if game.state.currentCharacter == character.id {
                                Image(systemName: "star.fill")
                            }
                        }
                    }
                    .buttonStyle(CompactDetectorButtonStyle(
                        tint: game.state.currentCharacter == character.id ? .orange : .white
                    ))
                    .disabled(!unlocked || !inParty)
                }

                Text("DIGIMON DOCKS • TAP TO CYCLE")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                ForEach(game.state.docks.indices, id: \.self) { slot in
                    let id = game.state.docks[slot]
                    let digimon = game.catalog.digimon.first(where: { $0.id == id })
                    Button {
                        game.cycleDock(slot)
                    } label: {
                        HStack {
                            Text("D\(slot + 1)")
                            if let digimon {
                                GameSprite(resource: digimon.sprite, frame: 0, size: 30)
                                Text(digimon.displayName)
                            } else {
                                Text("EMPTY")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(CompactDetectorButtonStyle(tint: .cyan))
                }

                HStack(spacing: 5) {
                    Button("AUTO") { game.autoFillDocks() }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .green))
                    Button("CLEAR") { game.clearDocks() }
                        .buttonStyle(CompactDetectorButtonStyle(tint: .gray))
                }
            }
        }
    }
}

private struct ConnectView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ScreenHeader(title: "OFFLINE CONNECT") { game.navigate(.mainMenu) }
                Text("WATCH FORMAT • NOT DMOG/SEA")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("YOUR OFFLINE CODE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                Text(game.outgoingLinkCode)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.cyan)

                TextField("14-HEX OPPONENT CODE", text: $game.connectCodeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("IMPORT OFFLINE CODE") {
                    game.importLinkCode()
                }
                .buttonStyle(DetectorButtonStyle(tint: .purple))

                Button("OFFLINE TRAINING") {
                    game.quickLinkBattle()
                }
                .buttonStyle(DetectorButtonStyle(tint: .green))

                Button("SEND / RECEIVE DATA") {
                    game.navigate(.connectSend)
                }
                .buttonStyle(DetectorButtonStyle(tint: .cyan))
                DataRow(label: "LINK WINS", value: "\(game.state.connectWins)")
                if !game.connectMessage.isEmpty {
                    Text(game.connectMessage)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                }
            }
        }
    }
}

private struct DatabaseView: View {
    @EnvironmentObject private var game: GameModel
    private let filters = ["all", "rookie", "champion", "ultimate", "mega", "boss", "spirit", "ancient", "final_boss"]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ScreenHeader(title: "DATABASE") { game.navigate(.extraMenu) }
                Picker("TYPE", selection: $game.databaseFilter) {
                    ForEach(filters, id: \.self) { value in
                        Text(value.replacingOccurrences(of: "_", with: " ").uppercased()).tag(value)
                    }
                }
                .labelsHidden()

                Text("\(game.unlockedDigimon.count) / \(game.catalog.digimon.count)")
                    .font(.system(size: 9, weight: .black, design: .monospaced))

                ForEach(game.visibleDatabase) { digimon in
                    let unlocked = game.state.digimonUnlocked.indices.contains(digimon.id)
                        && game.state.digimonUnlocked[digimon.id]
                    HStack(spacing: 6) {
                        GameSprite(resource: digimon.sprite, frame: 0, size: 39, locked: !unlocked)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(unlocked ? digimon.displayName : "NO.\(digimon.number) ?????")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                            if unlocked {
                                Text("LV\(digimon.level) • \(digimon.type.uppercased())")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                Text("HP\(digimon.hp) E\(digimon.energy) C\(digimon.crunch) A\(digimon.ability)")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                            }
                        }
                        Spacer()
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.08)))
                }
            }
        }
    }
}

private struct CodeScannerView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        VStack(spacing: 9) {
            ScreenHeader(title: "DIGI-CODE") { game.navigate(.extraMenu) }
            DetectorScreen(
                content: {
                    VStack(spacing: 5) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 38))
                        Text("ENTER 5 CHARACTERS")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                },
                accent: .orange,
                showGrid: game.state.gridEnabled
            )
            TextField("ABCDE", text: $game.codeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
            Button("DIGITIZE") { game.redeemCode() }
                .buttonStyle(DetectorButtonStyle(tint: .orange))
            if !game.banner.isEmpty {
                Text(game.banner)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct GamesView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ScreenHeader(title: "GAMES") { game.navigate(.extraMenu) }
                Button {
                    game.startMiniGame(.digiDigit)
                } label: {
                    VStack {
                        Label("SCAN BREAK", systemImage: "waveform.path.ecg")
                        Text("SCAN BREAK • CLEAR \(game.state.digiDigitHighScore)")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                }
                .buttonStyle(DetectorButtonStyle(tint: .orange))

                Button {
                    game.startMiniGame(.digiShip)
                } label: {
                    VStack {
                        Label("DIGI-SHIP", systemImage: "paperplane.fill")
                        Text("BEST \(game.state.digiShipHighScore)")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                    }
                }
                .buttonStyle(DetectorButtonStyle(tint: .cyan))
            }
        }
    }
}

private struct TVView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: SignalPhase = .idle
    @State private var phaseStartedAt = Date()
    @State private var receptionToken: UUID?
    @State private var receptionTask: Task<Void, Never>?

    private enum SignalPhase {
        case idle
        case tuning
        case signal
        case locked
    }

    var body: some View {
        VStack(spacing: 9) {
            ScreenHeader(title: "DIGITAL TV") { game.navigate(.extraMenu) }
            DetectorScreen(
                content: {
                    VStack(spacing: 4) {
                        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                            GameSprite(
                                resource: "spr_tv_dtector",
                                frame: spriteFrame(at: timeline.date),
                                size: 78
                            )
                        }
                        Text(signalStatus)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                },
                accent: .purple,
                showGrid: game.state.gridEnabled
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Digital TV signal")
            .accessibilityValue(signalStatus)

            Button {
                beginReception()
            } label: {
                Text(receptionButtonLabel)
            }
            .buttonStyle(DetectorButtonStyle(tint: .purple))
            .disabled(isReceiving)
            .accessibilityHint(
                isReceiving
                    ? "Signal reception is in progress"
                    : "Scans for a Digital TV reward"
            )

            Text(game.banner.isEmpty ? "RANDOM DATA OR BONUS" : game.banner)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .multilineTextAlignment(.center)
            DataRow(label: "SIGNALS", value: "\(game.state.tvRewards)")
        }
        .onDisappear {
            cancelReception()
        }
    }

    private var isReceiving: Bool {
        receptionToken != nil
    }

    private var signalStatus: String {
        switch phase {
        case .idle:
            "DATA BROADCAST"
        case .tuning:
            "TUNING DATA"
        case .signal:
            "LOCKING SIGNAL"
        case .locked:
            "SIGNAL LOCKED"
        }
    }

    private var receptionButtonLabel: String {
        switch phase {
        case .idle:
            "RECEIVE SIGNAL"
        case .tuning:
            "TUNING…"
        case .signal, .locked:
            "LOCKING…"
        }
    }

    private func spriteFrame(at date: Date) -> Int {
        if reduceMotion {
            switch phase {
            case .idle:
                return 0
            case .tuning:
                return 4
            case .signal:
                return 6
            case .locked:
                return 7
            }
        }

        let elapsed = max(0, date.timeIntervalSince(phaseStartedAt))
        switch phase {
        case .idle:
            return Int(elapsed / 0.5).isMultiple(of: 2) ? 0 : 1
        case .tuning:
            return 4 + Int(elapsed / 0.125) % 2
        case .signal:
            return 6 + Int(elapsed / 0.15) % 2
        case .locked:
            return 7
        }
    }

    private func beginReception() {
        guard receptionToken == nil else { return }

        let token = UUID()
        receptionToken = token
        GameAudio.shared.play(
            "sound_event_2",
            enabled: game.state.soundEnabled
        )
        setPhase(.tuning)
        receptionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard receptionToken == token, game.screen == .tv else { return }
            setPhase(.signal)

            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            guard receptionToken == token, game.screen == .tv else { return }
            setPhase(.locked)

            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard receptionToken == token, game.screen == .tv else { return }

            receptionToken = nil
            receptionTask = nil
            setPhase(.idle)
            game.activateTV()
        }
    }

    private func setPhase(_ newPhase: SignalPhase) {
        phase = newPhase
        phaseStartedAt = Date()
    }

    private func cancelReception() {
        receptionTask?.cancel()
        receptionTask = nil
        receptionToken = nil
        setPhase(.idle)
        GameAudio.shared.stop()
    }
}

private struct ConnectSendView: View {
    @EnvironmentObject private var game: GameModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "DATA SEND") { game.navigate(.connect) }
                ForEach(game.state.docks.indices, id: \.self) { slot in
                    let id = game.state.docks[slot]
                    if let digimon = game.catalog.digimon.first(where: { $0.id == id }) {
                        HStack {
                            GameSprite(resource: digimon.sprite, frame: 0, size: 37)
                            VStack(alignment: .leading) {
                                Text(digimon.displayName)
                                Text(digimon.code ?? "NO CODE")
                                    .foregroundStyle(.cyan)
                            }
                            Spacer()
                        }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    }
                }
                TextField("RECEIVE 5-CHAR CODE", text: $game.codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("RECEIVE DATA") { game.redeemCode() }
                    .buttonStyle(DetectorButtonStyle(tint: .cyan))
                if !game.banner.isEmpty {
                    Text(game.banner)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                }
            }
        }
        .onAppear {
            GameAudio.shared.play(
                "sound_connect",
                enabled: game.state.soundEnabled
            )
        }
    }
}

private struct EndingView: View {
    @EnvironmentObject private var game: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var vignetteStartedAt = Date()

    private enum EndingRoute {
        case koichi
        case lucemon
    }

    private struct EndingSample {
        let beat: Int
        let progress: Double
    }

    var body: some View {
        VStack(spacing: 7) {
            DetectorScreen(
                content: {
                    TimelineView(
                        .animation(
                            minimumInterval: reduceMotion ? 0.5 : 1.0 / 12.0
                        )
                    ) { timeline in
                        let route = endingRoute
                        let sample = endingSample(
                            at: timeline.date,
                            route: route
                        )

                        VStack(spacing: 2) {
                            endingScene(route: route, sample: sample)
                                .frame(height: 72)

                            Text("ADVENTURE CLEAR")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                            Text(routeTitle(for: route))
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                            Text(beatDescription(route: route, beat: sample.beat))
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                            Text(game.endingMessage)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Adventure clear")
                        .accessibilityValue(
                            "\(routeTitle(for: route)). "
                                + "\(beatDescription(route: route, beat: sample.beat)). "
                                + game.endingMessage.replacingOccurrences(
                                    of: "\n",
                                    with: ", "
                                )
                        )
                    }
                    .padding(6)
                },
                accent: .yellow,
                showGrid: game.state.gridEnabled
            )
            Button("NEW GAME+") { game.finishEnding() }
                .buttonStyle(DetectorButtonStyle(tint: .yellow))
                .accessibilityHint("Starts New Game Plus")
        }
        .onAppear {
            vignetteStartedAt = Date()
            playEndingSound()
        }
        .onDisappear {
            GameAudio.shared.stop()
        }
    }

    private var endingRoute: EndingRoute {
        game.endingMessage
            .localizedCaseInsensitiveContains("LUCEMON")
            ? .lucemon
            : .koichi
    }

    private func endingSample(
        at date: Date,
        route: EndingRoute
    ) -> EndingSample {
        let duration = route == .koichi ? 6.0 : 4.2
        let elapsed = max(0, date.timeIntervalSince(vignetteStartedAt))
            .truncatingRemainder(dividingBy: duration)
        let beatDuration = duration / 6
        let beat = min(5, Int(elapsed / beatDuration))
        let progress = (elapsed - Double(beat) * beatDuration) / beatDuration
        return EndingSample(beat: beat, progress: progress)
    }

    @ViewBuilder
    private func endingScene(
        route: EndingRoute,
        sample: EndingSample
    ) -> some View {
        switch route {
        case .koichi:
            koichiScene(sample: sample)
        case .lucemon:
            lucemonScene(sample: sample)
        }
    }

    @ViewBuilder
    private func koichiScene(sample: EndingSample) -> some View {
        switch sample.beat {
        case 0:
            GameSprite(
                resource: "spr_ancientsphinxmon_dtector",
                frame: alternatingFrame(0, 1, sample: sample),
                size: 66
            )
            .opacity(
                reduceMotion
                    ? 1
                    : max(0.35, 1 - sample.progress * 0.55)
            )

        case 1:
            ZStack {
                GameSprite(
                    resource: "spr_spirits_dtector",
                    frame: 10,
                    size: 44
                )
                .offset(
                    x: -18,
                    y: reduceMotion ? 0 : -24 + CGFloat(sample.progress) * 24
                )
                GameSprite(
                    resource: "spr_spirits_dtector",
                    frame: 11,
                    size: 44
                )
                .offset(
                    x: 18,
                    y: reduceMotion ? 0 : -24 + CGFloat(sample.progress) * 24
                )
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: 1,
                    size: 82
                )
            }

        case 2:
            ZStack {
                GameSprite(
                    resource: "spr_ancient_dtector",
                    frame: alternatingFrame(0, 1, sample: sample),
                    size: 60
                )
                GameSprite(
                    resource: "spr_ancient_cover_dtector",
                    frame: reduceMotion
                        ? 3
                        : min(3, Int(sample.progress * 4)),
                    size: 82
                )
            }

        case 3:
            GameSprite(
                resource: sample.progress < 0.5
                    ? "spr_koichi_defeat"
                    : "spr_koichi",
                frame: 0,
                size: 58
            )

        case 4:
            ZStack {
                GameSprite(
                    resource: "\(game.currentCharacter.sprite)_step",
                    frame: alternatingFrame(0, 1, sample: sample),
                    size: 52
                )
                .offset(
                    x: reduceMotion
                        ? -25
                        : -48 + CGFloat(sample.progress) * 23
                )
                GameSprite(
                    resource: "spr_koichi_step",
                    frame: alternatingFrame(0, 1, sample: sample),
                    size: 52
                )
                .scaleEffect(x: -1, y: 1)
                .offset(
                    x: reduceMotion
                        ? 25
                        : 48 - CGFloat(sample.progress) * 23
                )
            }

        default:
            ZStack {
                GameSprite(
                    resource: "\(game.currentCharacter.sprite)_happy",
                    frame: 0,
                    size: 52
                )
                .offset(x: -25)
                GameSprite(
                    resource: "spr_koichi_happy",
                    frame: 0,
                    size: 52
                )
                .scaleEffect(x: -1, y: 1)
                .offset(x: 25)
            }
        }
    }

    @ViewBuilder
    private func lucemonScene(sample: EndingSample) -> some View {
        switch sample.beat {
        case 0:
            GameSprite(
                resource: "spr_lucemon_dtector",
                frame: alternatingFrame(0, 1, sample: sample),
                size: 66
            )

        case 1:
            ZStack {
                GameSprite(
                    resource: "spr_lucemon_dtector",
                    frame: 0,
                    size: 66
                )
                GameSprite(
                    resource: "spr_capture_ball_dtector",
                    frame: 0,
                    size: 46
                )
                .offset(
                    y: reduceMotion
                        ? -10
                        : -36 + CGFloat(sample.progress) * 26
                )
            }

        case 2:
            ZStack {
                GameSprite(
                    resource: "spr_lucemon_dtector",
                    frame: alternatingFrame(0, 4, sample: sample),
                    size: 66
                )
                GameSprite(
                    resource: "spr_capture_ball_dtector",
                    frame: 0,
                    size: 46
                )
                .offset(y: -10)
            }

        case 3:
            ZStack {
                GameSprite(
                    resource: "spr_lucemon_dtector",
                    frame: 4,
                    size: 66
                )
                .opacity(
                    reduceMotion ? 0.45 : max(0, 1 - sample.progress)
                )
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: 1,
                    size: 82
                )
                .offset(
                    y: reduceMotion
                        ? 0
                        : -18 + CGFloat(sample.progress) * 18
                )
            }

        case 4:
            ZStack {
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: sample.progress < 0.5 ? 1 : 0,
                    size: 82
                )
                GameSprite(
                    resource: "spr_capture_ball_dtector",
                    frame: 0,
                    size: 46
                )
            }

        default:
            ZStack {
                GameSprite(
                    resource: "spr_catch_dtector",
                    frame: 0,
                    size: 82
                )
                GameSprite(
                    resource: "spr_capture_ball_dtector",
                    frame: 0,
                    size: 46
                )
                .offset(
                    y: reduceMotion
                        ? -14
                        : -8 - CGFloat(sample.progress) * 18
                )
            }
        }
    }

    private func alternatingFrame(
        _ first: Int,
        _ second: Int,
        sample: EndingSample
    ) -> Int {
        guard !reduceMotion else { return first }
        return Int(sample.progress * 4).isMultiple(of: 2)
            ? first
            : second
    }

    private func routeTitle(for route: EndingRoute) -> String {
        switch route {
        case .koichi:
            "DARKNESS RESTORED"
        case .lucemon:
            "LUCEMON SEALED"
        }
    }

    private func beatDescription(
        route: EndingRoute,
        beat: Int
    ) -> String {
        switch route {
        case .koichi:
            [
                "ANCIENT SPIRIT RELEASE",
                "DARKNESS SPIRITS RETURN",
                "SPIRIT LINK RESTORED",
                "KOICHI AWAKENS",
                "REUNION",
                "TOGETHER AGAIN"
            ][min(5, max(0, beat))]
        case .lucemon:
            [
                "FINAL SIGNAL",
                "CAPTURE LOCK",
                "LUCEMON SEALED",
                "DIGITIZE",
                "DATA CAPTURED",
                "NEW WORLD UNLOCKED"
            ][min(5, max(0, beat))]
        }
    }

    private func playEndingSound() {
        let sound: String
        switch endingRoute {
        case .koichi:
            sound = "sound_evo_ancient_dtector"
        case .lucemon:
            sound = "sound_catch_dtector"
        }
        GameAudio.shared.play(sound, enabled: game.state.soundEnabled)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var game: GameModel
    @State private var showReset = false

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                ScreenHeader(title: "SETTINGS") { game.navigate(.extraMenu) }
                Toggle("SOUND", isOn: Binding(
                    get: { game.state.soundEnabled },
                    set: { game.setSoundEnabled($0) }
                ))
                Toggle("HAPTICS", isOn: Binding(
                    get: { game.state.hapticsEnabled },
                    set: { game.setHapticsEnabled($0) }
                ))
                Toggle("PIXEL GRID", isOn: Binding(
                    get: { game.state.gridEnabled },
                    set: { game.setGridEnabled($0) }
                ))
                Toggle("NOTIFICATIONS", isOn: Binding(
                    get: { game.state.notificationsEnabled },
                    set: { game.setNotificationsEnabled($0) }
                ))
                Picker("COLOR", selection: Binding(
                    get: { game.state.paletteIndex },
                    set: { game.setPalette($0) }
                )) {
                    Text("RED").tag(0)
                    Text("BLUE").tag(1)
                    Text("ORANGE").tag(2)
                    Text("PURPLE").tag(3)
                    Text("GREEN").tag(4)
                    Text("MONO").tag(5)
                }
                Button("RESET SAVE") {
                    showReset = true
                }
                .buttonStyle(DetectorButtonStyle(tint: DetectorPalette.danger))
                .confirmationDialog("ลบเซฟ D‑Tector ทั้งหมดหรือไม่?", isPresented: $showReset) {
                    Button("ลบเซฟ", role: .destructive) { game.resetGame() }
                    Button("ยกเลิก", role: .cancel) {}
                }
                Text("V2.0.0 • SCHEMA \(FullSaveState.currentSchema) • \(game.catalog.digimon.count) DIGIMON")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
