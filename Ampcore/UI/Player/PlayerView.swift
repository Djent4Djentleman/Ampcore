import SwiftUI
import Combine
import CoreData
import UIKit

struct PlayerView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.colorScheme) private var envScheme
    @Environment(\.managedObjectContext) private var moc
    
    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var isWaveScrubbing = false
    
    @State private var showTimerDialog = false
    @State private var showSettingsSheet = false
    
    // Modes
    @AppStorage("player.shuffleEnabled") private var shuffleEnabled = false
    @AppStorage("player.repeatModeRaw") private var repeatModeRaw: Int = RepeatMode.off.rawValue
    
    private var repeatMode: RepeatMode {
        get { RepeatMode(rawValue: repeatModeRaw) ?? .off }
        nonmutating set { repeatModeRaw = newValue.rawValue }
    }
    
    // Sleep timer
    @AppStorage("player.sleepEndTs") private var sleepEndTs: Double = 0
    
    private let oneSecTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        GeometryReader { geo in
            let side = max(0, geo.size.width - 16) // 8 + 8 horizontal padding
            VStack(spacing: 14) {
                coverBlock
                    .frame(width: side, height: side, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .layoutPriority(1)
                
                if hasTrack {
                    modesBlock
                    waveformContainer
                        .padding(.top, 26)
                        .padding(.bottom, 10)
                    timeBlock
                    sleepStatusBlock
                } else {
                    ContentUnavailableView(
                        "Nothing playing",
                        systemImage: "play.circle",
                        description: Text("Pick a track in Library to start.")
                    )
                    .padding(.top, 20)
                }
                
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(backgroundView.ignoresSafeArea())
            .gesture(playerGestures)
            .confirmationDialog("Sleep timer", isPresented: $showTimerDialog) {
                Button("15 minutes") { setSleepTimer(minutes: 15) }
                Button("30 minutes") { setSleepTimer(minutes: 30) }
                Button("1 hour") { setSleepTimer(minutes: 60) }
                if sleepEndDate != nil {
                    Button("Turn off", role: .destructive) { cancelSleepTimer() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showSettingsSheet) {
                NavigationStack { SettingsRootView() }
            }
            .onAppear {
                scrubProgress = env.player.playbackProgress
            }
            .onChange(of: env.player.playbackProgress) { _, v in
                guard !isScrubbing && !isWaveScrubbing else { return }
                scrubProgress = v
            }
            .onReceive(oneSecTick) { _ in
                handleSleepTimerTick()
            }
        }
    }
    
    // MARK: - Top bar
    
    private var topBar: some View { EmptyView() }
    
    // MARK: - Cover
    
    // MARK: - Cover
    
    
    private var coverBlock: some View {
        ZStack(alignment: .bottomLeading) {
            coverImage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .clipped()
            
            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(alignment: .leading, spacing: 6) {
                Text(trackTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                
                if !trackSubtitle.isEmpty {
                    Text(trackSubtitle)
                        .font(.subheadline)
                        .opacity(0.75)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .aspectRatio(1, contentMode: .fit) // square, fills available width
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .compositingGroup() // smoother corners on scaled images
        .shadow(color: .black.opacity(0.55), radius: 26, x: 0, y: 14)
        .padding(.horizontal, 8) // Poweramp-like tight side margins
    }
    
    // MARK: - Modes
    
    private var modesBlock: some View {
        HStack(spacing: 18) {
            modeButton("shuffle", shuffleEnabled) { shuffleEnabled.toggle() }
            modeButton(repeatMode.icon, repeatMode != .off) { repeatMode = repeatMode.next }
            modeButton("list.bullet", false) { env.navigation.showQueue() }
            modeButton("timer", sleepEndDate != nil) { showTimerDialog = true }
            
            Spacer()
            
            Button { env.navigation.showLyrics() } label: {
                Label("Lyrics", systemImage: "quote.bubble")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.12))
        }
    }
    
    // MARK: - Waveform + transport
    
    private var waveformContainer: some View {
        GeometryReader { geo in
            ZStack {
                WaveformProgressView(
                    samples: env.player.waveformSamples,
                    progress: scrubProgress,
                    isScrubbing: isWaveScrubbing
                )
                
                transportOverlay
                    .opacity(isWaveScrubbing ? 0 : 1)
                    .scaleEffect(isWaveScrubbing ? 0.96 : 1)
                    .animation(nil, value: isWaveScrubbing)
            }
            .gesture(waveformScrubGesture(width: geo.size.width))
        }
        .frame(height: 112)
    }
    
    private var transportOverlay: some View {
        HStack(spacing: 34) {
            Button { playPrev() } label: {
                Image(systemName: "backward.fill")
            }
            
            Button { togglePlayPause() } label: {
                Image(systemName: env.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 58))
            }
            
            Button { playNext() } label: {
                Image(systemName: "forward.fill")
            }
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white)
        .shadow(radius: 16)
    }
    
    private func waveformScrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                // Scrub UI must win over playback updates (Poweramp-style).
                isWaveScrubbing = true
                isScrubbing = true
                
                let p = Double(v.location.x / max(width, 1))
                scrubProgress = min(max(p, 0), 1)
            }
            .onEnded { _ in
                // Seek first, then release UI lock after a tiny delay to prevent snap-back.
                env.player.seekUI(to: scrubProgress)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    isWaveScrubbing = false
                    isScrubbing = false
                }
            }
    }
    
    // MARK: - Time
    
    private var timeBlock: some View {
        HStack {
            Text(timeString(env.player.currentTime))
            Spacer()
            Text("-" + timeString(max(env.player.duration - env.player.currentTime, 0)))
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white.opacity(0.75))
    }
    
    private var sleepStatusBlock: some View {
        Group {
            if let d = sleepEndDate {
                let remaining = max(0, Int(d.timeIntervalSinceNow.rounded(.down)))
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Sleep in \(timeString(TimeInterval(remaining)))")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button(role: .destructive) { cancelSleepTimer() } label: {
                        Text("Off")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.12))
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.vertical, 6)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var hasTrack: Bool {
        env.player.currentTrackID != nil
    }
    
    private var track: CDTrack? {
        guard let id = env.player.currentTrackID else { return nil }
        return try? moc.existingObject(with: id) as? CDTrack
    }
    
    
    private var trackTitle: String {
        let t = env.player.nowPlayingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "—" : t
    }
    
    private var trackSubtitle: String {
        let artist = (env.player.nowPlayingArtist).trimmingCharacters(in: .whitespacesAndNewlines)
        let album = (track?.album ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if artist.isEmpty && album.isEmpty { return "" }
        if artist.isEmpty { return album }
        if album.isEmpty { return artist }
        return "\(artist) - \(album)"
    }
    
    private var coverImage: some View {
        Group {
            if let d = track?.artworkData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image("DefaultArtwork").resizable().scaledToFill()
            }
        }
    }
    
    
    
    
    private var cs: ColorScheme {
        switch env.settings.theme {
        case .system:
            return envScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
    
    private var backgroundGradientColors: [Color] {
        if cs == .light {
            return [Color.white.opacity(0.65), Color.white.opacity(0.96)]
        } else {
            return [Color.black.opacity(0.55), Color.black.opacity(0.92)]
        }
    }
    private var backgroundView: some View {
        ZStack {
            coverImage.blur(radius: 70).opacity(0.35)
            LinearGradient(colors: backgroundGradientColors, startPoint: .top, endPoint: .bottom)
        }
    }
    
    private func modeButton(_ icon: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
        }
        .background(Color.white.opacity(on ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(on ? .white : .white.opacity(0.55))
    }
    
    // MARK: - Transport logic (unchanged)
    
    private func togglePlayPause() {
        env.player.isPlaying ? env.player.pause() : env.player.resume()
    }
    
    private func playNext() {
        guard let next = resolveNextTrack() else { return }
        env.player.play(track: next)
    }
    
    private func playPrev() {
        guard let prev = resolvePrevTrack() else { return }
        env.player.play(track: prev)
    }
    
    private func resolveNextTrack() -> CDTrack? {
        guard let id = env.player.nextTrackID() else { return nil }
        return try? moc.existingObject(with: id) as? CDTrack
    }
    
    private func resolvePrevTrack() -> CDTrack? {
        guard let id = env.player.prevTrackID() else { return nil }
        return try? moc.existingObject(with: id) as? CDTrack
    }
    
    // MARK: - Sleep timer (unchanged)
    
    private var sleepEndDate: Date? {
        sleepEndTs > 0 ? Date(timeIntervalSince1970: sleepEndTs) : nil
    }
    
    private func setSleepTimer(minutes: Int) {
        sleepEndTs = Date().addingTimeInterval(Double(minutes) * 60).timeIntervalSince1970
    }
    
    private func cancelSleepTimer() {
        sleepEndTs = 0
    }
    
    private func handleSleepTimerTick() {
        guard let d = sleepEndDate, d.timeIntervalSinceNow <= 0 else { return }
        cancelSleepTimer()
        env.player.pause()
    }
    
    private func timeString(_ t: TimeInterval) -> String {
        let v = max(Int(t), 0)
        return String(format: "%d:%02d", v / 60, v % 60)
    }
    
    // MARK: - Gestures
    
    private var playerGestures: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded {
                if $0.translation.height > 70 { env.navigation.showLibrary() }
                if $0.translation.height < -70 { env.navigation.showLyrics() }
            }
    }
}

// MARK: - WaveformProgressView

private struct WaveformProgressView: View {
    let samples: [Float]
    let progress: Double
    let isScrubbing: Bool
    
    // Visual tuning (Poweramp-like)
    private let yPad: CGFloat = 8
    private let barWidth: CGFloat = 4
    private let minBarHeight: CGFloat = 2
    
    // Bars density (lower = fewer bars)
    private let barsPerPoint: CGFloat = 1.0 / 7.0
    
    // Keep headroom so bars never hit top/bottom
    private let headroom: CGFloat = 0.82
    
    // Shape curve: >1 keeps mids lower, improves contrast
    private let gamma: CGFloat = 1.25
    
    private func downsamplePeaks(_ input: [Float], to count: Int) -> [Float] {
        guard !input.isEmpty, count > 0 else { return [] }
        if input.count <= count { return input.map { abs($0) } }
        
        let n = input.count
        let step = Double(n) / Double(count)
        
        var out: [Float] = []
        out.reserveCapacity(count)
        
        for i in 0..<count {
            let start = Int(Double(i) * step)
            let end = min(n, Int(Double(i + 1) * step))
            if start >= end {
                out.append(abs(input[min(start, n - 1)]))
                continue
            }
            
            var peak: Float = 0
            for j in start..<end {
                let v = abs(input[j])
                if v > peak { peak = v }
            }
            out.append(peak)
        }
        return out
    }
    
    private func percentileRef(_ data: [Float], p: Double) -> Float {
        guard !data.isEmpty else { return 1 }
        let clampedP = min(max(p, 0), 1)
        let sorted = data.sorted()
        let idx = Int(round(Double(sorted.count - 1) * clampedP))
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }
    
    private func barHeight(for peak: Float, usableH: CGFloat, ref: Float) -> CGFloat {
        let denom = max(ref, 0.0001)
        let n = CGFloat(min(max(peak / denom, 0), 1))
        let shaped = pow(n, gamma)
        let target = usableH * headroom * shaped
        return max(minBarHeight, min(usableH * headroom, target))
    }
    
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            
            let usableH = max(0, h - yPad * 2)
            
            // Stable layout: compute a fixed bar grid that fills width exactly.
            let desired = max(50, min(220, Int(round(w * barsPerPoint))))
            let nBars = max(1, desired)
            let step = w / CGFloat(nBars) // fills exactly
            let xInset = max(0, (step - barWidth) * 0.5)
            
            let peaks = downsamplePeaks(samples, to: nBars)
            let ref = percentileRef(peaks, p: 0.90)
            
            let clampedP = min(max(progress, 0), 1)
            let progressX = w * clampedP
            
            var barsPath = Path()
            for i in 0..<peaks.count {
                let barH = barHeight(for: peaks[i], usableH: usableH, ref: ref)
                let x = CGFloat(i) * step + xInset
                let y = yPad + (usableH - barH) * 0.5
                
                let r = CGRect(x: x, y: y, width: barWidth, height: barH)
                let corner = CGSize(width: barWidth * 0.5, height: barWidth * 0.5)
                barsPath.addRoundedRect(in: r, cornerSize: corner)
            }
            
            // Unplayed = light
            ctx.fill(barsPath, with: .color(.white.opacity(0.55)))
            
            // Played = dark (masked to left)
            ctx.drawLayer { layer in
                var clip = Path()
                clip.addRect(CGRect(x: 0, y: 0, width: max(0, progressX), height: h))
                layer.clip(to: clip)
                layer.fill(barsPath, with: .color(.black.opacity(0.55)))
            }
            
            // Stroke: thin outline per bar
            ctx.stroke(barsPath, with: .color(.black.opacity(0.75)), lineWidth: 0.6)
            
            // Cursor: black, thin, only while scrubbing
            if isScrubbing {
                var cursor = Path()
                cursor.addRect(CGRect(x: max(0, progressX - 0.5), y: yPad, width: 1, height: usableH))
                ctx.fill(cursor, with: .color(.black.opacity(0.9)))
            }
        }
    }
}

// MARK: - RepeatMode


private enum RepeatMode: Int {
    case off, all, one
    
    var next: RepeatMode { self == .off ? .all : self == .all ? .one : .off }
    var icon: String { self == .one ? "repeat.1" : "repeat" }
}
