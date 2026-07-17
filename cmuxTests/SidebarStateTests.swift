import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

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
