import SwiftUI
import CoreText

@main
struct LightMinuteApp: App {
    /// Owned here rather than in `ContentView` so a link arriving while the app
    /// is cold reaches the same timer the screen is showing.
    @StateObject private var vm = TimerViewModel()

    init() {
        if let url = Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                // `com.lightminute.app:/focus?taskId=…` — opening a task in
                // Light Week and focusing on it here. The sign-in callback uses
                // the same scheme but never arrives this way:
                // `ASWebAuthenticationSession` intercepts its own redirect.
                .onOpenURL { vm.open($0) }
        }
    }
}
