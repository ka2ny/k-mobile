import Foundation

enum RuntimePolicy {
    static func canControl(online: Bool, kind: ConnectionProfile.Kind?, device: GatewayModels.Device?, hub: GatewayModels.Hub?) -> Bool {
        guard online, device?.control == "full" else { return false }
        switch kind {
        case .computer: return device?.kind == "phone" && hub?.paired == true && hub?.control == "full" && hub?.stopped == false
        case .companion: return device?.kind == "companion"
        case nil: return false
        }
    }
    static func pollDelay(failures: Int, interactive: Bool) -> Double {
        if failures > 0 { return min(30, 5 * pow(2, Double(min(failures - 1, 3)))) }
        return interactive ? 5 : 15
    }
}
