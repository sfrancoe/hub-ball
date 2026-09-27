import AVFoundation
import Observation
import OSLog

/// A quiet, locally synthesized eight-second pad. No files, downloads, or services.
@MainActor @Observable
final class StoryAudioController {
    private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var loopData: Data?

    @discardableResult
    func start() -> Bool {
        if isPlaying { return true }
        do {
            let session = AVAudioSession.sharedInstance()
            // Ambient already mixes with other audio and respects the silent switch.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let data = loopData ?? StoryAudioLoop.makeData()
            loopData = data
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.prepareToPlay()
            guard player.play() else { stop(); return false }
            self.player = player
            isPlaying = true
            return true
        } catch {
            Logger(subsystem: "com.sfrancoe.HubBall", category: "StoryAudio").error("Unable to start local story sound: \(error.localizedDescription, privacy: .public)")
            stop()
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
