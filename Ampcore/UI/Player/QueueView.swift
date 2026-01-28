import SwiftUI
import CoreData

struct QueueView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss
    
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        NavigationStack {
            List {
                if queueIDs.isEmpty {
                    ContentUnavailableView(
                        "Queue is empty",
                        systemImage: "list.bullet",
                        description: Text("Add tracks from Library or start playback.")
                    )
                } else {
                    ForEach(queueTracks, id: \.objectID) { t in
                        row(t)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { play(t) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(t) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                    .onMove(perform: move)
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        if !queueIDs.isEmpty {
                            Button { clear() } label: {
                                Image(systemName: "trash")
                            }
                        }
                        
                        Button {
                            editMode = (editMode == .active) ? .inactive : .active
                        } label: {
                            Image(systemName: editMode == .active ? "checkmark.circle" : "line.3.horizontal")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Data
    
    private var queueIDs: [NSManagedObjectID] {
        env.player.queueTrackIDs
    }
    
    private var queueTracks: [CDTrack] {
        queueIDs.compactMap { id in
            (try? moc.existingObject(with: id)) as? CDTrack
        }
    }
    
    // MARK: - Row
    
    private func row(_ t: CDTrack) -> some View {
        TrackRowView(
            track: t,
            rowScale: 1.0,
            isCurrent: t.objectID == env.player.currentTrackID,
            isPlaying: env.player.isPlaying
        )
        .listRowBackground(
            t.objectID == env.player.currentTrackID
            ? Color.secondary.opacity(0.18)
            : Color.clear
        )
    }
    
    // MARK: - Actions
    
    private func play(_ t: CDTrack) {
        env.player.play(track: t)
    }
    
    private func move(from source: IndexSet, to destination: Int) {
        env.player.moveQueue(fromOffsets: source, toOffset: destination)
    }
    
    private func remove(_ t: CDTrack) {
        env.player.removeFromQueue(trackID: t.objectID)
    }
    
    private func clear() {
        env.player.clearQueue()
    }
}
