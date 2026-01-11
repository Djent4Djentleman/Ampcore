// WaveformBuilder.swift
import Foundation
import AVFoundation
import Accelerate

enum WaveformBuilder {
    static func buildPeaks(from url: URL, bucketCount: Int = 260) async throws -> [Float] {
        try Task.checkCancellation()
        
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        
        guard reader.startReading() else {
            throw reader.error ?? NSError(domain: "WaveformBuilder", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed to start"])
        }
        
        var all: [Float] = []
        all.reserveCapacity(1_000_000)
        
        while true {
            try Task.checkCancellation()
            
            guard let sb = output.copyNextSampleBuffer(),
                  let block = CMSampleBufferGetDataBuffer(sb) else { break }
            
            let len = CMBlockBufferGetDataLength(block)
            var data = Data(count: len)
            data.withUnsafeMutableBytes { dst in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: dst.baseAddress!)
            }
            
            let n = len / MemoryLayout<Float>.size
            data.withUnsafeBytes { ptr in
                let buf = ptr.bindMemory(to: Float.self)
                all.append(contentsOf: buf[0..<n])
            }
            
            CMSampleBufferInvalidate(sb)
        }
        
        if reader.status == .failed {
            throw reader.error ?? NSError(domain: "WaveformBuilder", code: -2, userInfo: [NSLocalizedDescriptionKey: "AVAssetReader failed"])
        }
        
        try Task.checkCancellation()
        guard !all.isEmpty else { return [] }
        
        var absAll = [Float](repeating: 0, count: all.count)
        vDSP_vabs(all, 1, &absAll, 1, vDSP_Length(all.count))
        
        let buckets = max(16, bucketCount)
        let step = Double(absAll.count) / Double(buckets)
        
        var out = [Float](repeating: 0, count: buckets)
        
        absAll.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for i in 0..<buckets {
                let start = Int(Double(i) * step)
                let end = min(absAll.count, Int(Double(i + 1) * step))
                if start >= end { out[i] = 0; continue }
                
                var rms: Float = 0
                vDSP_rmsqv(base.advanced(by: start), 1, &rms, vDSP_Length(end - start))
                out[i] = rms
            }
        }
        
        try Task.checkCancellation()
        out = smooth(out)
        
        let ref = percentile(out, p: 0.99)
        guard ref > 0 else { return out }
        
        var denom = ref * 1.15
        var norm = [Float](repeating: 0, count: out.count)
        vDSP_vsdiv(out, 1, &denom, &norm, 1, vDSP_Length(out.count))
        
        var lo: Float = 0
        var hi: Float = 1
        vDSP_vclip(norm, 1, &lo, &hi, &norm, 1, vDSP_Length(norm.count))
        return norm
    }
    
    private static func smooth(_ v: [Float]) -> [Float] {
        guard v.count >= 3 else { return v }
        var out = v
        for i in 1..<(v.count - 1) {
            out[i] = (v[i - 1] + v[i] + v[i + 1]) / 3
        }
        return out
    }
    
    private static func percentile(_ data: [Float], p: Double) -> Float {
        guard !data.isEmpty else { return 1 }
        let clamped = min(max(p, 0), 1)
        let sorted = data.sorted()
        let idx = Int((Double(sorted.count - 1) * clamped).rounded(.toNearestOrAwayFromZero))
        return sorted[min(max(idx, 0), sorted.count - 1)]
    }
}
