import SwiftUI

struct ArtworkWithGlow: View {
    let image: UIImage
    var cornerRadius: CGFloat = 18
    
    /// Размеры можно подстроить из PlayerView
    var coverSide: CGFloat = 220
    var glowPadding: CGFloat = 80       // насколько glow выходит за квадрат
    var glowBlur: CGFloat = 42
    var glowOpacity: Double = 0.85
    
    var body: some View {
        let mode = coverMode(for: image)
        
        ZStack {
            // ✅ Glow: размытая копия, больше квадрата
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: coverSide + glowPadding, height: coverSide + glowPadding)
                .clipped()
                .blur(radius: glowBlur)
                .opacity(glowOpacity)
            
            // ✅ РЕЗКАЯ обложка (Fit или Fill)
            cover(mode: mode)
                .frame(width: coverSide, height: coverSide)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(width: coverSide + glowPadding, height: coverSide + glowPadding)
    }
    
    private enum CoverMode { case fill, fit }
    
    /// 1) “Fill или Fit в квадрат” — авто по пропорциям
    private func coverMode(for ui: UIImage) -> CoverMode {
        let w = max(ui.size.width, 1)
        let h = max(ui.size.height, 1)
        let ratio = w / h
        
        // почти квадрат → Fill
        if ratio > 0.88 && ratio < 1.14 { return .fill }
        
        // слишком широкие/высокие → Fit
        return .fit
    }
    
    @ViewBuilder
    private func cover(mode: CoverMode) -> some View {
        switch mode {
        case .fill:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipped()
            
        case .fit:
            ZStack {
                // лёгкая “подложка” внутри квадрата, чтобы Fit выглядел красиво
                Rectangle()
                    .fill(.black.opacity(0.14))
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            }
        }
    }
}
