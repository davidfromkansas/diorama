import AppKit
import SceneKit

/// A clipped title texture. SceneKit animates UVs; no text drawing occurs per frame.
final class OfficeScrollingTitle {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>(); cache.countLimit = 128; cache.totalCostLimit = 16 * 1024 * 1024; return cache
    }()
    let node = SCNNode()
    private(set) var running = false
    private(set) var overflow: CGFloat = 0
    private var textureWidth: CGFloat = 456
    private var property: SCNMaterialProperty?
    private var title = ""

    func setTitle(_ text: String) {
        guard title != text else { return }
        title = text
        setRunning(false)
        let font = NSFont.systemFont(ofSize: 29, weight: .semibold)
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 4
        textureWidth = max(456, width)
        overflow = max(0, textureWidth - 456)
        // Bound the texture allocation even for unusually long imported titles.
        let scale = min(1, 8192 / textureWidth)
        let image: NSImage
        if let cached = Self.images.object(forKey: text as NSString) { image = cached }
        else {
            image = NSImage(size: NSSize(width: textureWidth * scale, height: 43 * scale))
            image.lockFocus()
            let drawingTransform = NSAffineTransform(); drawingTransform.scale(by: scale); drawingTransform.concat()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = overflow > 0 ? .left : .center
            paragraph.lineBreakMode = .byClipping
            (text as NSString).draw(in: NSRect(x: 0, y: 0, width: textureWidth, height: 43), withAttributes: [
                .font: font, .foregroundColor: NSColor.darkGray, .paragraphStyle: paragraph
            ])
            image.unlockFocus()
            Self.images.setObject(image, forKey: text as NSString, cost: Int(image.size.width * image.size.height * 16))
        }

        let material = WorkspaceAvatarFactory.material(.white, constant: true)
        material.diffuse.contents = image
        material.diffuse.wrapS = .clamp
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        property = material.diffuse
        material.diffuse.contentsTransform = transform(at: 0)
        let plane = SCNPlane(width: 1.65 * 456 / 480, height: 0.385 * 43 / 112)
        plane.materials = [material]
        node.geometry = plane
        node.position = SCNVector3(0, 0.385 * (78.5 - 56) / 112, 0.002)
    }

    private func transform(at offset: CGFloat) -> SCNMatrix4 {
        var matrix = SCNMatrix4MakeScale(456 / textureWidth, 1, 1)
        matrix.m41 = offset / textureWidth
        return matrix
    }

    func setRunning(_ enabled: Bool) {
        let desired = enabled && overflow > 0
        guard desired != running else { return }
        running = desired
        property?.removeAnimation(forKey: "titleScroll")
        guard desired else { return }
        let travel = Double(overflow / 30)
        let duration = travel + 4
        let animation = CAKeyframeAnimation(keyPath: "contentsTransform")
        animation.values = [0, 0, overflow, overflow].map { NSValue(scnMatrix4: transform(at: $0)) }
        animation.keyTimes = [0, NSNumber(value: 2 / duration), NSNumber(value: (2 + travel) / duration), 1]
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.calculationMode = .linear
        property?.addAnimation(animation, forKey: "titleScroll")
    }
}
