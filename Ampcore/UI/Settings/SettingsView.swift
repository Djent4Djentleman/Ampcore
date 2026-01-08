import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    LibrarySettingsView()
                } label: {
                    Label("Library", systemImage: "music.note.list")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
