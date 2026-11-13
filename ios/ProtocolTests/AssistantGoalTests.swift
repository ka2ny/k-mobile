import Testing
@testable import KMobileProtocol

struct AssistantGoalTests {
    @Test func requiresServerGoalIdentity() {
        #expect(AssistantGoal(.object(["id": .string("made-up")])) == nil)
        #expect(AssistantGoal(.object(["id": .string("g0123456789")]))?.state == "paused")
    }
    @Test func preservesWaitingAndBudgetState() {
        let value = AssistantGoal(.object(["id": .string("g0123456789"), "state": .string("paused"),
            "why": .string("budget"), "needs": .number(2), "progress": .string("Draft ready")]))
        #expect(value?.needs == 2)
        #expect(value?.status == "Paused — monthly budget reached")
        #expect(value?.progress == "Draft ready")
    }
    @Test func unknownStateDoesNotImplyActiveWork() {
        let value = AssistantGoal(.object(["id": .string("g0123456789"), "state": .string("unknown"),
            "needs": .number(-3), "next_due": .number(-1)]))
        #expect(value?.state == "paused")
        #expect(value?.needs == 0)
        #expect(value?.nextDue == 0)
    }
}
