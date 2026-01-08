import SwiftUI

struct TrackRowView: View {
    let track: CDTrack
    
    var body: some View {
        HStack(spacing: 12) {
            artwork
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .lineLimit(1)
                
                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " • "))
                    .font(.caption)
                    .opacity(0.7)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !track.isSupported {
                Text("Unsupported")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .opacity(0.8)
            }
        }
        .padding(.vertical, 6)
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
