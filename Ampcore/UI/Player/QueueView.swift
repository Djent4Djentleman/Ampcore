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
        HStack(spacing: 12) {
            artwork

            VStack(alignment: .leading, spacing: 3) {
                Text(t.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(t.artist ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if t.objectID == env.player.currentTrackID {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.secondary) // Accent
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(
            t.objectID == env.player.currentTrackID
            ? Color.secondary.opacity(0.18)
            : Color.clear
        )
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.15))
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
        .frame(width: 42, height: 42)
    }

    // MARK: - Actions

    private func play(_ t: CDTrack) {
        env.player.play(track: t)
    }

    private func move(from source: IndexSet, to destination: Int) {
        env.player.moveQueue(fromOffsets: source, toOffset: destination)
    }

    private func remove(_ t: CDTrack) {
        guard let idx = queueIDs.firstIndex(of: t.objectID) else { return }
        env.player.removeFromQueue(atOffsets: IndexSet(integer: idx))
    }

    private func clear() {
        env.player.clearQueue()
    }
}
