import SceneKit
import Metal

/// A bounded, occasional single-sample offscreen diagnostic of the same scene.
/// SceneKit deferred shadows reject externally multisampled pass textures.
/// This lower-cost probe excludes MSAA and must not drive onscreen quality. SCNView does not expose
/// its command buffer, so frame-callback duration must not be labelled GPU time.
/// This probe owns its Metal command buffer and reads actual GPU start/end timestamps.
final class SceneGPUProbe {
    private var pending = false
    func sample(scene: SCNScene, camera: SCNNode, size: CGSize, samples: Int,
                completion: @escaping @MainActor (Double?) -> Void) {
        guard !pending, let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return }
        pending = true
        let job = Job(scene: scene, camera: camera, device: device, queue: queue,
                      width: max(1,Int(size.width)), height: max(1,Int(size.height)), samples: samples)
        Task { [weak self] in
            let duration = await Task.detached(priority: .utility) { job.run() }.value
            self?.pending = false
            completion(duration)
        }
    }
    /// SceneKit permits sharing a scene across renderers; only this worker owns its
    /// renderer and Metal resources. The app continues to mutate nodes on the main actor.
    private nonisolated final class Job: @unchecked Sendable {
        let scene: SCNScene, camera: SCNNode
        let device: any MTLDevice, queue: any MTLCommandQueue
        let width: Int, height: Int, samples: Int
        init(scene: SCNScene, camera: SCNNode, device: any MTLDevice, queue: any MTLCommandQueue, width: Int, height: Int, samples: Int) {
            self.scene=scene; self.camera=camera; self.device=device; self.queue=queue
            self.width=width; self.height=height; self.samples=samples
        }
        func run() -> Double? {
            let renderer = SCNRenderer(device:device,options:nil)
            renderer.scene=scene; renderer.pointOfView=camera
            func texture(_ format: MTLPixelFormat, samples: Int) -> (any MTLTexture)? {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:format,width:width,height:height,mipmapped:false)
                descriptor.storageMode = .private; descriptor.usage = [.renderTarget]
                descriptor.sampleCount = samples
                if samples > 1 { descriptor.textureType = .type2DMultisample }
                return device.makeTexture(descriptor:descriptor)
            }
            guard let color=texture(.bgra8Unorm,samples:1), let depth=texture(.depth32Float,samples:1), let command=queue.makeCommandBuffer() else { return nil }
            let pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=color; pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .dontCare
            pass.depthAttachment.texture=depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
            renderer.render(atTime:CACurrentMediaTime(),viewport:CGRect(x:0,y:0,width:width,height:height),commandBuffer:command,passDescriptor:pass)
            command.commit(); command.waitUntilCompleted()
            guard command.status == .completed, command.gpuEndTime > command.gpuStartTime else { return nil }
            return command.gpuEndTime-command.gpuStartTime
        }
    }
}
