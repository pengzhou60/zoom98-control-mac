import SwiftUI

@main
struct Zoom98MacApp: App {
    @StateObject private var controller = KeyboardController()
    @StateObject private var bleController = BLEController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller, bleController: bleController)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
