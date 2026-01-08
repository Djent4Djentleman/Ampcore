import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    var body: some View {
        Form {
            
            // MARK: - Playback
            
            Section("Playback") {
                Toggle("Gapless", isOn: $env.settings.gaplessEnabled)
                Toggle("ReplayGain", isOn: $env.settings.replayGainEnabled)
            }
            
            // MARK: - Crossfade
            
            Section("Crossfade") {
                Toggle("Enable", isOn: $env.settings.crossfadeEnabled)
                
                if env.settings.crossfadeEnabled {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(env.settings.crossfadeSeconds, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: $env.settings.crossfadeSeconds,
                        in: 1...12,
                        step: 0.5
                    )
                }
            }
            
            // MARK: - Fade In
            
            Section("Fade-in") {
                Toggle("Enable", isOn: $env.settings.fadeInEnabled)
                
                if env.settings.fadeInEnabled {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(env.settings.fadeInSeconds, specifier: "%.2f")s")
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(
                        value: $env.settings.fadeInSeconds,
                        in: 0...2,
                        step: 0.05
                    )
                }
            }
            
            // MARK: - EQ
            
            Section {
                NavigationLink {
                    EQView()
                } label: {
                    Label("EQ", systemImage: "slider.horizontal.3")
                }
            }
        }
        .navigationTitle("Audio")
    }
}
