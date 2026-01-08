import SwiftUI
import CoreData
import UIKit

struct LyricsEditorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss
    
    @State private var lyrics: String = ""
    @State private var textScale: CGFloat = 1.0
    @State private var loadedTrackID: NSManagedObjectID?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                header
                
                TextEditor(text: $lyrics)
                    .font(.system(size: 15 * textScale))
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal)
                    .gesture(pinchGesture)
                
                footer
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: env.player.currentTrackID) { _, _ in
            loadIfNeeded()
        }
        .onDisappear {
            saveIfPossible()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track?.title ?? "No track")
                .font(.headline)
            
            Text(artistAlbumLine)
                .font(.subheadline)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    
    private var artistAlbumLine: String {
        let a = (track?.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let al = (track?.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !a.isEmpty, !al.isEmpty { return "\(a) • \(al)" }
        if !a.isEmpty { return a }
        if !al.isEmpty { return al }
        return "—"
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button {
                openLyricsSearch()
            } label: {
                Label("Find in browser", systemImage: "safari")
            }
            .buttonStyle(.bordered)
            .disabled(track == nil)
            
            Spacer()
            
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }
    
    // MARK: - Gestures
    
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                textScale = min(max(v, 0.85), 1.6)
            }
    }
    
    // MARK: - Data
    
    private var track: CDTrack? {
        guard let id = env.player.currentTrackID else { return nil }
        return (try? moc.existingObject(with: id)) as? CDTrack
    }
    
    private func loadIfNeeded() {
        guard let id = env.player.currentTrackID else {
            lyrics = ""
            loadedTrackID = nil
            return
        }
        guard loadedTrackID != id else { return }
        
        loadedTrackID = id
        lyrics = track?.lyrics ?? ""
    }
    
    private func saveIfPossible() {
        guard let t = track else { return }
        t.lyrics = lyrics
        try? moc.save()
    }
    
    // MARK: - Helpers
    
    private func openLyricsSearch() {
        let a = (track?.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let t = (track?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        
        let query = [a, t, "lyrics"].filter { !$0.isEmpty }.joined(separator: " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://www.google.com/search?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
}
