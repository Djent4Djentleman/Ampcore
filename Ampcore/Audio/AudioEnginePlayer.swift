import Foundation
import Combine
import AVFoundation
import AudioToolbox
import CoreData
import UIKit

final class AudioEnginePlayer: ObservableObject {
    static let shared = AudioEnginePlayer()
    
    // Injected from AppEnvironment
    var managedObjectContext: NSManagedObjectContext?
    
    static let didFinishTrack = Notification.Name("AudioEnginePlayer.didFinishTrack")
    
    enum RepeatMode: Int, CaseIterable {
        case off = 0
        case all = 1
        case one = 2
    }
    
    // MARK: - Published state (UI)
    
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingTitle = ""
    @Published private(set) var nowPlayingArtist = ""
    
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    
    @Published var playbackProgress: Double = 0
    @Published var waveformSamples: [Float] = []
    
    // Queue state
    @Published private(set) var queueTrackIDs: [NSManagedObjectID] = []
    @Published private(set) var currentTrackID: NSManagedObjectID?
    
    // Modes (owned by player logic)
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    
    var hasLoadedFile: Bool { currentFile != nil }
    
    // MARK: - Engine / DSP
    
    private let audioQueue = DispatchQueue(label: "AudioEnginePlayer.audio", qos: .userInitiated)
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private let eq = AVAudioUnitEQ(numberOfBands: 9)
    private let toneEQ = AVAudioUnitEQ(numberOfBands: 2)
    
    private let limiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()
    
    // MARK: - Playback state (audioQueue-only)
    
    private var currentFile: AVAudioFile?
    private var currentStartFrame: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100
    
    private var progressTimer: DispatchSourceTimer?
    private var scheduleToken: UInt64 = 0
    private var pendingSeekWork: DispatchWorkItem?
    // MARK: - UI Sync
    
    private var uiScrubLock: Bool = false
    private var pendingScrubUnlockWork: DispatchWorkItem?
    
    // MARK: - Runtime Settings (audioQueue)
    
    private struct RuntimeSettings {
        var fadeTransportEnabled: Bool = false
        var fadeTransportSeconds: Double = 0.30
        var fadeSeekEnabled: Bool = false
        var fadeSeekSeconds: Double = 0.08
    }
    
    private var runtimeSettings = RuntimeSettings()
    private var fadeToken: UInt64 = 0
    
    
    private init() {
        audioQueue.sync {
            engine.attach(playerNode)
            engine.attach(eq)
            engine.attach(toneEQ)
            engine.attach(limiter)
            
            engine.connect(playerNode, to: eq, format: nil)
            engine.connect(eq, to: toneEQ, format: nil)
            engine.connect(toneEQ, to: limiter, format: nil)
            engine.connect(limiter, to: engine.mainMixerNode, format: nil)
            
            configureEQDefaults()
            configureToneDefaults()
            configureLimiterDefaults()
            
            // Default DSP off
            eq.bypass = true
            toneEQ.bypass = true
            limiter.bypass = true
            
            do { try engine.start() }
            catch { print("Audio engine start error: \(error)") }
        }
    }
    
    
    // MARK: - Settings
    
    /// Snapshot settings on MainActor and apply on audioQueue.
    func applySettings(_ settings: AppSettings) {
        let snap = RuntimeSettings(
            fadeTransportEnabled: settings.fadeTransportEnabled,
            fadeTransportSeconds: settings.fadeTransportSeconds,
            fadeSeekEnabled: settings.fadeSeekEnabled,
            fadeSeekSeconds: settings.fadeSeekSeconds
        )
        audioQueue.async { [weak self] in
            self?.runtimeSettings = snap
        }
    }
    
    // MARK: - Queue API (used by UI)
    
    func setQueue(ids: [NSManagedObjectID], startAt: NSManagedObjectID?) {
        queueTrackIDs = ids
        if let startAt {
            currentTrackID = startAt
            if !queueTrackIDs.contains(startAt) {
                queueTrackIDs.insert(startAt, at: 0)
            }
        }
    }
    
    func moveQueue(fromOffsets: IndexSet, toOffset: Int) {
        guard !fromOffsets.isEmpty else { return }
        
        var arr = queueTrackIDs
        let moving = fromOffsets.sorted()
        let elements = moving.compactMap { idx -> NSManagedObjectID? in
            guard idx >= 0 && idx < arr.count else { return nil }
            return arr[idx]
        }
        
        for idx in moving.sorted(by: >) {
            if idx >= 0 && idx < arr.count { arr.remove(at: idx) }
        }
        
        var target = toOffset
        let removedBefore = moving.filter { $0 < toOffset }.count
        target -= removedBefore
        target = max(0, min(target, arr.count))
        
        arr.insert(contentsOf: elements, at: target)
        queueTrackIDs = arr
    }
    
    func removeFromQueue(atOffsets: IndexSet) {
        guard !atOffsets.isEmpty else { return }
        
        let removedIDs: [NSManagedObjectID] = atOffsets.compactMap { idx in
            guard idx >= 0 && idx < queueTrackIDs.count else { return nil }
            return queueTrackIDs[idx]
        }
        
        var arr = queueTrackIDs
        for idx in atOffsets.sorted(by: >) {
            if idx >= 0 && idx < arr.count { arr.remove(at: idx) }
        }
        queueTrackIDs = arr
        
        if let currentTrackID, removedIDs.contains(currentTrackID) {
            self.currentTrackID = queueTrackIDs.first
            if let first = queueTrackIDs.first,
               let ctx = managedObjectContext,
               let t = try? ctx.existingObject(with: first) as? CDTrack {
                play(track: t)
            } else {
                clearQueue()
            }
        }
    }
    
    func removeFromQueue(trackID: NSManagedObjectID) {
        guard let idx = queueTrackIDs.firstIndex(of: trackID) else { return }
        removeFromQueue(atOffsets: IndexSet(integer: idx))
    }
    
    func clearQueue() {
        queueTrackIDs = []
        currentTrackID = nil
        stop()
    }
    
    // MARK: - DSP (EQ / Tone / Limiter)
    
    func setEQEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.eq.bypass = !enabled
            for b in self.eq.bands {
                b.bypass = !enabled
            }
        }
    }
    
    func isEQEnabled() -> Bool {
        audioQueue.sync { !eq.bypass }
    }
    
    func applyEQ(preampDB: Float, gainsDB: [Float]) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            // Loudness/Headroom handling:
            // The previous implementation fully subtracted the maximum positive band gain
            // from the global gain, which could make the audio sound noticeably quieter
            // as soon as a preset with boosts is selected.
            //
            // Here we keep a bit of headroom to reduce clipping risk, but we compensate
            // more gently so the perceived loudness doesn't drop as much.
            let maxBoost = max(0, gainsDB.max() ?? 0)
            let headroomDB: Float = 1.0
            let compensationStrength: Float = 0.70
            let compensation = max(0, maxBoost - headroomDB) * compensationStrength
            let compensated = preampDB - compensation
            self.eq.globalGain = max(-24, min(24, compensated))
            for i in 0..<min(self.eq.bands.count, gainsDB.count) {
                self.eq.bands[i].gain = gainsDB[i]
            }
        }
    }
    
    func setToneEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            self?.toneEQ.bypass = !enabled
        }
    }
    
    func isToneEnabled() -> Bool {
        audioQueue.sync { !toneEQ.bypass }
    }
    
    func applyTone(bassPercent: Float, treblePercent: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let bassClamped = max(0, min(100, bassPercent))
            let trebleClamped = max(0, min(100, treblePercent))
            let bassGain = max(0, min(12, (bassClamped / 100) * 12))
            let trebleGain = max(0, min(12, (trebleClamped / 100) * 12))
            
            if self.toneEQ.bands.count >= 2 {
                self.toneEQ.bands[0].gain = bassGain
                self.toneEQ.bands[1].gain = trebleGain
            }
        }
    }
    
    func setLimiterEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            self?.limiter.bypass = !enabled
        }
    }
    
    func isLimiterEnabled() -> Bool {
        audioQueue.sync { !limiter.bypass }
    }
    
    /// Pro limiter control.
    /// - 0%: neutral (0 dB drive).
    /// - 100%: strong peak control (up to +12 dB drive).
    func applyLimiter(amountPercent: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let a = max(0, min(100, amountPercent))
            let x = a / 100
            
            // Smooth, musical mapping (more resolution in the low range).
            let shaped = pow(x, 1.6)
            let preGainDB: Float = shaped * 12.0
            
            // PeakLimiter params are in seconds. Keep attack fast, release scales with amount.
            let attack: Float = 0.002
            let release: Float = 0.005 + pow(x, 1.3) * 0.025
            
            self.setPeakLimiterParams(attack: attack, release: release, preGainDB: preGainDB)
        }
    }
    
    private func setPeakLimiterParams(attack: Float, release: Float, preGainDB: Float) {
        // Peak Limiter parameters:
        // kLimiterParam_AttackTime = 0 (0.0005 .. 0.03)
        // kLimiterParam_DecayTime  = 1 (release) (0.001 .. 0.04)
        // kLimiterParam_PreGain    = 2 (-40 .. 40)
        // Source: AudioUnitParameters.h and Apple docs.
        // (PeakLimiter AU)
        let a = max(0.0005, min(0.03, attack))
        let r = max(0.001, min(0.04, release))
        let g = max(-40.0, min(40.0, preGainDB))
        
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, a, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_DecayTime,  kAudioUnitScope_Global, 0, r, 0)
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain,    kAudioUnitScope_Global, 0, g, 0)
    }
    
    
    // MARK: - Transport
    
    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let cfg = self.runtimeSettings
            
            let doStop = { [weak self] in
                guard let self else { return }
                self.playerNode.stop()
                self.engine.mainMixerNode.outputVolume = 1.0
                self.currentFile = nil
                self.currentStartFrame = 0
                self.stopProgressTimer()
                
                self.publish {
                    self.isPlaying = false
                    self.playbackProgress = 0
                    self.currentTime = 0
                    self.duration = 0
                    self.waveformSamples = []
                }
            }
            
            if cfg.fadeTransportEnabled {
                self.fadeMixer(to: 0.0, seconds: cfg.fadeTransportSeconds) {
                    doStop()
                }
            } else {
                doStop()
            }
        }
    }
    
    func pause() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let cfg = self.runtimeSettings
            
            if cfg.fadeTransportEnabled {
                self.fadeMixer(to: 0.0, seconds: cfg.fadeTransportSeconds) { [weak self] in
                    guard let self else { return }
                    self.playerNode.pause()
                    self.engine.mainMixerNode.outputVolume = 1.0
                    self.publish { self.isPlaying = false }
                }
            } else {
                self.playerNode.pause()
                self.publish { self.isPlaying = false }
            }
        }
    }
    
    func resume() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.currentFile != nil else { return }
            let cfg = self.runtimeSettings
            
            if cfg.fadeTransportEnabled {
                self.engine.mainMixerNode.outputVolume = 0.0
                self.playerNode.play()
                self.fadeMixer(to: 1.0, seconds: cfg.fadeTransportSeconds, completion: nil)
            } else {
                self.playerNode.play()
            }
            self.startProgressTimer()
            self.updateProgressOnce()
            self.publish { self.isPlaying = true }
        }
    }
    
    func play(track: CDTrack) {
        let rel = track.relativePath
        guard !rel.isEmpty else { return }
        
        do {
            let folderURL = try FolderAccess.shared.resolveFolderURL()
            try FolderAccess.shared.withAccess(folderURL) {
                let fileURL = folderURL.appendingPathComponent(rel)
                try self.playFile(url: fileURL)
                self.loadWaveformIfNeeded(track: track, fileURL: fileURL)
            }
            
            nowPlayingTitle = track.title
            nowPlayingArtist = track.artist ?? ""
            currentTrackID = track.objectID

            // Stats (Most Played / Recently Played)
            if let moc = managedObjectContext {
                let trackID = track.objectID
                moc.perform {
                    do {
                        if let t = try moc.existingObject(with: trackID) as? CDTrack {
                            t.playCount += 1
                            t.lastPlayedAt = Date()
                            try moc.save()
                        }
                    } catch { }
                }
            }

            
            ensureInQueue(track.objectID)
        } catch {
            stop()
        }
    }
    
    // MARK: - Seeking (UI)
    
    /// Accepts either progress (0...1) or seconds (> 1). Keeps old call sites stable.
    func seekUI(to value: Double) {
        // Debounce so quick repeated calls don't thrash the node.
        audioQueue.async { [weak self] in
            guard let self else { return }
            
            self.uiScrubLock = true
            self.pendingScrubUnlockWork?.cancel()
            
            self.pendingSeekWork?.cancel()
            
            let cfg = self.runtimeSettings
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                
                if cfg.fadeSeekEnabled {
                    self.fadeMixer(to: 0.0, seconds: cfg.fadeSeekSeconds) { [weak self] in
                        guard let self else { return }
                        self.performSeekUI(to: value)
                        self.fadeMixer(to: 1.0, seconds: cfg.fadeSeekSeconds, completion: nil)
                    }
                } else {
                    self.performSeekUI(to: value)
                }
                
                let unlock = DispatchWorkItem { [weak self] in
                    self?.uiScrubLock = false
                    self?.pendingScrubUnlockWork = nil
                }
                self.pendingScrubUnlockWork = unlock
                self.audioQueue.asyncAfter(deadline: .now() + 0.12, execute: unlock)
            }
            
            self.pendingSeekWork = work
            self.audioQueue.async(execute: work)
        }
    }
    
    private func performSeekUI(to value: Double) {
        guard let file = currentFile else { return }
        
        let wasPlaying = isPlaying
        let targetSeconds: Double
        if value >= 0, value <= 1, duration > 1 {
            targetSeconds = value * duration
        } else {
            targetSeconds = max(0, min(value, duration))
        }
        
        let sr = max(sampleRate, 1)
        let maxSeconds = Double(file.length) / sr
        let clampedSeconds = max(0, min(targetSeconds, maxSeconds))
        
        // UI sync (paused seek needs this)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentTime = clampedSeconds
            let p = maxSeconds > 0 ? (clampedSeconds / maxSeconds) : 0
            self.playbackProgress = max(0, min(p, 1))
        }
        let targetFrame = AVAudioFramePosition(clampedSeconds * sr)
        
        scheduleToken &+= 1
        let token = scheduleToken
        
        playerNode.stop()
        currentStartFrame = targetFrame
        scheduleFrom(frame: targetFrame, token: token)
        
        if wasPlaying {
            playerNode.play()
        }
        
        startProgressTimer()
        updateProgressOnce()
    }
    
    // MARK: - Queue navigation
    
    func nextTrackID() -> NSManagedObjectID? {
        nextTrackID(whenEnded: false)
    }
    
    func nextTrackID(whenEnded: Bool) -> NSManagedObjectID? {
        guard !queueTrackIDs.isEmpty else { return nil }
        guard let currentTrackID else { return queueTrackIDs.first }
        
        if repeatMode == .one, whenEnded {
            return currentTrackID
        }
        
        if shuffleEnabled {
            let candidates = queueTrackIDs.filter { $0 != currentTrackID }
            return candidates.randomElement() ?? currentTrackID
        }
        
        guard let idx = queueTrackIDs.firstIndex(of: currentTrackID) else {
            return queueTrackIDs.first
        }
        
        let next = idx + 1
        if next < queueTrackIDs.count {
            return queueTrackIDs[next]
        }
        
        return repeatMode == .all ? queueTrackIDs.first : nil
    }
    
    func prevTrackID() -> NSManagedObjectID? {
        guard !queueTrackIDs.isEmpty else { return nil }
        guard let currentTrackID else { return queueTrackIDs.first }
        
        if shuffleEnabled {
            let candidates = queueTrackIDs.filter { $0 != currentTrackID }
            return candidates.randomElement() ?? currentTrackID
        }
        
        guard let idx = queueTrackIDs.firstIndex(of: currentTrackID) else {
            return queueTrackIDs.first
        }
        
        let prev = idx - 1
        if prev >= 0 {
            return queueTrackIDs[prev]
        }
        
        return repeatMode == .all ? queueTrackIDs.last : nil
    }
    
    private func ensureInQueue(_ id: NSManagedObjectID) {
        if !queueTrackIDs.contains(id) {
            queueTrackIDs.append(id)
        }
    }
    
    // MARK: - File scheduling / progress (audioQueue-only)
    
    private func playFile(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        
        audioQueue.async { [weak self] in
            guard let self else { return }
            
            self.currentFile = file
            self.sampleRate = file.processingFormat.sampleRate
            let dur = Double(file.length) / max(self.sampleRate, 1)
            
            self.playerNode.stop()
            self.currentStartFrame = 0
            
            self.scheduleToken &+= 1
            let token = self.scheduleToken
            self.scheduleFrom(frame: 0, token: token)
            
            self.playerNode.play()
            self.startProgressTimer()
            
            self.publish {
                self.duration = dur
                self.playbackProgress = 0
                self.currentTime = 0
                self.isPlaying = true
            }
        }
    }
    
    private func scheduleFrom(frame start: AVAudioFramePosition, token: UInt64) {
        guard let file = currentFile else { return }
        
        let remainingFrames = max(AVAudioFrameCount(file.length - start), 0)
        if remainingFrames == 0 {
            publish { self.isPlaying = false }
            return
        }
        
        playerNode.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: remainingFrames,
            at: nil
        ) { [weak self] in
            guard let self else { return }
            // Ignore stale completions (e.g. seek reschedules).
            self.audioQueue.async {
                guard token == self.scheduleToken else { return }
                NotificationCenter.default.post(name: AudioEnginePlayer.didFinishTrack, object: nil)
            }
        }
    }
    
    
    // MARK: - Fades
    
    /// Linear volume ramp on mainMixer. Runs on audioQueue.
    private func fadeMixer(to target: Float, seconds: Double, completion: (() -> Void)?) {
        fadeToken &+= 1
        let token = fadeToken
        
        let mixer = engine.mainMixerNode
        let start = mixer.outputVolume
        let clampedSeconds = max(0.0, seconds)
        
        if clampedSeconds <= 0.0001 {
            mixer.outputVolume = target
            completion?()
            return
        }
        
        let steps = max(1, Int(clampedSeconds / 0.02))
        let dt = clampedSeconds / Double(steps)
        
        for i in 1...steps {
            let delay = dt * Double(i)
            audioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.fadeToken == token else { return }
                
                let t = Float(Double(i) / Double(steps))
                mixer.outputVolume = start + (target - start) * t
                
                if i == steps {
                    completion?()
                }
            }
        }
    }
    
    private func startProgressTimer() {
        if progressTimer != nil { return }
        
        let t = DispatchSource.makeTimerSource(queue: audioQueue)
        t.schedule(deadline: .now(), repeating: 0.05)
        t.setEventHandler { [weak self] in
            self?.updateProgressOnce()
        }
        progressTimer = t
        t.resume()
    }
    
    private func stopProgressTimer() {
        progressTimer?.cancel()
        progressTimer = nil
    }
    
    private func updateProgressOnce() {
        if uiScrubLock { return }
        guard let file = currentFile else { return }
        guard
            let nodeTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return }
        
        let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
        let absoluteFrame = currentStartFrame + playedFrames
        
        let p = min(max(Double(absoluteFrame) / Double(max(file.length, 1)), 0), 1)
        let t = Double(absoluteFrame) / max(sampleRate, 1)
        
        publish {
            self.playbackProgress = p
            self.currentTime = t
        }
    }
    
    private func publish(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
    
    // MARK: - Waveform
    
    private func loadWaveformIfNeeded(track: CDTrack, fileURL: URL) {
        let id = track.id
        
        Task { @MainActor in
            if let cached = await WaveformCache.shared.load(id: id) {
                self.waveformSamples = cached
                return
            }
            
            do {
                let peaks = try await WaveformBuilder.buildPeaks(from: fileURL, bucketCount: 260)
                if !peaks.isEmpty {
                    self.waveformSamples = peaks
                    await WaveformCache.shared.save(peaks, id: id)
                }
            } catch {}
        }
    }
    
    private static func makeDefaultWaveform() -> [Float] {
        (0..<240).map { i in
            let x = Double(i) * 0.18
            return Float(min(1, abs(sin(x)) * 0.9 + 0.1))
        }
    }
    
    // MARK: - DSP defaults
    
    private func configureEQDefaults() {
        let freqs: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000]
        for i in 0..<min(eq.bands.count, freqs.count) {
            let b = eq.bands[i]
            b.filterType = .parametric
            b.frequency = freqs[i]
            b.bandwidth = 1.0
            b.gain = 0
            b.bypass = true
        }
        eq.globalGain = 0
    }
    
    private func configureToneDefaults() {
        if toneEQ.bands.count >= 1 {
            let b = toneEQ.bands[0]
            b.filterType = .lowShelf
            b.frequency = 120
            b.gain = 0
            b.bypass = false
        }
        if toneEQ.bands.count >= 2 {
            let b = toneEQ.bands[1]
            b.filterType = .highShelf
            b.frequency = 8000
            b.gain = 0
            b.bypass = false
        }
    }
    
    private func configureLimiterDefaults() {
        // Neutral defaults for Peak Limiter.
        // Keep the limiter from coloring the audio when enabled at 0%.
        setPeakLimiterParams(attack: 0.002, release: 0.010, preGainDB: 0.0)
    }
}
