import SwiftUI

struct EQView: View {
    @EnvironmentObject private var env: AppEnvironment
    
    private let ink = Color.primary
    
    @State private var scrollProxy: ScrollViewProxy?
    @State private var focusedIndex: Int = 0
    
    @State private var showSavePreset: Bool = false
    @State private var savePresetName: String = ""
    
    @State private var dspWorkItem: DispatchWorkItem?
    
    private let bandLabels: [String] = ["Pre","31","62","125","250","500","1K","2K","4K","8K"]
    private let bandRange: ClosedRange<Double> = -12...12
    
    private var store: EQStore { env.eqStore }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
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
                focusedIndex = min(max(focusedIndex, 0), bandLabels.count - 1)
                syncDSP()
            }
            .onChange(of: store.snapshot.eqEnabled) { _, newValue in
                if !newValue {
                    store.snapshot.toneEnabled = false
                    store.snapshot.limiterEnabled = false
                }
                scheduleDSP()
            }
            .onChange(of: store.snapshot.toneEnabled) { _, _ in scheduleDSP() }
            .onChange(of: store.snapshot.limiterEnabled) { _, _ in scheduleDSP() }
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
            ScrollView(.horizontal, showsIndicators: true) {
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
            
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ink.opacity(store.snapshot.eqEnabled ? 0.10 : 0.06))
                .frame(width: knobW, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ink.opacity(store.snapshot.eqEnabled ? 0.18 : 0.10), lineWidth: 1)
                )
                .offset(x: x)
                .animation(.easeOut(duration: 0.12), value: focusedIndex)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
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
                    .opacity(store.snapshot.eqEnabled ? 1.0 : 0.45)
                    
                    modeButton(title: "Limit", isOn: store.snapshot.limiterEnabled) {
                        withAnimation(.easeInOut(duration: 0.18)) { store.snapshot.limiterEnabled.toggle() }
                    }
                    .opacity(store.snapshot.eqEnabled ? 1.0 : 0.45)
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
                    .fill(Color.black.opacity(0.06))
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
        
        env.player.setLimiterEnabled(s.limiterEnabled && s.eqEnabled)
    }
}

// MARK: - Slider

private struct VerticalEQSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let enabled: Bool
    let ink: Color
    
    @GestureState private var isDragging: Bool = false
    
    private let handleW: CGFloat = 22
    private let handleH: CGFloat = 54
    private let trackW: CGFloat = 3
    private let activeInset: CGFloat = 33
    
    private var trackWidth: CGFloat { isDragging ? (trackW + 1) : trackW }
    private var handleStroke: CGFloat { isDragging ? 1.6 : 1.0 }
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let activeTop = activeInset
            let activeBottom = max(activeTop + 1, h - activeInset)
            let activeH = activeBottom - activeTop
            
            let t = normalized(value)
            let yRaw = activeTop + (1 - t) * activeH
            let yCenter = min(max(yRaw, handleH * 0.5), h - handleH * 0.5)
            
            ZStack {
                Capsule(style: .continuous)
                    .fill(ink.opacity(0.18))
                    .frame(width: trackWidth)
                
                VStack(spacing: 3) {
                    dashedStack
                    Spacer(minLength: 0)
                    dashedStack
                }
                .frame(width: trackWidth)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .allowsHitTesting(false)
                
                Rectangle()
                    .fill(ink.opacity(0.30))
                    .frame(width: 28, height: 1)
                    .offset(y: activeTop + activeH * 0.5 - h * 0.5)
                    .allowsHitTesting(false)
                
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(enabled ? 1.0 : 0.75))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(ink.opacity(0.55), lineWidth: handleStroke)
                    )
                    .overlay(
                        Rectangle()
                            .fill(ink.opacity(0.90))
                            .frame(width: handleW - 8, height: 2)
                    )
                    .frame(width: handleW, height: handleH)
                    .position(x: geo.size.width * 0.5, y: yCenter)
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard enabled else { return }
                        let y = min(max(g.location.y, max(activeTop, handleH * 0.5)), min(activeBottom, h - handleH * 0.5))
                        let tNew = 1 - ((y - activeTop) / max(activeH, 1))
                        value = denormalized(tNew)
                    }
            )
        }
    }
    
    private var dashedStack: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(ink.opacity(0.22))
                    .frame(width: trackW, height: 3)
            }
        }
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
