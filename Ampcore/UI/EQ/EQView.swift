import SwiftUI

struct EQView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var cs
    
    private let ink = Color.primary
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var focusedIndex: Int = 0
    
    @State private var showSavePreset: Bool = false
    @State private var savePresetName: String = ""
    
    @State private var dspWorkItem: DispatchWorkItem?
    
    private let bandLabels: [String] = ["Pre","31","62","125","250","500","1K","2K","4K","8K"]
    private let bandRange: ClosedRange<Double> = -12...12
    
    private var store: EQStore { env.eqStore }
    
    
    // Card styling (like Settings rows)
    private var panelFill: Color {
        cs == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    
    private var panelStroke: Color {
        Color.primary.opacity(cs == .dark ? 0.18 : 0.12)
    }
    
    // Control styling (buttons/menus)
    private var controlFillOff: Color { panelFill }
    private var controlFillOn: Color {
        // Selected state should be clearly visible.
        cs == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.14)
    }
    private var controlStroke: Color { ink.opacity(cs == .dark ? 0.22 : 0.16) }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (cs == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    slidersRow
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(panelFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(panelStroke, lineWidth: 1)
                        )
                        .padding(.horizontal, 16)
                    
                    
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
                    focusedIndex = min(max(focusedIndex, 0), bandLabels.count - 1)
                    syncDSP()
                }
                .onChange(of: store.snapshot.eqEnabled) { _, _ in scheduleDSP() }
                .onChange(of: store.snapshot.toneEnabled) { _, _ in scheduleDSP() }
                .onChange(of: store.snapshot.limiterEnabled) { _, _ in scheduleDSP() }
                .onChange(of: store.snapshot.limiterAmount) { _, _ in scheduleDSP() }
                .onChange(of: store.snapshot.bass) { _, _ in scheduleDSP() }
                .onChange(of: store.snapshot.treble) { _, _ in scheduleDSP() }
                .alert("Save Preset", isPresented: $showSavePreset) {
                    TextField("Name", text: $savePresetName)
                    Button("Save") {
                        store.saveCurrentAsUserPreset(name: savePresetName)
                        savePresetName = ""
                    }
                    Button("Cancel", role: .cancel) { savePresetName = "" }
                } message: {
                    Text("Create a new preset from current settings.")
                }
            }
        }
    }
    
    private var currentPresetTitle: String {
        let id = store.snapshot.selectedPresetId
        if let builtIn = BuiltInEQPreset.allCases.first(where: { $0.id == id }) {
            return builtIn.title
        }
        if let user = store.userPresets.first(where: { $0.id == id }) {
            return user.name
        }
        return "Custom"
    }
    
    // MARK: - Sliders
    
    private var slidersRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(0..<bandLabels.count, id: \.self) { idx in
                        VStack(spacing: 10) {
                            VerticalEQSlider(
                                value: Binding(
                                    get: { store.snapshot.bandValues[safe: idx] ?? 0 },
                                    set: { v in
                                        setBand(idx: idx, value: v)
                                        focusedIndex = idx
                                        scheduleDSP()
                                    }
                                ),
                                range: bandRange,
                                enabled: store.snapshot.eqEnabled,
                                ink: ink
                            )
                            .frame(width: 34, height: 210)
                            
                            Text(bandLabels[idx])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ink.opacity(store.snapshot.eqEnabled ? 0.9 : 0.35))
                                .padding(.top, 2)
                            
                            Text(String(format: "%.1f", store.snapshot.bandValues[safe: idx] ?? 0))
                                .font(.caption2)
                                .foregroundStyle(ink.opacity(store.snapshot.eqEnabled ? 0.65 : 0.25))
                        }
                        .frame(width: 40)
                        .id(idx)
                        
                        // Visually separate Preamp from the other bands.
                        if idx == 0 {
                            Rectangle()
                                .fill(Color.black.opacity(cs == .dark ? 0.35 : 0.18))
                                .frame(width: 1, height: 230)
                                .padding(.horizontal, 6)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { scrollProxy = proxy }
        }
    }
    
    private func setBand(idx: Int, value: Double) {
        if store.snapshot.bandValues.count != bandLabels.count {
            store.snapshot.bandValues = store.normalized10(store.snapshot.bandValues)
        }
        guard store.snapshot.bandValues.indices.contains(idx) else { return }
        store.snapshot.bandValues[idx] = min(max(value, bandRange.lowerBound), bandRange.upperBound)
    }
    
    // MARK: - Response panel
    
    private var responsePanel: some View {
        ZStack {
            responseCurve
                .padding(.horizontal, 16)
            
            glassScroller
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(height: 74)
        .opacity(store.snapshot.eqEnabled ? 1.0 : 0.45)
    }
    
    private var responseCurve: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = curvePoints(width: w, height: h)
            
            ZStack {
                Rectangle()
                    .fill(ink.opacity(0.22))
                    .frame(height: 1)
                    .position(x: w * 0.5, y: h * 0.5)
                
                Path { p in
                    guard points.count >= 2 else { return }
                    p.move(to: points[0])
                    
                    for i in 1..<points.count {
                        let prev = points[i - 1]
                        let cur = points[i]
                        let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
                        p.addQuadCurve(to: mid, control: prev)
                        if i == points.count - 1 {
                            p.addQuadCurve(to: cur, control: cur)
                        }
                    }
                }
                .stroke(ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }
    
    private func curvePoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        let values = Array(store.normalized10(store.snapshot.bandValues).dropFirst())
        let n = max(values.count, 2)
        let minV: Double = bandRange.lowerBound
        let maxV: Double = bandRange.upperBound
        
        func y(for v: Double) -> CGFloat {
            let denom = (maxV - minV == 0) ? 1 : (maxV - minV)
            let t = (v - minV) / denom
            let inset: CGFloat = 6
            return inset + (1 - CGFloat(t)) * (height - inset * 2)
        }
        
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        
        for i in 0..<n {
            let x = CGFloat(i) / CGFloat(n - 1) * width
            pts.append(CGPoint(x: x, y: y(for: values[i])))
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
            let count = max(bandLabels.count, 1)
            
            let knobW = max(140, w * 0.60)
            let step = (w - knobW) / CGFloat(max(count - 1, 1))
            let x = CGFloat(focusedIndex) * step
            
            ZStack(alignment: .leading) {
                // Static track (full width) so the gray background does NOT move.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ink.opacity(store.snapshot.eqEnabled ? 0.08 : 0.05))
                    .frame(height: h)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ink.opacity(store.snapshot.eqEnabled ? 0.14 : 0.08), lineWidth: 1)
                    )
                
                // Moving focus window.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ink.opacity(store.snapshot.eqEnabled ? 0.12 : 0.07))
                    .frame(width: knobW, height: h)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ink.opacity(store.snapshot.eqEnabled ? 0.20 : 0.10), lineWidth: 1)
                    )
                    .offset(x: x)
                    .animation(.easeOut(duration: 0.12), value: focusedIndex)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard store.snapshot.eqEnabled else { return }
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
        }
        .frame(height: 44)
        .opacity(store.snapshot.eqEnabled ? 1.0 : 0.55)
    }
    // MARK: - Bottom panel
    
    private var bottomPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                modeButton(title: "Equ", isOn: store.snapshot.eqEnabled) {
                    withAnimation(.easeInOut(duration: 0.18)) { store.snapshot.eqEnabled.toggle() }
                }
                .frame(width: 96)
                
                presetMenuButton
            }
            
            HStack(spacing: 6) {
                VStack(spacing: 10) {
                    modeButton(title: "Tone", isOn: store.snapshot.toneEnabled) {
                        withAnimation(.easeInOut(duration: 0.18)) { store.snapshot.toneEnabled.toggle() }
                    }
                    
                    modeButton(title: "Limit", isOn: store.snapshot.limiterEnabled) {
                        withAnimation(.easeInOut(duration: 0.18)) { store.snapshot.limiterEnabled.toggle() }
                    }
                }
                .frame(width: 96)
                
                HStack(spacing: 18) {
                    ToneKnob(
                        title: "Bass",
                        value: Binding(get: { store.snapshot.bass }, set: { store.snapshot.bass = $0; scheduleDSP() }),
                        enabled: store.snapshot.toneEnabled,
                        ink: ink
                    )
                    ToneKnob(
                        title: "Treble",
                        value: Binding(get: { store.snapshot.treble }, set: { store.snapshot.treble = $0; scheduleDSP() }),
                        enabled: store.snapshot.toneEnabled,
                        ink: ink
                    )
                    
                    ToneKnob(
                        title: "Drive",
                        value: Binding(get: { store.snapshot.limiterAmount }, set: { store.snapshot.limiterAmount = $0; scheduleDSP() }),
                        enabled: store.snapshot.limiterEnabled,
                        ink: ink
                    )
                }
            }
        }
    }
    
    private var presetMenuButton: some View {
        Menu {
            Section("Built-in") {
                ForEach(BuiltInEQPreset.allCases) { p in
                    Button {
                        store.selectBuiltIn(p, keepEQEnabled: true)
                        scheduleDSP()
                    } label: {
                        if store.snapshot.selectedPresetId == p.id {
                            Label(p.title, systemImage: "checkmark")
                        } else {
                            Text(p.title)
                        }
                    }
                }
            }
            
            if !store.userPresets.isEmpty {
                Section("My Presets") {
                    ForEach(store.userPresets) { p in
                        Button {
                            store.selectUserPreset(id: p.id, keepEQEnabled: true)
                            scheduleDSP()
                        } label: {
                            if store.snapshot.selectedPresetId == p.id {
                                Label(p.name, systemImage: "checkmark")
                            } else {
                                Text(p.name)
                            }
                        }
                    }
                }
            }
            
            Section {
                Button {
                    showSavePreset = true
                } label: {
                    Label("Save Preset…", systemImage: "plus")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentPresetTitle)
                    .foregroundStyle(ink)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink.opacity(0.7))
            }
            .frame(maxWidth: 260, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(controlFillOff)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ink.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .layoutPriority(1)
    }
    
    private func modeButton(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        let fill = isOn ? controlFillOn : controlFillOff
        let stroke = isOn
        ? ink.opacity(cs == .dark ? 0.42 : 0.24)
        : controlStroke
        
        return Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle((isOn && cs == .dark) ? Color.black.opacity(0.92) : ink.opacity(isOn ? 1.0 : 0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(stroke, lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(isOn ? 0.18 : 0.0), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
    // MARK: - DSP
    
    private func scheduleDSP() {
        dspWorkItem?.cancel()
        let item = DispatchWorkItem { syncDSP() }
        dspWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: item)
    }
    
    private func syncDSP() {
        let s = store.snapshot.normalized10()
        
        env.player.setEQEnabled(s.eqEnabled)
        
        let pre = Float(s.bandValues.first ?? 0)
        let gains = s.bandValues.dropFirst().map { Float($0) }
        env.player.applyEQ(preampDB: pre, gainsDB: gains)
        
        env.player.setToneEnabled(s.toneEnabled)
        env.player.applyTone(bassPercent: Float(s.bass), treblePercent: Float(s.treble))
        
        env.player.setLimiterEnabled(s.limiterEnabled)
        env.player.applyLimiter(amountPercent: Float(s.limiterAmount))
    }
}

// MARK: - Slider

private struct VerticalEQSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let ink: Color
    
    @Environment(\.colorScheme) private var cs
    
    @GestureState private var isDragging: Bool = false
    
    private let handleW: CGFloat = 22
    private let handleH: CGFloat = 54
    // Base track thickness (bottom segment).
    private let trackW: CGFloat = 3
    private let activeInset: CGFloat = 33
    
    // Subtle "active" emphasis when the EQ is enabled + stronger emphasis while dragging.
    private var activeBoost: CGFloat { enabled ? 1.06 : 1.0 }
    private var trackWidth: CGFloat {
        let base = trackW * activeBoost
        return isDragging ? (base + 0.8) : base
    }
    private var topTrackWidth: CGFloat {
        // Make the section above the handle *clearly* thinner than the bottom segment.
        // Using a smaller ratio avoids the light theme reading as "same thickness".
        max(1.2, trackWidth * 0.42)
    }
    private var handleStroke: CGFloat { (enabled ? 1.15 : 1.0) + (isDragging ? 0.55 : 0.0) }
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let activeTop = activeInset
            let activeBottom = max(activeTop + 1, h - activeInset)
            let activeH = activeBottom - activeTop
            
            let t = normalized(value)
            let yRaw = activeTop + (1 - t) * activeH
            let yCenter = min(max(yRaw, handleH * 0.5), h - handleH * 0.5)
            
            // Track is two-tone:
            // - Above the handle: gray (both themes)
            // - Below the handle: white in dark / black in light
            let topTrack = Color.gray.opacity(enabled ? 0.55 : 0.28)
            let bottomTrack = (cs == .dark
                               ? Color.white.opacity(enabled ? 0.95 : 0.45)
                               : Color.black.opacity(enabled ? 0.92 : 0.38)
            )
            
            // Subtle outline (kept lighter in Light mode so it doesn't "fatten" the thin top segment).
            let trackOutline = Color.black.opacity(cs == .dark ? 0.22 : 0.10)
            let baseOutline: CGFloat = cs == .dark ? 0.70 : 0.45
            let bottomOutlineW: CGFloat = (enabled ? baseOutline : baseOutline * 0.85) + (isDragging ? 0.25 : 0.0)
            let topOutlineW: CGFloat = bottomOutlineW * 0.65
            
            let topFillH = max(0, yCenter - handleH * 0.5)
            let bottomFillH = max(0, h - (yCenter + handleH * 0.5))
            let topFill = min(topFillH, h)
            let bottomFill = min(bottomFillH, h)
            
            ZStack {
                // Two independent segments so the "top" is truly thinner (not an overlay illusion).
                // Bottom segment (full thickness) — from bottom up to the handle.
                Capsule(style: .continuous)
                    .fill(bottomTrack)
                    .frame(width: trackWidth)
                    .mask(
                        Rectangle()
                            .frame(height: bottomFill)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(trackOutline, lineWidth: bottomOutlineW)
                            .frame(width: trackWidth)
                    )
                
                // Top segment (thinner) — from top down to the handle.
                Capsule(style: .continuous)
                    .fill(topTrack)
                    .frame(width: topTrackWidth)
                    .mask(
                        Rectangle()
                            .frame(height: topFill)
                            .frame(maxHeight: .infinity, alignment: .top)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(trackOutline, lineWidth: topOutlineW)
                            .frame(width: topTrackWidth)
                    )
                
                // Horizontal dashed guides at the top/bottom limits of the handle's center.
                dashedLimitLine(y: activeTop, in: geo.size.width, lineWidth: 28, color: topTrack)
                dashedLimitLine(y: activeBottom, in: geo.size.width, lineWidth: 28, color: topTrack)
                
                Rectangle()
                    .fill(ink.opacity(0.30))
                    .frame(width: 28, height: 1)
                    .offset(y: activeTop + activeH * 0.5 - h * 0.5)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 1.0 : 0.75))
                // Subtle 3D feel (highlight at top, shade at bottom).
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(enabled ? 0.55 : 0.35),
                                        Color.white.opacity(0.0),
                                        Color.black.opacity(enabled ? 0.10 : 0.06)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .blendMode(.overlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.black.opacity(enabled ? 0.55 : 0.28), lineWidth: handleStroke)
                    )
                    .overlay(
                        Rectangle()
                        // Keep the handle's center marker identical in light/dark.
                            .fill(Color.black.opacity(0.65))
                            .frame(width: handleW - 8, height: 2)
                    )
                    .frame(width: handleW, height: handleH)
                    .position(x: geo.size.width * 0.5, y: yCenter)
                    .scaleEffect(isDragging ? 1.035 : 1.0)
                    .shadow(color: .black.opacity(enabled ? 0.16 : 0.10), radius: isDragging ? 12 : 8, x: 0, y: isDragging ? 9 : 6)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { g in
                        guard enabled else { return }
                        // Allow horizontal swipes to scroll the EQ without jerking slider values.
                        guard abs(g.translation.height) > abs(g.translation.width) else { return }
                        
                        let y = min(max(g.location.y, max(activeTop, handleH * 0.5)), min(activeBottom, h - handleH * 0.5))
                        let tNew = 1 - ((y - activeTop) / max(activeH, 1))
                        value = denormalized(tNew)
                    }
            )
        }
    }
    
    private func dashedLimitLine(y: CGFloat, in viewWidth: CGFloat, lineWidth: CGFloat, color: Color) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: lineWidth, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
        .frame(width: lineWidth, height: 1)
        .position(x: viewWidth * 0.5, y: y)
        .allowsHitTesting(false)
    }
    
    private func normalized(_ v: Double) -> CGFloat {
        let r = range.upperBound - range.lowerBound
        if r == 0 { return 0.5 }
        let tt = (v - range.lowerBound) / r
        return CGFloat(min(max(tt, 0), 1))
    }
    
    private func denormalized(_ t: CGFloat) -> Double {
        let tt = Double(min(max(t, 0), 1))
        return range.lowerBound + (range.upperBound - range.lowerBound) * tt
    }
}

private struct ToneKnob: View {
    let title: String
    @Binding var value: Double
    let enabled: Bool
    let ink: Color
    
    private let range: ClosedRange<Double> = 0...100
    
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
                    .frame(width: 4, height: 18)
                    .offset(y: -20)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        let delta = -Double(g.translation.height) * 0.7
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

private extension Array {
    subscript(safe idx: Int) -> Element? {
        guard indices.contains(idx) else { return nil }
        return self[idx]
    }
}
