import SwiftUI

struct WaveformSeekView: View {
    let samples: [Float]          // 0...1 (желательно). Если у тебя другое — норм, я нормализую.
    let progress: Double          // 0...1
    let onSeek: (Double) -> Void
    
    // Настройки вида (можешь править)
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let minBarHeight: CGFloat = 3
    
    // “Files-like”: насколько длиннее экрана делаем waveform при большом количестве samples
    private let maxBarsOnScreen: Int = 120
    
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            
            // решаем: обзорный режим (вся песня на экране) или длинный waveform (как Files)
            let bars = barsToDraw(screenWidth: w)
            let contentWidth = contentWidthFor(barsCount: bars.count, screenWidth: w)
            
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .leading) {
                    waveformBars(bars: bars, height: h)
                        .frame(width: contentWidth, height: h)
                    
                    // progress overlay
                    progressOverlay(contentWidth: contentWidth, height: h)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            isDragging = true
                            let x = clamp(g.location.x, 0, contentWidth)
                            let p = Double(x / max(contentWidth, 1))
                            onSeek(clamp(p, 0, 1))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
        }
        .frame(height: 110) // большой waveform как в Poweramp
    }
    
    // MARK: - Drawing
    
    private func waveformBars(bars: [CGFloat], height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<bars.count, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: barWidth, height: max(minBarHeight, bars[i] * height))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }
    
    private func progressOverlay(contentWidth: CGFloat, height: CGFloat) -> some View {
        let x = CGFloat(clamp(progress, 0, 1)) * contentWidth
        
        return ZStack(alignment: .leading) {
            // “закрашенная” часть waveform (поверх)
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: x, height: height)
                .mask(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            
            // курсор
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(isDragging ? 0.9 : 0.55))
                .frame(width: 3, height: height - 18)
                .padding(.leading, 12 + x)
                .padding(.vertical, 9)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Bars logic
    
    private func barsToDraw(screenWidth: CGFloat) -> [CGFloat] {
        guard !samples.isEmpty else { return Array(repeating: 0.1, count: 60) }
        
        // число столбиков, которое реально видно на экране
        let approxOnScreen = Int((screenWidth - 24) / (barWidth + barSpacing))
        let onScreen = max(40, min(maxBarsOnScreen, approxOnScreen))
        
        // Если samples мало — рисуем “overview” (всё умещается)
        // Если samples много — делаем длиннее, но не 1:1, а разумно
        let targetBars: Int
        if samples.count <= onScreen {
            targetBars = onScreen
        } else {
            // делаем длинный waveform: например в 4 раза длиннее экрана, но ограничим
            targetBars = min(samples.count, onScreen * 6)
        }
        
        return downsample(samples: samples, to: targetBars)
    }
    
    private func contentWidthFor(barsCount: Int, screenWidth: CGFloat) -> CGFloat {
        // если barsCount примерно умещается — ширина = экран
        // если barsCount большой — ширина растёт (как Files)
        let barsWidth = CGFloat(barsCount) * (barWidth + barSpacing) + 24
        return max(screenWidth, barsWidth)
    }
    
    private func downsample(samples: [Float], to count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        if samples.isEmpty { return Array(repeating: 0.1, count: count) }
        
        // нормализация
        let absVals = samples.map { CGFloat(abs($0)) }
        let maxVal = max(absVals.max() ?? 1, 0.0001)
        
        // собираем пики в окна
        let step = Double(samples.count) / Double(count)
        var out: [CGFloat] = []
        out.reserveCapacity(count)
        
        for i in 0..<count {
            let start = Int(Double(i) * step)
            let end = min(samples.count, Int(Double(i + 1) * step))
            if start >= end {
                out.append(0.12)
                continue
            }
            var peak: CGFloat = 0
            for j in start..<end {
                peak = max(peak, absVals[j])
            }
            out.append(max(0.08, peak / maxVal))
        }
        
        return out
    }
    
    private func clamp<T: Comparable>(_ v: T, _ a: T, _ b: T) -> T {
        min(max(v, a), b)
    }
}
