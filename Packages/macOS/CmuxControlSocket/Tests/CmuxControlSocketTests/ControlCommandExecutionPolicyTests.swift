import Testing
@testable import CmuxControlSocket

@Suite("ControlCommandExecutionPolicy")
struct ControlCommandExecutionPolicyTests {
    @Test func fixedWorkerSetRunsOnTheSocketWorker() {
        for method in [
            "system.ping", "system.capabilities",
            "feed.push", "browser.download.wait", "system.top", "system.memory",
            "workspace.env", "sidebar.custom.reload",
            "sidebar.custom.open",
            "debug.sidebar.simulate_drag",
            // JavaScript-evaluating browser methods block on page JS and must
            // not hold the main actor (see socketWorkerMethods rationale).
            "browser.eval", "browser.wait", "browser.snapshot", "browser.click",
            "browser.fill", "browser.navigate", "browser.get.text",
            "browser.find.text", "browser.highlight",
        ] {
            #expect(ControlCommandExecutionPolicy(forMethod: method).runsOnSocketWorker, "\(method)")
        }
    }

    @Test func workspaceSnapshotRunsOnTheSocketWorker() {
        // `workspace.snapshot`'s only handler lives in the socket-worker
        // switch (TerminalController.processCommand). If the policy routes it
        // to the main actor the dispatcher never reaches that handler and
        // answers method_not_found, which breaks `cmux open`'s smart
        // placement — see the missing-entry regression this test pins.
        #expect(ControlCommandExecutionPolicy(forMethod: "workspace.snapshot").runsOnSocketWorker)
    }

    @Test func everythingElseRunsOnTheMainActor() {
        for method in [
            "surface.list", "workspace.create", "window.list", "browser.url.get",
            "browser.open_split", "browser.screenshot", "browser.cookies.get",
            "mobile.terminal.create", "feed.jump", "vmx.create", "vm.create",
            "remotes.list", "auth.status", "workspace.remote.pty_bridge",
            "mobile.attach_ticket.create", "",
        ] {
            let policy = ControlCommandExecutionPolicy(forMethod: method)
            #expect(policy == .mainActor, "\(method)")
            #expect(!policy.runsOnSocketWorker, "\(method)")
        }
    }

    @Test func onlyPureProbesAreMainThreadCallable() {
        #expect(ControlCommandExecutionPolicy(forMethod: "system.ping") == .socketWorker(mainThreadCallable: true))
        #expect(ControlCommandExecutionPolicy(forMethod: "system.capabilities") == .socketWorker(mainThreadCallable: true))
        #expect(ControlCommandExecutionPolicy(forMethod: "system.top") == .socketWorker(mainThreadCallable: false))
    }
}
