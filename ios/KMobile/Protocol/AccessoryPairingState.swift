import Foundation

/// Evidence from the relay service, independent of presentation and localized status strings.
struct AccessoryPairingState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case idle, discovering, connecting, confirming, verified, relaying }
    private(set) var phase = Phase.idle
    private var waitingForPickerDismissal = false
    var verified: Bool { phase == .verified || phase == .relaying }
    var inProgress: Bool { phase == .discovering || phase == .connecting || phase == .confirming }

    mutating func discover() { phase = .discovering }
    mutating func connect() { phase = .connecting }
    /// AccessorySetupKit authorization is not proof of a Bluetooth bond.
    mutating func selected(inSystemPicker: Bool) {
        phase = .connecting
        waitingForPickerDismissal = inSystemPicker
    }
    /// Custom UI must wait until the system picker has left the screen.
    mutating func pickerDismissed() -> Bool {
        let present = waitingForPickerDismissal
        waitingForPickerDismissal = false
        if phase == .discovering { phase = .idle }
        return present
    }
    mutating func subscribed() { if !verified { phase = .confirming } }
    /// Current firmware sends a valid OPEN only after numeric comparison and bonding.
    mutating func receivedProtectedOpen() { if !verified { phase = .verified } }
    mutating func connections(_ count: Int) {
        guard verified else { return }
        phase = count > 0 ? .relaying : .verified
    }
    /// Transport can reset while the system picker is still dismissing.
    mutating func transportReset() { phase = .idle }
    mutating func cancel() { self = Self() }
}
