import Foundation
import AVFoundation

let data = MLB300HitterData.seasons
precondition(data.count == 51)
precondition(data.map(\.year) == Array(1976...2026))
precondition(data.allSatisfy { $0.count >= 0 })
precondition(MLB300HitterData.peak == .init(year: 1999, count: 51))
precondition(MLB300HitterData.finish == .init(year: 2026, count: 6, isProvisional: true))
precondition(MLB300HitterData.decline == 88)
precondition(data.filter { $0.count == data.map(\.count).min() }.map(\.year) == [2025, 2026])
precondition(data.filter(\.isProvisional).map(\.year) == [2026])
precondition(data.first { $0.year == 2025 } == .init(year: 2025, count: 6))
precondition(MLB300HitterData.finish.label == "2026 YTD")
// Completion is time-based, including skipped frames and replay's zero point.
precondition(MLB300HitterData.progress(elapsed: -1) == 0)
precondition(MLB300HitterData.progress(elapsed: 0) == 0)
precondition(MLB300HitterData.progress(elapsed: 5) == 0.5)
precondition(MLB300HitterData.progress(elapsed: 9.999) < 1)
precondition(MLB300HitterData.progress(elapsed: 10) == 1)
precondition(MLB300HitterData.progress(elapsed: 11) == 1)
for index in data.indices {
    precondition(MLB300HitterData.pointOpacity(index: index, elapsed: 0) == 0)
    precondition(MLB300HitterData.pointOpacity(index: index, elapsed: 9) == 1)
}
print("PASS: 50 completed seasons plus provisional 2026, endpoints, peak, decline, 10-second timing, nine-second point fade")

let sound = StoryAudioLoop.makeData()
let soundURL = FileManager.default.temporaryDirectory.appendingPathComponent("hub-hitter-\(UUID().uuidString).wav")
try sound.write(to: soundURL)
defer { try? FileManager.default.removeItem(at: soundURL) }
let audioFile = try AVAudioFile(forReading: soundURL)
precondition(audioFile.length == 176_400)
precondition(audioFile.processingFormat.sampleRate == 22_050)
precondition(audioFile.processingFormat.channelCount == 1)
let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: AVAudioFrameCount(audioFile.length))!
try audioFile.read(into: buffer)
let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
precondition(samples.contains { abs($0) > 0.01 }, "Soundtrack must contain audible signal")
precondition(samples.allSatisfy { abs($0) < 0.2 }, "Keep soundtrack quiet and unclipped")
precondition(abs(samples.first!) < 0.001 && abs(samples.last!) < 0.001, "Loop seam must be quiet")
print("PASS: generated WAV decodes to eight seconds of quiet, unclipped mono audio")
