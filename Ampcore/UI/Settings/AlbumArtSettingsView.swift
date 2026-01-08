import SwiftUI

struct AlbumArtSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    var body: some View {
        Form {
            Section("Download") {
                Toggle("Download in HD", isOn: $env.settings.artworkQualityHD)
                Toggle("Wi-Fi only", isOn: $env.settings.artworkWifiOnly)
            }
            
            Section {
                Text("Next: search by tags/title/filename and show a cover picker grid.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Album Art")
    }
}
