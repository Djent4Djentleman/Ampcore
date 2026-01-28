import SwiftUI
import UIKit

struct TrackRowView: View {
    let track: CDTrack
    
    /// Visual scaling controlled by parent (e.g. pinch gesture in All Songs).
    var rowScale: CGFloat = 1.0
    
    /// Current playback indicator.
    var isCurrent: Bool = false
    var isPlaying: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 64 * rowScale, height: 64 * rowScale)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(track.title)
                    .font(.system(size: 16 * rowScale, weight: .semibold))
                    .lineLimit(1)
                
                Text([track.artist, track.album]
                    .compactMap { $0 }
                    .joined(separator: " • "))
                .font(.system(size: 13 * rowScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                
                Text(Formatters.time(track.duration))
                    .font(.system(size: 12 * rowScale))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            
            Spacer()
            
            if isCurrent {
                Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 16 * rowScale, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else if !track.isSupported {
                Text("Unsupported")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .opacity(0.8)
            }
        }
        .padding(.vertical, 4 * rowScale)
    }
    
    private var artwork: some View {
        Group {
            if let d = track.artworkData, let img = UIImage(data: d) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                Image("DefaultArtwork")
                    .resizable()
                    .scaledToFill()
                    .clipped()
            }
        }
    }
}
