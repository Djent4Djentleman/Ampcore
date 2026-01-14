import SwiftUI
import Combine

struct LookFeelSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: Binding(
                    get: { env.settings.theme },
                    set: { env.settings.theme = $0 }
                )) {
                    ForEach(AppSettings.Theme.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
            }
            
            Section("Font") {
                Picker("Font", selection: Binding(
                    get: { env.settings.fontChoice },
                    set: { env.settings.fontChoice = $0 }
                )) {
                    ForEach(AppSettings.FontChoice.allCases) { f in
                        Text(f.title).tag(f)
                    }
                    .onChange(of: env.settings.fontChoice) { _, newValue in
                        if newValue != .system { env.settings.boldText = false }
                    }
                }
                
                Toggle("Bold text", isOn: $env.settings.boldText)
                    .disabled(env.settings.fontChoice != .system)
                    .opacity(env.settings.fontChoice == .system ? 1 : 0.45)
            }
        }
        .navigationTitle("Look & Feel")
    }
}
