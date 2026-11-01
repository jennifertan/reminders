import AVFoundation
import UserNotifications

/// Alarm sounds bundled with the app. Each is a short WAV file in Ringlet/Sounds, made by
/// scripts/make-sounds.py. iOS plays up to 30 seconds of a notification sound.
enum ReminderSound: String, CaseIterable, Identifiable {
    case chime, bells, pulse, rise, marimba, silent

    var id: Self { self }

    var title: String {
        switch self {
        case .chime: "Glass Chime"
        case .bells: "Little Bells"
        case .pulse: "Steady Pulse"
        case .rise: "Gentle Rise"
        case .marimba: "Marimba"
        case .silent: "Silent"
        }
    }

    var fileName: String? { self == .silent ? nil : "\(rawValue).wav" }

    func notificationSound(critical: Bool, volume: Double) -> UNNotificationSound? {
        guard let fileName else { return nil }
        let name = UNNotificationSoundName(fileName)
        if critical && NotificationScheduler.hasCriticalAlertEntitlement {
            return .criticalSoundNamed(name, withAudioVolume: Float(volume))
        }
        return UNNotificationSound(named: name)
    }
}

/// Plays alarm sounds while Ringlet is open, even with the ring switch on silent.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    func play(_ sound: ReminderSound, repeating: Bool, volume: Double = 1) {
        stop()
        guard let fileName = sound.fileName,
              let url = Bundle.main.url(forResource: fileName, withExtension: nil)
        else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = repeating ? -1 : 0
        player?.volume = Float(volume)
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
