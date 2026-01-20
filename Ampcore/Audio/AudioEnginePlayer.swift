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
    private let preGainMixer = AVAudioMixerNode()
    
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
    
    // Auto-Gain state (audioQueue-only)
    private var lastEQMaxBoostDB: Float = 0
    private var lastToneMaxBoostDB: Float = 0
    private var lastLimiterDriveDB: Float = 0
    
    // Pre-gain smoothing (audioQueue-only)
    private var preGainRampToken: UInt64 = 0
    private var lastPreGainLinear: Float = 1.0
    
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
            engine.attach(preGainMixer)
            engine.attach(eq)
            engine.attach(toneEQ)
            engine.attach(limiter)
            
            engine.connect(playerNode, to: preGainMixer, format: nil)
            engine.connect(preGainMixer, to: eq, format: nil)
            engine.connect(eq, to: toneEQ, format: nil)
            engine.connect(toneEQ, to: limiter, format: nil)
            engine.connect(limiter, to: engine.mainMixerNode, format: nil)
            
            configureEQDefaults()
            configureToneDefaults()
            configureLimiterDefaults()
            
            preGainMixer.outputVolume = 1.0
            
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
    
    // MARK: - Pro Auto-Gain & Safety
    
    private func dbToLinear(_ db: Float) -> Float {
        // linear = 10^(dB/20)
        return pow(10.0, db / 20.0)
    }
    
    private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        min(max(v, lo), hi)
    }
    
    /// Smoothly ramp pre-gain to avoid audible "jumps" when enabling limiter or moving EQ/Tone.
    private func setPreGainSmooth(_ targetLinear: Float, seconds: Double = 0.18) {
        let target = clamp(targetLinear, 0.0, 1.0)
        let start = lastPreGainLinear
        let dur = max(0.0, seconds)
        if abs(start - target) < 0.0005 {
            preGainMixer.outputVolume = target
            lastPreGainLinear = target
            return
        }
        
        preGainRampToken &+= 1
        let token = preGainRampToken
        
        let steps = max(1, Int(dur / 0.02))
        let dt = dur / Double(steps)
        for i in 1...steps {
            let delay = dt * Double(i)
            audioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.preGainRampToken == token else { return }
                let t = Float(Double(i) / Double(steps))
                let v = start + (target - start) * t
                self.preGainMixer.outputVolume = v
                if i == steps {
                    self.lastPreGainLinear = target
                }
            }
        }
    }
    
    /// UI remains ±12 dB, but for cleaner, safer sound we softly cap extreme *boosts* in sub/air bands.
    private func clampedEQGain(bandIndex: Int, gainDB: Float) -> Float {
        let g = clamp(gainDB, -12, 12)
        if g <= 0 { return g }
        
        // Safety caps depend on limiter state:
        // - Limiter OFF: UI is truthful (±12 dB) even if it clips (user requested).
        // - Limiter ON: softly cap extreme boosts (especially sub/air) to reduce pumping and distortion.
        let limiterOn = !limiter.bypass
        
        switch bandIndex {
        case 0, 1, 2:
            // 31–125 Hz: allow full boost when limiter is off
            return min(g, limiterOn ? 8 : 12)
        case 7:
            // 4 kHz: mildly cap when limiter is on
            return min(g, limiterOn ? 10 : 12)
        case 8:
            // 8 kHz: cap more aggressively when limiter is on
            return min(g, limiterOn ? 8 : 12)
        default:
            return g
        }
    }
    
    /// Recompute pre-gain headroom so EQ/Tone boosts don't constantly hit the limiter.
    /// Pro strategy: take the maximum positive boost and apply partial compensation (keeps punch).
    private func updateAutoGainLocked() {
        // User requirement:
        // - When limiter is OFF: do not change overall loudness; allow clipping if user boosts EQ.
        // - When limiter is ON: apply gentle, smooth headroom compensation to reduce clipping/pumping.
        guard !limiter.bypass else {
            setPreGainSmooth(1.0, seconds: 0.10)
            return
        }
        
        let maxBoost = max(0, max(lastEQMaxBoostDB, lastToneMaxBoostDB))
        
        // Gentle compensation: preserve perceived loudness while creating enough headroom.
        let compensationStrength: Float = 0.35
        let headroomDB: Float = 1.0
        let targetDB = -max(0, maxBoost - headroomDB) * compensationStrength
        let clampedDB = clamp(targetDB, -9, 0)
        setPreGainSmooth(dbToLinear(clampedDB), seconds: 0.18)
    }
    
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
            
            // UI remains ±12 dB. When limiter is ON we softly cap extreme boosts (see clampedEQGain)
            // to reduce audible pumping/distortion. When limiter is OFF we allow full range (user requested).
            let n = min(self.eq.bands.count, gainsDB.count)
            var applied: [Float] = []
            applied.reserveCapacity(n)
            
            for i in 0..<n {
                let g = self.clampedEQGain(bandIndex: i, gainDB: gainsDB[i])
                applied.append(g)
                self.eq.bands[i].gain = g
            }
            
            // Apply user preamp directly (still useful if you want to trim overall level).
            self.eq.globalGain = max(-24, min(24, preampDB))
            
            // Update Auto-Gain based on max positive EQ boost.
            self.lastEQMaxBoostDB = max(0, applied.max() ?? 0)
            self.updateAutoGainLocked()
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
            
            // Pro rule for Tone in AmpCore:
            // - 0% = 0 dB (neutral)
            // - >0% = boost only
            // - When limiter is ON, treble boost is softly reduced at very high Drive to prevent audible pumping.
            let bP = max(0, min(100, bassPercent)) / 100
            let tP = max(0, min(100, treblePercent)) / 100
            
            let limiterOn = !self.limiter.bypass
            
            // lastLimiterDriveDB is ~0..7 dB in our mapping. Normalize to 0..1.
            let driveNorm = clamp(self.lastLimiterDriveDB / 7.0, 0, 1)
            
            let bassMax: Float = 12
            // Limiter ON: treble max is 8 dB at low drive, down to ~6 dB at max drive.
            // Limiter OFF: allow full 12 dB (user wants freedom even if it clips).
            let trebleMax: Float = limiterOn ? (8 - 2 * driveNorm) : 12
            
            // Nonlinear curve: more resolution at low values, less aggressive at the top.
            let bassGain: Float = bassMax * powf(bP, 1.15)
            let trebleGain: Float = trebleMax * powf(tP, 1.60)
            
            if self.toneEQ.bands.count >= 2 {
                self.toneEQ.bands[0].gain = bassGain
                self.toneEQ.bands[1].gain = trebleGain
            }
            
            self.lastToneMaxBoostDB = max(bassGain, trebleGain)
            self.updateAutoGainLocked()
        }
    }
    
    func setLimiterEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.limiter.bypass = !enabled
            // When turning limiter OFF, keep loudness constant (no auto-gain). When ON, re-evaluate headroom.
            self.updateAutoGainLocked()
        }
    }
    
    func isLimiterEnabled() -> Bool {
        !limiter.bypass
    }
    
    
    /// 0...100% amount maps to PeakLimiter pre-gain/attack/release.
    /// 0% is neutral (no added drive).
    func applyLimiterAmount(_ percent: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let p = max(0, min(100, percent)) / 100
            
            
            // Pro-safe mapping: avoid audible pumping, especially with high Treble + Drive.
            // Percent controls *protection strength*, not "make it loud".
            let totalBoost = max(self.lastEQMaxBoostDB, self.lastToneMaxBoostDB) // 0..12
            let boostPenalty = clamp((totalBoost - 3) / 9, 0, 1) // starts penalizing after +3 dB boost
            
            // Drive: 0 dB .. +7 dB with gentle curve; further reduced when boosts are high.
            let baseDrive: Float = 7 * powf(p, 1.20)
            let driveDB: Float = baseDrive * (1 - 0.70 * boostPenalty)
            
            // PeakLimiter params (seconds)
            // Longer release prevents audible "up-down" pumping. Slightly longer at higher amounts.
            let attack: Float = 0.0010 // 1 ms
            let release: Float = 0.12 + (0.38 * p) // 120 ms .. 500 ms
            
            let au = self.limiter.audioUnit
            AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, attack, 0)
            AudioUnitSetParameter(au, kLimiterParam_DecayTime,  kAudioUnitScope_Global, 0, release, 0)
            AudioUnitSetParameter(au, kLimiterParam_PreGain,    kAudioUnitScope_Global, 0, driveDB, 0)
            self.lastLimiterDriveDB = driveDB
        }
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
        // Bandwidth is in octaves. Wider in low-end, slightly narrower in highs for a more 'pro' curve.
        let bws: [Float] = [2.6, 2.0, 1.4, 1.15, 1.05, 1.0, 0.95, 0.85, 0.8]
        for i in 0..<min(eq.bands.count, freqs.count) {
            let b = eq.bands[i]
            b.filterType = .parametric
            b.frequency = freqs[i]
            b.bandwidth = bws[min(i, bws.count - 1)]
            b.gain = 0
            b.bypass = true
        }
        eq.globalGain = 0
    }
    
    private func configureToneDefaults() {
        if toneEQ.bands.count >= 1 {
            let b = toneEQ.bands[0]
            b.filterType = .lowShelf
            b.frequency = 90
            b.gain = 0
            b.bypass = false
        }
        if toneEQ.bands.count >= 2 {
            let b = toneEQ.bands[1]
            b.filterType = .highShelf
            b.frequency = 7500
            b.gain = 0
            b.bypass = false
        }
    }
    
    private func configureLimiterDefaults() {
        // PeakLimiter defaults (neutral but safe)
        let au = limiter.audioUnit
        AudioUnitSetParameter(au, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.0010, 0)
        AudioUnitSetParameter(au, kLimiterParam_DecayTime,  kAudioUnitScope_Global, 0, 0.12,   0)
        AudioUnitSetParameter(au, kLimiterParam_PreGain,    kAudioUnitScope_Global, 0, 0.0,    0)
    }
}
