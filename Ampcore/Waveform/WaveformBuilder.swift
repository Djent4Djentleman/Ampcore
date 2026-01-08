import Foundation
import AVFoundation
import Accelerate

enum WaveformBuilder {
    static func buildPeaks(from url: URL, bucketCount: Int = 260) async throws -> [Float] {
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
        reader.startReading()
        
        var all: [Float] = []
        
        while reader.status == .reading {
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
        
        guard !all.isEmpty else { return [] }
        
        var absAll = [Float](repeating: 0, count: all.count)
        vDSP_vabs(all, 1, &absAll, 1, vDSP_Length(all.count))
        
        let window = max(1, absAll.count / bucketCount)
        var peaks: [Float] = []
        peaks.reserveCapacity(bucketCount)
        
        var i = 0
        while i < absAll.count {
            let end = min(absAll.count, i + window)
            var m: Float = 0
            let slice = Array(absAll[i..<end])
            vDSP_maxv(slice, 1, &m, vDSP_Length(slice.count))
            peaks.append(m)
            i += window
        }
        
        var maxVal: Float = 0
        vDSP_maxv(peaks, 1, &maxVal, vDSP_Length(peaks.count))
        guard maxVal > 0 else { return peaks }
        
        var denom = maxVal
        var norm = [Float](repeating: 0, count: peaks.count)
        vDSP_vsdiv(peaks, 1, &denom, &norm, 1, vDSP_Length(peaks.count))
        return norm
    }
}
