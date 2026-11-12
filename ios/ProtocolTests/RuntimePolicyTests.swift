import Testing
@testable import KMobileProtocol

struct RuntimePolicyTests {
    let phone = GatewayModels.Device(id: "test", name: "Phone", control: "full", kind: "phone", fp: nil)
    @Test func unavailableDesktopStatusNeverGrantsControl() {
        #expect(!RuntimePolicy.canControl(online: true, kind: .computer, device: phone, hub: nil))
        let stopped = GatewayModels.Hub(paired: true, stopped: true, remote: true, beam: true, agents: true, control: "full")
        #expect(!RuntimePolicy.canControl(online: true, kind: .computer, device: phone, hub: stopped))
    }
    @Test func controlRequiresBothIdentityAndGatewayConsent() {
        let hub = GatewayModels.Hub(paired: true, stopped: false, remote: true, beam: true, agents: true, control: "full")
        #expect(RuntimePolicy.canControl(online: true, kind: .computer, device: phone, hub: hub))
        #expect(!RuntimePolicy.canControl(online: false, kind: .computer, device: phone, hub: hub))
        #expect(!RuntimePolicy.canControl(online: true, kind: .companion, device: phone, hub: nil))
    }
    @Test func companionIdentityHasItsOwnPermissionContract() {
        let board = GatewayModels.Device(id: "test", name: "Companion", control: "full", kind: "companion", fp: nil)
        #expect(RuntimePolicy.canControl(online: true, kind: .companion, device: board, hub: nil))
    }
    @Test func pollingBackoffIsBoundedAndIdleTabsAreCheaper() {
        #expect(RuntimePolicy.pollDelay(failures: 0, interactive: true) == 5)
        #expect(RuntimePolicy.pollDelay(failures: 0, interactive: false) == 15)
        #expect([1, 2, 3, 4, 100].map { RuntimePolicy.pollDelay(failures: $0, interactive: true) } == [5, 10, 20, 30, 30])
    }
}
