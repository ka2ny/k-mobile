import SwiftUI

/// The k-chain as it looks on the desk: the graphite body with the face the board would show for this moment.
struct KChainDeviceView: View {
    enum Face: String {
        case pair = "KChainFacePair"
        case idle = "KChainFaceIdle"
        case thinking = "KChainFaceThinking"
        case ready = "KChainFaceReady"
        case problem = "KChainFaceProblem"
        case wifi = "KChainFaceWiFi"
        case asking = "KChainFaceAsking"

        var words: String {
            switch self {
            case .pair: "Not paired yet"
            case .idle: "Paired, resting"
            case .thinking: "Connecting"
            case .ready: "Connected"
            case .problem: "Needs attention"
            case .wifi: "Choosing a Wi-Fi network"
            case .asking: "Waiting for the board's code"
            }
        }
    }

    let face: Face
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Geometry of the body picture (280 × 325 pt, screen hole 200 × 245 at 40, 40).
    private static let size = CGSize(width: 280, height: 325)
    private static let screen = CGRect(x: 40, y: 40, width: 200, height: 245)
    private static let radius: CGFloat = 23.3

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Self.size.width, proxy.size.height / Self.size.height)
            ZStack(alignment: .topLeading) {
                Image(face.rawValue)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.screen.width * scale, height: Self.screen.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: Self.radius * scale, style: .continuous))
                    .offset(x: Self.screen.minX * scale, y: Self.screen.minY * scale)
                    .id(face)
                    .transition(.opacity)
                Image("KChainBody")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Self.size.width * scale, height: Self.size.height * scale)
            }
            .frame(width: Self.size.width * scale, height: Self.size.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: face)
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("k-chain")
        .accessibilityValue(face.words)
    }
}

extension AccessoryModel {
    /// The face the board picture shows for the connection's state. Read only from observed state.
    var face: KChainDeviceView.Face {
        if error != nil { return .problem }
        if joinedAddress != nil { return .ready }
        if mode == .setup && ready {
            if !setupAuthenticated { return .asking }
            return working ? .thinking : .wifi
        }
        if working { return .thinking }
        if mode == .relay && ready { return .ready }
        if status.hasPrefix("Connecting") || status.hasPrefix("Waiting") || status.hasPrefix("Bluetooth connected")
            || status.hasPrefix("Board disconnected. Reconnecting") || status.hasPrefix("Bluetooth is restarting")
        {
            return .thinking
        }
        return savedRelay ? .idle : .pair
    }
}
