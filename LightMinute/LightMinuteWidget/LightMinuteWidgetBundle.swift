import WidgetKit
import SwiftUI
import CoreText

@main
struct LightMinuteWidgetBundle: WidgetBundle {
    init() {
        if let url = Bundle.main.url(forResource: "PressStart2P-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Widget {
        RestLiveActivityWidget()
    }
}
