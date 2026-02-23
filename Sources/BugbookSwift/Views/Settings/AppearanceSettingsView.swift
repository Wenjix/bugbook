import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        GroupBox("Theme") {
            Picker("Theme", selection: $appState.settings.theme) {
                Text("Light").tag(ThemeMode.light)
                Text("Dark").tag(ThemeMode.dark)
                Text("System").tag(ThemeMode.system)
            }
            .pickerStyle(.segmented)
            .padding(8)
        }
    }
}
