import Testing
@testable import cmux_DEV

@MainActor
struct SidebarStateTests {
    @Test func hideAndShowAreIdempotent() {
        let state = SidebarState()
        state.isVisible = true
        state.hide()
        #expect(state.isVisible == false)
        state.hide()
        #expect(state.isVisible == false)
        state.show()
        #expect(state.isVisible == true)
        state.show()
        #expect(state.isVisible == true)
    }
}
