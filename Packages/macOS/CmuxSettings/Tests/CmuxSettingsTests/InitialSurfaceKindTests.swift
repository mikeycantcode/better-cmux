import Testing
@testable import CmuxSettings

@Suite struct InitialSurfaceKindTests {
    @Test func freshAndEnabledIsWelcome() {
        #expect(InitialSurfaceKind.resolve(isFreshLaunch: true, hasInitialInput: false, welcomeEnabled: true) == .welcome)
    }
    @Test func freshButDisabledIsTerminal() {
        #expect(InitialSurfaceKind.resolve(isFreshLaunch: true, hasInitialInput: false, welcomeEnabled: false) == .terminal)
    }
    @Test func initialInputForcesTerminal() {
        #expect(InitialSurfaceKind.resolve(isFreshLaunch: true, hasInitialInput: true, welcomeEnabled: true) == .terminal)
    }
    @Test func notFreshIsTerminal() {
        #expect(InitialSurfaceKind.resolve(isFreshLaunch: false, hasInitialInput: false, welcomeEnabled: true) == .terminal)
    }
}
