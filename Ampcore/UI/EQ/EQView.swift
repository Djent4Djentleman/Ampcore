import SwiftUI

struct EQView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    private let ink = Color.black
    
    @State private var eqEnabled = true
    @State private var toneEnabled = false
    @State private var limitEnabled = false
    
    @State private var preset: Preset = .flat
    
    // ✅ 10 контролов: Pre + 31..8K
    @State private var bands: [EQBand] = [
        .init(label: "Pre", value: 0, min: -12, max: 12),
        .init(label: "31",  value: 0, min: -12, max: 12),
        .init(label: "62",  value: 0, min: -12, max: 12),
        .init(label: "125", value: 0, min: -12, max: 12),
        .init(label: "250", value: 0, min: -12, max: 12),
        .init(label: "500", value: 0, min: -12, max: 12),
        .init(label: "1K",  value: 0, min: -12, max: 12),
        .init(label: "2K",  value: 0, min: -12, max: 12),
        .init(label: "4K",  value: 0, min: -12, max: 12),
        .init(label: "8K",  value: 0, min: -12, max: 12)
    ]
    
    @State private var bass: Double = 0
    @State private var treble: Double = 0
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var focusedIndex: Int = 0
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                topRow
                slidersRow
                
                responsePanel
                    .padding(.horizontal, 16)
                
                bottomPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .navigationTitle("EQ")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                limitEnabled = env.player.isLimiterEnabled()
                preset = .flat
                applyPreset(.flat)
                syncDSP()
            }
            
            // ✅ любой чендж => syncDSP
            .onChange(of: bands) { _, _ in syncDSP() }
            .onChange(of: eqEnabled) { _, _ in
                if !eqEnabled {
                    toneEnabled = false
                    limitEnabled = false
                }
                syncDSP()
            }
            .onChange(of: toneEnabled) { _, _ in syncDSP() }
            .onChange(of: limitEnabled) { _, _ in syncDSP() }
            .onChange(of: bass) { _, _ in syncDSP() }
            .onChange(of: treble) { _, _ in syncDSP() }
        }
    }
    
    // MARK: - DSP sync
    
    private func syncDSP() {
        env.player.setEQEnabled(eqEnabled)
        
        // preamp = bands[0], gains = bands[1...]
        let pre = Float(bands.first?.value ?? 0)
        let gains = bands.dropFirst().map { Float($0.value) }
        env.player.applyEQ(preampDB: pre, gainsDB: gains)
        
        env.player.setToneEnabled(eqEnabled && toneEnabled)
        env.player.applyTone(bassPercent: Float(bass), treblePercent: Float(treble))
        
        // Limiter only when EQ enabled
        env.player.setLimiterEnabled(eqEnabled && limitEnabled)
    }
    
    // MARK: - Top
    
    private var topRow: some View {
        HStack(spacing: 12) {
            Text("EQ")
                .font(.headline)
                .foregroundStyle(ink)
            
            Spacer()
            
            PressButton(isOn: eqEnabled, titleOn: "On", titleOff: "Off") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    eqEnabled.toggle()
                }
            }
            .frame(width: 86, height: 34)
            
            Menu {
                Picker("Preset", selection: $preset) {
                    ForEach(Preset.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(preset.title)
                        .foregroundStyle(ink)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.7))
                }
                // ✅ фиксируем ширину, чтобы названия пресетов не "прыгали" и не вылезали
                .frame(width: 210, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(ink.opacity(0.25), lineWidth: 1))
            }
            .onChange(of: preset) { _, new in
                applyPreset(new)
                syncDSP()
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Sliders
    
    private var slidersRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 12) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { idx, _ in
                        VStack(spacing: 8) {
                            VerticalEQSlider(
                                value: Binding(
                                    get: { bands[idx].value },
                                    set: { v in
                                        bands[idx].value = v
                                        focusedIndex = idx
                                    }
                                ),
                                range: bands[idx].min...bands[idx].max,
                                enabled: eqEnabled,
                                ink: ink
                            )
                            // ✅ чуть короче, чтобы не вылезало
                            .frame(width: 46, height: 210)
                            
                            Text(bands[idx].label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ink.opacity(eqEnabled ? 0.9 : 0.35))
                            
                            Text(String(format: "%.1f", bands[idx].value))
                                .font(.caption2)
                                .foregroundStyle(ink.opacity(eqEnabled ? 0.65 : 0.25))
                        }
                        .frame(width: 54)
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
            }
            .onAppear { scrollProxy = proxy }
        }
    }
    
    // MARK: - Response panel + overlay scroller
    
    private var responsePanel: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        
        return ZStack {
            shape
                .fill(.thinMaterial)
                .overlay(shape.stroke(ink.opacity(0.12), lineWidth: 1))
            
            // ✅ диаграмма всегда чёрная, не вылезает за края из-за clip ниже
            responseCurve
                .padding(.horizontal, 18)
            
            // ✅ “liquid glass” скроллер — почти прозрачный, по размеру почти как поле
            glassScroller
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(height: 74)
        .opacity(0.95)
        .clipShape(shape) // ✅ главный фикс "не вылезает за края"
    }
    
    private var responseCurve: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = curvePoints(width: w, height: h)
            
            Path { p in
                guard let first = points.first else { return }
                p.move(to: first)
                for pt in points.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(ink, lineWidth: 2.2)
        }
    }
    
    private func curvePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let n = max(bands.count, 2)
        let minV = bands.map(\.min).min() ?? -12
        let maxV = bands.map(\.max).max() ?? 12
        
        func y(for v: Double) -> CGFloat {
            let denom = (maxV - minV == 0) ? 1 : (maxV - minV)
            let t = (v - minV) / denom
            return (1 - CGFloat(t)) * height
        }
        
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        
        for i in 0..<n {
            let x = CGFloat(i) / CGFloat(n - 1) * width
            pts.append(CGPoint(x: x, y: y(for: bands[i].value)))
        }
        
        if pts.count > 2 {
            var smooth = pts
            for i in 1..<(pts.count - 1) {
                let yv = (pts[i-1].y + pts[i].y * 2 + pts[i+1].y) / 4
                smooth[i] = CGPoint(x: pts[i].x, y: yv)
            }
            return smooth
        }
        return pts
    }
    
    private var glassScroller: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 44
            let count = max(bands.count, 1)
            
            // ✅ почти размер поля, “liquid”
            let knobW = max(90, w * 0.28)
            let step = (w - knobW) / CGFloat(max(count - 1, 1))
            let x = CGFloat(focusedIndex) * step
            
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ink.opacity(0.06), lineWidth: 1)
                )
                .frame(height: h)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ink.opacity(0.03))     // ✅ почти прозрачная “ручка”
                        .background(.ultraThinMaterial)
                        .frame(width: knobW, height: 38)
                        .offset(x: x)
                        .animation(.easeOut(duration: 0.12), value: focusedIndex)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            // ✅ индекс считаем по позиции — меньше дёрганья
                            let p = min(max(g.location.x / max(w, 1), 0), 1)
                            let idx = Int((p * CGFloat(count - 1)).rounded())
                            let clamped = max(0, min(count - 1, idx))
                            
                            guard clamped != focusedIndex else { return }
                            focusedIndex = clamped
                            
                            if let proxy = scrollProxy {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    proxy.scrollTo(clamped, anchor: .center)
                                }
                            }
                        }
                )
                .opacity(eqEnabled ? 1.0 : 0.55)
        }
        .frame(height: 44)
    }
    
    // MARK: - Bottom panel
    
    private var bottomPanel: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                modeButton(title: "Equ", isOn: eqEnabled) {
                    withAnimation(.easeInOut(duration: 0.18)) { eqEnabled.toggle() }
                }
                
                modeButton(title: "Tone", isOn: eqEnabled && toneEnabled) {
                    guard eqEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { toneEnabled.toggle() }
                }
                .opacity(eqEnabled ? 1.0 : 0.45)
                
                modeButton(title: "Limit", isOn: eqEnabled && limitEnabled) {
                    guard eqEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.18)) { limitEnabled.toggle() }
                }
                .opacity(eqEnabled ? 1.0 : 0.45)
            }
            .frame(width: 96)
            
            VStack(spacing: 10) {
                HStack(spacing: 18) {
                    ToneKnob(title: "Bass", value: $bass, enabled: eqEnabled && toneEnabled, ink: ink)
                    ToneKnob(title: "Treble", value: $treble, enabled: eqEnabled && toneEnabled, ink: ink)
                }
            }
        }
    }
    
    private func modeButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isOn ? ink : Color.black.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ink.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Presets
    
    private func applyPreset(_ p: Preset) {
        let v: [Double]
        switch p {
        case .flat:
            v = [0, 0,0,0,0,0,0,0,0,0]
        case .rock:
            v = [0, 3,2,1,0.5,-0.5,1.5,3,1,0.5]
        case .bassBoost:
            v = [2, 6,5,3,1,0,-1,-1,-1,-1]
        case .trebleBoost:
            v = [0, -1,-1,0,1,2,4,5,6,5]
        case .vShape:
            v = [0, 4,3,1,-1,-1,1,3,4,3]
        case .vocal:
            v = [0, -2,-1,1,3,3,2,1,0,0]
        case .metal:
            v = [0, 4,3,0,-1,1,3,4,2,1]
        case .dance:
            v = [0, 5,4,2,0,-1,1,3,4,3]
        case .acoustic:
            v = [0, -1,0,1,2,2,1,0,-1,-1]
        }
        
        for i in bands.indices {
            bands[i].value = v[safe: i] ?? 0
        }
    }
}

// MARK: - Models

private struct EQBand: Equatable {
    var label: String
    var value: Double
    var min: Double
    var max: Double
}

private enum Preset: String, CaseIterable, Identifiable {
    case flat, rock, bassBoost, trebleBoost, vShape, vocal, metal, dance, acoustic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .flat: return "Flat"
        case .rock: return "Rock"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .vShape: return "V-Shape"
        case .vocal: return "Vocal"
        case .metal: return "Metal"
        case .dance: return "Dance"
        case .acoustic: return "Acoustic"
        }
    }
}

// MARK: - Vertical slider (no out-of-bounds)

private struct VerticalEQSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let ink: Color
    
    private let handleH: CGFloat = 44
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            
            ZStack {
                Capsule()
                    .fill(ink.opacity(0.18))
                    .frame(width: 3)
                
                Rectangle()
                    .fill(ink.opacity(0.18))
                    .frame(width: 26, height: 1)
                
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ink.opacity(0.55), lineWidth: 1)
                    )
                    .frame(width: w, height: handleH)
                    .overlay(
                        Capsule()
                            .fill(ink.opacity(0.55))
                            .frame(width: 18, height: 4)
                    )
                    .position(x: w / 2, y: yPos(for: value, height: h))
                    .shadow(radius: 2, y: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        let y = min(max(g.location.y, handleH / 2), h - handleH / 2)
                        value = valueFrom(y: y, height: h)
                    }
            )
            .opacity(enabled ? 1.0 : 0.40)
        }
    }
    
    private func yPos(for v: Double, height: CGFloat) -> CGFloat {
        let denom = (range.upperBound - range.lowerBound == 0) ? 1 : (range.upperBound - range.lowerBound)
        let t = (v - range.lowerBound) / denom
        let raw = (1 - CGFloat(t)) * height
        return min(max(raw, handleH / 2), height - handleH / 2)
    }
    
    private func valueFrom(y: CGFloat, height: CGFloat) -> Double {
        let usable = max(height - handleH, 1)
        let t = 1 - Double((y - handleH / 2) / usable)
        return range.lowerBound + t * (range.upperBound - range.lowerBound)
    }
}

// MARK: - Tone knob

private struct ToneKnob: View {
    let title: String
    @Binding var value: Double
    let enabled: Bool
    let ink: Color
    
    private let range: ClosedRange<Double> = -100...100
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ink.opacity(enabled ? 0.9 : 0.35))
                Spacer()
                Text("\(Int(value))%")
                    .font(.caption2)
                    .foregroundStyle(ink.opacity(enabled ? 0.65 : 0.25))
            }
            
            ZStack {
                Circle().fill(.thinMaterial)
                Circle().stroke(ink.opacity(0.22), lineWidth: 1)
                
                Rectangle()
                    .fill(ink.opacity(enabled ? 0.75 : 0.25))
                    .frame(width: 4, height: 22)
                    .offset(y: -22)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 110, height: 110)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        let delta = -Double(g.translation.height) * 0.6
                        value = clamp(value + delta, range)
                    }
            )
            .opacity(enabled ? 1.0 : 0.55)
        }
    }
    
    private var angle: Double {
        let denom = (range.upperBound - range.lowerBound == 0) ? 1 : (range.upperBound - range.lowerBound)
        let t = (value - range.lowerBound) / denom
        return -135 + t * 270
    }
    
    private func clamp(_ v: Double, _ r: ClosedRange<Double>) -> Double {
        min(max(v, r.lowerBound), r.upperBound)
    }
}

// MARK: - Press button

private struct PressButton: View {
    let isOn: Bool
    let titleOn: String
    let titleOff: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isOn ? Color.black : Color.black.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.16), lineWidth: 1)
                    )
                
                Text(isOn ? titleOn : titleOff)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? Color.white : Color.black)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard indices.contains(idx) else { return nil }
        return self[idx]
    }
}
