import Testing
@testable import DioramaApp

@MainActor struct OfficeScrollingTitleTests {
    @Test func shortTitlesStayStill() {
        let title = OfficeScrollingTitle()
        title.setTitle("Fix login")
        title.setRunning(true)
        #expect(title.overflow == 0)
        #expect(!title.running)
    }

    @Test func overflowUsesClippedTextureAndLifecycle() {
        let title = OfficeScrollingTitle()
        title.setTitle("Create a realistic 3D model of a Mediterranean office with furniture")
        #expect(title.overflow > 0)
        let geometry = title.node.geometry
        title.setRunning(true)
        #expect(title.running)
        #expect(title.node.geometry?.firstMaterial?.diffuse.animationKeys == ["titleScroll"])
        title.setRunning(false)
        #expect(!title.running)
        #expect(title.node.geometry?.firstMaterial?.diffuse.animationKeys.isEmpty == true)
        title.setRunning(true)
        #expect(title.node.geometry === geometry)
        title.setTitle("Done")
        #expect(!title.running)
        #expect(title.overflow == 0)
    }
}
