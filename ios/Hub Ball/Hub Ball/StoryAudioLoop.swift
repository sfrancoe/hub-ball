import Foundation

/// Dependency-free soundtrack synthesis shared with the decode validation.
enum StoryAudioLoop {
    /// In-memory PCM WAV lets AVAudioPlayer handle the current output route's format.
    static func makeData() -> Data {
        let sampleRate = 22_050
        let frames = sampleRate * 8
        let byteCount = frames * 2
        var data = Data()
        data.reserveCapacity(44 + byteCount)
        func append16(_ value: UInt16) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8(value >> 8))
        }
        func append32(_ value: Int) {
            append16(UInt16(value & 0xffff))
            append16(UInt16((value >> 16) & 0xffff))
        }
        data.append(contentsOf: "RIFF".utf8)
        append32(36 + byteCount)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append32(16)
        append16(1) // PCM
        append16(1) // Mono
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        data.append(contentsOf: "data".utf8)
        append32(byteCount)
        for frame in 0..<frames {
            let t = Double(frame) / Double(sampleRate)
            // Integral cycles and zero-ended envelope prevent clicks at the loop seam.
            let envelope = pow(sin(.pi * t / 8), 2)
            let chord = sin(2 * .pi * 130.75 * t) + 0.55 * sin(2 * .pi * 196 * t) + 0.3 * sin(2 * .pi * 261.5 * t)
            let sample = Int16(chord * envelope * 0.055 * Double(Int16.max))
            append16(UInt16(bitPattern: sample))
        }
        return data
    }
}
