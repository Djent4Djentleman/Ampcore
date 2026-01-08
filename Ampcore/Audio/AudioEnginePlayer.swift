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

    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingTitle = ""
    @Published private(set) var nowPlayingArtist = ""

    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    // 0...1
    @Published var playbackProgress: Double = 0
    @Published var waveformSamples: [Float] = AudioEnginePlayer.makeDefaultWaveform()

    // Queue state
    @Published private(set) var queueTrackIDs: [NSManagedObjectID] = []
    @Published private(set) var currentTrackID: NSManagedObjectID?

    // Modes (owned by player logic)
    @Published var shuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off

    var hasLoadedFile: Bool { currentFile != nil }

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    private let eq = AVAudioUnitEQ(numberOfBands: 9)
    private let toneEQ = AVAudioUnitEQ(numberOfBands: 2)

    private let limiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    // MARK: - Playback state

    private var currentFile: AVAudioFile?
    private var currentStartFrame: AVAudioFramePosition = 0
    private var sampleRate: Double = 44100

    private var tick: AnyCancellable?
    private var finishCancellable: AnyCancellable?

    // Keep engine operations off the main thread.
    private let audioQueue = DispatchQueue(label: "ampcore.audio.engine", qos: .userInitiated)
    private var pendingSeekWork: DispatchWorkItem?

    private init() {
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

        do { try engine.start() }
        catch { print("Audio engine start error: \(error)") }

        finishCancellable = NotificationCenter.default
            .publisher(for: AudioEnginePlayer.didFinishTrack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleTrackFinished()
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

        let removedIDs: [NSManagedObjectID] = atOffsets.compactMap { idx -> NSManagedObjectID? in
            guard idx >= 0 && idx < queueTrackIDs.count else { return nil }
            return queueTrackIDs[idx]
        }

        var arr = queueTrackIDs
        for idx in atOffsets.sorted(by: >) {
            if idx >= 0 && idx < arr.count { arr.remove(at: idx) }
        }
        queueTrackIDs = arr

        if let cur = currentTrackID, removedIDs.contains(cur) {
            currentTrackID = queueTrackIDs.first
            if let first = queueTrackIDs.first, let ctx = managedObjectContext,
               let t = try? ctx.existingObject(with: first) as? CDTrack {
                play(track: t)
            } else {
                stop()
            }
        }
    }

    // Convenience for legacy call sites
    func removeFromQueue(trackID: NSManagedObjectID) {
        guard let idx = queueTrackIDs.firstIndex(of: trackID) else { return }
        removeFromQueue(atOffsets: IndexSet(integer: idx))
    }

    func clearQueue() {
        queueTrackIDs = []
        currentTrackID = nil
        stop()
    }

    func nextTrackID() -> NSManagedObjectID? {
        nextTrackID(whenEnded: false)
    }

    // MARK: - DSP (EQ / Tone / Limiter)

    func setEQEnabled(_ enabled: Bool) {
        eq.bypass = !enabled
    }

    func applyEQ(preampDB: Float, gainsDB: [Float]) {
        eq.globalGain = preampDB
        for i in 0..<min(eq.bands.count, gainsDB.count) {
            eq.bands[i].gain = gainsDB[i]
        }
    }

    func setToneEnabled(_ enabled: Bool) {
        toneEQ.bypass = !enabled
    }

    func applyTone(bassPercent: Float, treblePercent: Float) {
        // Map -100..100 to -12..12 dB
        let bassGain = max(-12, min(12, bassPercent / 100 * 12))
        let trebleGain = max(-12, min(12, treblePercent / 100 * 12))

        if toneEQ.bands.count >= 2 {
            toneEQ.bands[0].gain = bassGain
            toneEQ.bands[1].gain = trebleGain
        }
    }

    func setLimiterEnabled(_ enabled: Bool) {
        limiter.bypass = !enabled
    }

    func isLimiterEnabled() -> Bool {
        !limiter.bypass
    }

    // MARK: - Transport

    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.playerNode.stop()
            self.currentStartFrame = 0
            self.pendingSeekWork?.cancel()
            self.pendingSeekWork = nil
        }

        isPlaying = false
        tick?.cancel()
        tick = nil

        playbackProgress = 0
        currentTime = 0
    }

    func pause() {
        audioQueue.async { [weak self] in
            self?.playerNode.pause()
        }
        isPlaying = false
    }

    func resume() {
        guard currentFile != nil else { return }
        audioQueue.async { [weak self] in
            self?.playerNode.play()
        }
        isPlaying = true
        startProgressTick()
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

    private func playFile(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        currentFile = file
        sampleRate = file.processingFormat.sampleRate
        duration = Double(file.length) / max(sampleRate, 1)

        playbackProgress = 0
        currentTime = 0
        currentStartFrame = 0

        audioQueue.async { [weak self] in
            guard let self else { return }
            self.playerNode.stop()
            self.scheduleFrom(frame: 0)
            self.playerNode.play()
        }

        isPlaying = true
        startProgressTick()
    }

    /// UI seek helper.
    /// Accepts either progress (0...1) or seconds (> 1).
    func seekUI(to value: Double) {
        guard let file = currentFile else { return }

        // Debounce - commit seek after user settles.
        pendingSeekWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let sr = max(self.sampleRate, 1)

            let seconds: Double
            if value <= 1.0001 {
                seconds = max(0, min(1, value)) * (Double(file.length) / sr)
            } else {
                seconds = max(0, min(value, Double(file.length) / sr))
            }

            let targetFrame = AVAudioFramePosition(seconds * sr)

            self.audioQueue.async { [weak self] in
                guard let self, let file = self.currentFile else { return }

                self.playerNode.stop()
                self.currentStartFrame = max(0, min(targetFrame, file.length))
                self.scheduleFrom(frame: self.currentStartFrame)
                if self.isPlaying {
                    self.playerNode.play()
                }
            }
        }

        pendingSeekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    // MARK: - Queue logic

    private func handleTrackFinished() {
        guard let nextID = nextTrackID(whenEnded: true) else {
            stop()
            return
        }
        playFromQueue(id: nextID)
    }

    private func playFromQueue(id: NSManagedObjectID) {
        guard let ctx = managedObjectContext,
              let track = try? ctx.existingObject(with: id) as? CDTrack
        else {
            stop()
            return
        }
        play(track: track)
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

    // MARK: - Scheduling / progress

    private func scheduleFrom(frame start: AVAudioFramePosition) {
        guard let file = currentFile else { return }

        let clampedStart = max(0, min(start, file.length))
        let remaining = max(AVAudioFrameCount(file.length - clampedStart), 0)
        if remaining == 0 {
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return
        }

        playerNode.scheduleSegment(
            file,
            startingFrame: clampedStart,
            frameCount: remaining,
            at: nil
        ) {
            NotificationCenter.default.post(name: AudioEnginePlayer.didFinishTrack, object: nil)
        }
    }

    private func startProgressTick() {
        tick?.cancel()
        tick = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateProgress()
            }
    }

    private func updateProgress() {
        guard isPlaying else { return }

        audioQueue.async { [weak self] in
            guard let self, let file = self.currentFile else { return }
            guard
                let nodeTime = self.playerNode.lastRenderTime,
                let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime)
            else { return }

            let playedFrames = AVAudioFramePosition(playerTime.sampleTime)
            let absoluteFrame = self.currentStartFrame + playedFrames

            let progress = min(max(Double(absoluteFrame) / Double(max(file.length, 1)), 0), 1)
            let time = Double(absoluteFrame) / max(self.sampleRate, 1)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.playbackProgress = progress
                self.currentTime = time
            }
        }
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

    // MARK: - Defaults

    private func configureEQDefaults() {
        let freqs: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000]
        for i in 0..<min(eq.bands.count, freqs.count) {
            let b = eq.bands[i]
            b.filterType = .parametric
            b.frequency = freqs[i]
            b.bandwidth = 1.0
            b.gain = 0
            b.bypass = false
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
        // Defaults are fine
    }
}
