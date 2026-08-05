import SwiftUI

@main
struct DTectorWatchApp: App {
    @StateObject private var game = UnityDTGameModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            UnityDTRootView()
                .environmentObject(game)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        game.save()
                    }
                }
        }
    }
}
