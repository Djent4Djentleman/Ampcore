import SwiftUI
import UIKit

struct CoverSwiperView: View {
    let image: UIImage?
    
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void
    
    @State private var offsetX: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 22).fill(.thinMaterial)
                    Image(systemName: "music.note").font(.system(size: 44)).opacity(0.6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .shadow(radius: 22, y: 10)
        .offset(x: offsetX)
        .scaleEffect(scale)
        .gesture(
            DragGesture()
                .onChanged { v in offsetX = v.translation.width; scale = 0.98 }
                .onEnded { v in
                    let dx = v.translation.width
                    let threshold: CGFloat = 90
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        offsetX = 0; scale = 1.0
                    }
                    if dx <= -threshold { onSwipeLeft() }
                    if dx >= threshold { onSwipeRight() }
                }
        )
    }
}
