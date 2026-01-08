import SwiftUI

struct SettingsRootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LibrarySettingsView()
                } label: {
                    Label("Library", systemImage: "folder")
                }
                
                NavigationLink {
                    AudioSettingsView()
                } label: {
                    Label("Audio", systemImage: "speaker.wave.2")
                }
                
                NavigationLink {
                    AlbumArtSettingsView()
                } label: {
                    Label("Album Art", systemImage: "photo.on.rectangle")
                }
                
                NavigationLink {
                    LookFeelSettingsView()
                } label: {
                    Label("Look & Feel", systemImage: "paintbrush")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
