import Foundation

enum CompanionCommand: String, CaseIterable, Identifiable {
    case previous = "media.previous"
    case playPause = "media.toggle"
    case next = "media.next"
    case quieter = "volume.down"
    case mute = "volume.mute"
    case louder = "volume.up"
    case focusOn = "dnd.on"
    case focusOff = "dnd.off"
    case lock = "lock"
    var id: Self { self }
    var title: String {
        switch self {
        case .previous: "Previous track"
        case .playPause: "Play or pause"
        case .next: "Next track"
        case .quieter: "Volume down"
        case .mute: "Toggle mute"
        case .louder: "Volume up"
        case .focusOn: "Focus on"
        case .focusOff: "Focus off"
        case .lock: "Lock computer"
        }
    }
    var symbol: String {
        switch self {
        case .previous: "backward.end"
        case .playPause: "playpause"
        case .next: "forward.end"
        case .quieter: "speaker.wave.1"
        case .mute: "speaker.slash"
        case .louder: "speaker.wave.3"
        case .focusOn: "moon"
        case .focusOff: "sun.max"
        case .lock: "lock"
        }
    }
}
