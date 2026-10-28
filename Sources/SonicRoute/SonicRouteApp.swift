import SwiftUI
import SonicRouteCore

@main
struct SonicRouteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            Text("As configurações do Sonic Route ficam no painel da barra de menus.")
                .padding(24)
                .frame(width: 320)
        }
    }
}
