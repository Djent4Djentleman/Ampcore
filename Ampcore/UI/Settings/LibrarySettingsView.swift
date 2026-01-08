import SwiftUI
import CoreData

struct LibrarySettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.managedObjectContext) private var moc
    
    @State private var showPicker = false
    @State private var isScanning = false
    @State private var errorText: String?
    @State private var resultText: String?
    
    var body: some View {
        Form {
            
            // MARK: - Auto Scan + Rescan
            
            Section {
                Toggle("Auto scan on launch", isOn: $env.settings.autoScanOnLaunch)
                
                Button {
                    Task { await rescanLibrary() }
                } label: {
                    if isScanning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Scanning…")
                        }
                    } else {
                        Label("Rescan library", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isScanning || !hasFolder)
                
                if let resultText {
                    Text(resultText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // MARK: - Folder
            
            Section("Default folder") {
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(env.folderAccess.folderDisplayName ?? "Not selected")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Button {
                    showPicker = true
                } label: {
                    Label("Choose folder", systemImage: "folder")
                }
                .disabled(isScanning)
            }
        }
        .navigationTitle("Library")
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in
                showPicker = false
                guard let url else { return }
                
                do {
                    try env.folderAccess.storeSelectedFolder(url: url)
                    resultText = nil
                    errorText = nil
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }
    
    // MARK: - Helpers
    
    private var hasFolder: Bool {
        env.folderAccess.currentBookmarkData() != nil
    }
    
    // MARK: - Scan
    
    @MainActor
    private func rescanLibrary() async {
        guard !isScanning else { return }
        guard hasFolder else {
            resultText = "No folder selected"
            return
        }
        
        isScanning = true
        resultText = nil
        errorText = nil
        
        do {
            let bookmark = env.folderAccess.currentBookmarkData()
            
            try env.folderAccess.withResolvedAccess { folderURL in
                let result = try MusicScanner.scanAndUpsert(
                    folderURL: folderURL,
                    folderBookmark: bookmark,
                    context: moc
                )
                
                if result.added == 0 && result.updated == 0 {
                    resultText = "No changes"
                } else {
                    resultText = "Added \(result.added), updated \(result.updated)"
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
        
        isScanning = false
    }
}
