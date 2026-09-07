import AppKit
import SwiftUI

@main
struct TinyStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Panel(store: Store.shared)
        } label: {
            BarLabel()
        }
        .menuBarExtraStyle(.window)
        Settings {
            ConfigWindow(store: Store.shared)
        }
    }
}
