import Foundation

extension Bundle {
    /// SwiftPM's generated `Bundle.module` searches the .app root and then the build
    /// checkout, and traps when neither exists. A packaged app stores the resource bundle
    /// under Contents/Resources, so look there first and never trap in a packaged app.
    static let dioramaResources: Bundle? = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Diorama_DioramaApp.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        if Bundle.main.bundleURL.pathExtension == "app" { return nil }
        return Bundle.module
    }()
}
