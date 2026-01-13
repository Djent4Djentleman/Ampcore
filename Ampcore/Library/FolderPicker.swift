import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: View {
    
    @State private var isPickingFolder = false
    let onPicked: (URL) -> Void
    
    var body: some View {
        Button {
            isPickingFolder = true
        } label: {
            Label("Select folder", systemImage: "folder")
        }
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                
                // Activate security-scoped access
                guard url.startAccessingSecurityScopedResource() else {
                    print("❌ Failed to access security-scoped resource")
                    return
                }
                
                defer { url.stopAccessingSecurityScopedResource() }
                
                // Pass URL up (FolderAccess will store bookmark)
                onPicked(url)
                
            case .failure(let error):
                print("❌ Folder picker error:", error)
            }
        }
    }
}
