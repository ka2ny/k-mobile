import Testing
@testable import KMobileProtocol

struct AccessoryPairingStateTests {
    @Test func selectionAndSubscriptionNeverClaimVerification() {
        var state = AccessoryPairingState()
        state.discover()
        state.selected(inSystemPicker: true)
        #expect(!state.verified)
        state.subscribed()
        state.connections(1)
        #expect(!state.verified)
        #expect(state.phase == .confirming)
    }

    @Test func pickerDismissalSurvivesTransportDiscovery() {
        var state = AccessoryPairingState()
        state.discover()
        state.selected(inSystemPicker: true)
        state.transportReset()
        state.connect()
        state.subscribed()
        #expect(state.pickerDismissed())
        #expect(!state.pickerDismissed())
        #expect(!state.verified)
    }

    @Test func protectedTrafficAndActiveRelayAreDistinct() {
        var state = AccessoryPairingState()
        state.subscribed()
        state.receivedProtectedOpen()
        #expect(state.verified)
        #expect(state.phase == .verified)
        state.connections(2)
        #expect(state.phase == .relaying)
        state.connections(0)
        #expect(state.phase == .verified)
        state.transportReset()
        #expect(!state.verified)
    }

    @Test func cancelledDiscoveryCannotPresentCompletion() {
        var state = AccessoryPairingState()
        state.discover()
        #expect(!state.pickerDismissed())
        #expect(state.phase == .idle)
        state.selected(inSystemPicker: true)
        state.cancel()
        #expect(!state.pickerDismissed())
        #expect(!state.verified)
    }
}
