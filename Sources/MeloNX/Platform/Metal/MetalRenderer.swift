// MetalRenderer.swift
// MeloNX Air5 Edition
//
// Metal-based renderer for the emulated Nintendo Switch display output.
// Renders the emulator framebuffer to a CAMetalLayer / MTKView.

import Foundation
import Metal
import MetalKit
import simd

/// Vertex used for the full-screen blit quad.
struct BlitVertex {
    var position: SIMD4<Float>
    var texCoord: SIMD2<Float>
}

/// Handles presenting emulator output to the screen using Metal.
final class MetalRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal Objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var blitPipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?

    /// Texture containing the latest emulator framebuffer (1280×720 Nintendo Switch output).
    private var framebufferTexture: MTLTexture?

    /// The full-screen quad vertex buffer.
    private var quadVertexBuffer: MTLBuffer?

    // MARK: - Display Properties

    let targetWidth: Int
    let targetHeight: Int

    // MARK: - Init

    init?(targetWidth: Int = iPadAir5Device.displayWidth,
          targetHeight: Int = iPadAir5Device.displayHeight) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
        super.init()
        buildBlitPipeline()
        buildSamplerState()
        buildQuadBuffer()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize if needed.
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        if let pipeline = blitPipelineState,
           let sampler = samplerState,
           let quad = quadVertexBuffer,
           let texture = framebufferTexture {
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(quad, offset: 0, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Framebuffer Update

    /// Update the displayed framebuffer with new pixel data from the emulator.
    /// - Parameters:
    ///   - pixels: RGBA8Unorm pixel data, width × height × 4 bytes.
    ///   - width: Framebuffer width (typically 1280 for Nintendo Switch docked).
    ///   - height: Framebuffer height (typically 720 for Nintendo Switch docked).
    func updateFramebuffer(pixels: Data, width: Int, height: Int) {
        if framebufferTexture == nil || framebufferTexture!.width != width || framebufferTexture!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            framebufferTexture = device.makeTexture(descriptor: descriptor)
        }

        pixels.withUnsafeBytes { ptr in
            framebufferTexture?.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: width * 4
            )
        }
    }

    // MARK: - Private Setup

    private func buildBlitPipeline() {
        guard let library = device.makeDefaultLibrary() else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction   = library.makeFunction(name: "blitVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "blitFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        blitPipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func buildSamplerState() {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter    = .linear
        descriptor.magFilter    = .linear
        descriptor.mipFilter    = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: descriptor)
    }

    private func buildQuadBuffer() {
        // Full-screen quad as a triangle strip.
        let vertices: [BlitVertex] = [
            BlitVertex(position: SIMD4(-1,  1, 0, 1), texCoord: SIMD2(0, 0)),
            BlitVertex(position: SIMD4(-1, -1, 0, 1), texCoord: SIMD2(0, 1)),
            BlitVertex(position: SIMD4( 1,  1, 0, 1), texCoord: SIMD2(1, 0)),
            BlitVertex(position: SIMD4( 1, -1, 0, 1), texCoord: SIMD2(1, 1)),
        ]
        quadVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<BlitVertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }
}
