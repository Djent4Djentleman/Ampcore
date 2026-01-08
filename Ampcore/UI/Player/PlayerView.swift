import SwiftUI
import Combine
import CoreData
import UIKit

struct PlayerView: View {
    @EnvironmentObject private var env: AppEnvironment
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
        VStack(spacing: 14) {
            topBar
            coverBlock
            
            if hasTrack {
                modesBlock
                
                waveformContainer
                
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
        .padding(.horizontal, 16)
        .padding(.top, 10)
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
    
    // MARK: - Top bar
    
    private var topBar: some View {
        HStack(spacing: 16) {
            Button { env.navigation.showLibrary() } label: {
                Image(systemName: "music.note.list")
            }
            
            Button { env.navigation.showPlayer() } label: {
                Image(systemName: "play.circle.fill")
            }
            
            Button { env.navigation.showLibrary() } label: {
                Image(systemName: "magnifyingglass")
            }
            
            Spacer()
            
            Button { showSettingsSheet = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white.opacity(0.92))
    }
    
    // MARK: - Cover
    
    private var coverBlock: some View {
        let side = min(UIScreen.main.bounds.width - 32, 320)
        
        return ZStack(alignment: .bottomLeading) {
            coverImage
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 28, x: 0, y: 16)
            
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(env.player.nowPlayingTitle.isEmpty ? "—" : env.player.nowPlayingTitle)
                    .font(.headline.weight(.semibold))
                Text(env.player.nowPlayingArtist)
                    .font(.subheadline)
                    .opacity(0.75)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(maxWidth: .infinity)
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
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let w = max(width, 1)
                let p = min(max(Double(v.location.x / w), 0), 1)
                if !isWaveScrubbing { isWaveScrubbing = true }
                if !isScrubbing { isScrubbing = true }
                scrubProgress = p
            }
            .onEnded { _ in
                isWaveScrubbing = false
                isScrubbing = false
                env.player.seekUI(to: scrubProgress) // progress 0...1
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
    
    private var coverImage: some View {
        Group {
            if let d = track?.artworkData, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image("DefaultArtwork").resizable().scaledToFill()
            }
        }
    }
    
    private var backgroundView: some View {
        ZStack {
            coverImage.blur(radius: 70).opacity(0.35)
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
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

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let insetX: CGFloat = 10
            let insetY: CGFloat = 10
            let innerW = max(w - insetX * 2, 1)
            let innerH = max(h - insetY * 2, 1)

            let count = max(samples.count, 1)
            let step = innerW / CGFloat(count)
            let barW = max(1, step * 0.7)
            let radius = barW * 0.5

            let clamped = min(max(progress, 0), 1)
            let filledCount = Int((CGFloat(clamped) * CGFloat(count)).rounded(.down))

            func barRect(_ i: Int, amp: CGFloat) -> CGRect {
                let x = insetX + CGFloat(i) * step + (step - barW) * 0.5
                let bh = max(2, innerH * amp)
                let y = insetY + (innerH - bh) * 0.5
                return CGRect(x: x, y: y, width: barW, height: bh)
            }

            // Background bars
            var bgPath = Path()
            bgPath.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h), cornerSize: CGSize(width: 16, height: 16))
            context.clip(to: bgPath)

            for i in 0..<count {
                let amp = CGFloat(min(max(samples[safe: i] ?? 0, 0), 1))
                let r = barRect(i, amp: amp)
                let p = Path(roundedRect: r, cornerRadius: radius)
                context.fill(p, with: .color(.white.opacity(0.18)))
            }

            // Foreground bars (up to progress)
            let fgOpacity: Double = isScrubbing ? 0.85 : 0.65
            if filledCount > 0 {
                for i in 0..<min(filledCount, count) {
                    let amp = CGFloat(min(max(samples[safe: i] ?? 0, 0), 1))
                    let r = barRect(i, amp: amp)
                    let p = Path(roundedRect: r, cornerRadius: radius)
                    context.fill(p, with: .color(.white.opacity(fgOpacity)))
                }
            }

            // Playhead
            let progressX = insetX + innerW * CGFloat(clamped)
            let lineRect = CGRect(x: max(insetX, min(progressX, insetX + innerW)) - 1,
                                  y: insetY,
                                  width: 2,
                                  height: innerH)
            let linePath = Path(lineRect)
            context.fill(linePath, with: .color(.white.opacity(isScrubbing ? 0.9 : 0.55)))

            // Background plate
            let plate = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                             cornerRadius: 16)
            context.stroke(plate, with: .color(.white.opacity(0.06)), lineWidth: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension Array where Element == Float {
    subscript(safe index: Int) -> Float? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

// MARK: - RepeatMode

private enum RepeatMode: Int {
    case off, all, one
    
    var next: RepeatMode { self == .off ? .all : self == .all ? .one : .off }
    var icon: String { self == .one ? "repeat.1" : "repeat" }
}
