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
                }
                
                Toggle("Bold text", isOn: $env.settings.boldText)
            }
        }
        .navigationTitle("Look & Feel")
    }
}
