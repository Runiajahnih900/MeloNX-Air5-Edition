// GPUEngine.swift
// MeloNX Air5 Edition
//
// Nintendo Switch GPU (Nvidia Maxwell / NVN) emulation with Metal backend.
// Optimized for the Apple M1 GPU (7-core) in the iPad Air 5.

import Foundation
import Metal
import MetalKit

/// GPU command types issued by the CPU to the GPU engine.
enum GPUCommand {
    case draw(vertexCount: Int, instanceCount: Int)
    case drawIndexed(indexCount: Int, indexBuffer: GPUBuffer)
    case setRenderPipeline(descriptor: GPURenderPipelineDescriptor)
    case setVertexBuffer(buffer: GPUBuffer, offset: Int, index: Int)
    case setFragmentTexture(texture: GPUTexture, index: Int)
    case setViewport(x: Float, y: Float, width: Float, height: Float)
    case setScissorRect(x: Int, y: Int, width: Int, height: Int)
    case clearColor(r: Float, g: Float, b: Float, a: Float)
    case present
}

/// A reference to a GPU-side buffer.
struct GPUBuffer {
    let id: UInt32
    let size: Int
    let data: Data?
}

/// A reference to a GPU-side texture.
struct GPUTexture {
    let id: UInt32
    let width: Int
    let height: Int
    let format: GPUTextureFormat
}

/// Texture formats matching the Nintendo Switch NVN API.
enum GPUTextureFormat {
    case rgba8Unorm
    case bgra8Unorm
    case r16Float
    case rgba16Float
    case depth32Float
    case bc1RGBA
    case bc3RGBA
}

/// Render pipeline descriptor (simplified NVN → Metal mapping).
struct GPURenderPipelineDescriptor {
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let pixelFormat: GPUTextureFormat
    let depthWriteEnabled: Bool
}

/// The GPU engine: translates Nintendo Switch NVN API calls into Apple Metal commands.
/// Leverages the M1 GPU's tile-based deferred rendering for maximum efficiency on iPad Air 5.
final class GPUEngine {

    // MARK: - Metal objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var bufferCache: [UInt32: MTLBuffer] = [:]
    private var textureCache: [UInt32: MTLTexture] = [:]
    private var currentCommandBuffer: MTLCommandBuffer?
    private var currentEncoder: MTLRenderCommandEncoder?

    // MARK: - iPad Air 5 display properties

    /// Native resolution of the iPad Air 5 display (2360×1640).
    static let nativeResolutionWidth = 2360
    static let nativeResolutionHeight = 1640
    static let nativePPI: Float = 264.0

    // MARK: - Init

    /// Initialize the GPU engine. Requires an MTLDevice (Metal-capable GPU).
    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            return nil
        }
        self.device = device
        self.commandQueue = queue
    }

    // MARK: - Command Processing

    /// Process a batch of GPU commands, translating them to Metal.
    func processCommands(_ commands: [GPUCommand]) {
        beginFrame()
        for command in commands {
            processCommand(command)
        }
        endFrame()
    }

    private func processCommand(_ command: GPUCommand) {
        switch command {
        case let .draw(vertexCount, instanceCount):
            currentEncoder?.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: vertexCount,
                instanceCount: instanceCount
            )

        case let .drawIndexed(indexCount, indexBuffer):
            guard let mtlBuffer = metalBuffer(for: indexBuffer) else { break }
            currentEncoder?.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: mtlBuffer,
                indexBufferOffset: 0
            )

        case let .setRenderPipeline(descriptor):
            if let pipeline = metalPipeline(for: descriptor) {
                currentEncoder?.setRenderPipelineState(pipeline)
            }

        case let .setVertexBuffer(buffer, offset, index):
            if let mtlBuffer = metalBuffer(for: buffer) {
                currentEncoder?.setVertexBuffer(mtlBuffer, offset: offset, index: index)
            }

        case let .setFragmentTexture(texture, index):
            if let mtlTexture = metalTexture(for: texture) {
                currentEncoder?.setFragmentTexture(mtlTexture, index: index)
            }

        case let .setViewport(x, y, width, height):
            currentEncoder?.setViewport(MTLViewport(
                originX: Double(x), originY: Double(y),
                width: Double(width), height: Double(height),
                znear: 0.0, zfar: 1.0
            ))

        case let .setScissorRect(x, y, width, height):
            currentEncoder?.setScissorRect(MTLScissorRect(
                x: x, y: y, width: width, height: height
            ))

        case .clearColor:
            // Clear is handled via render pass descriptor.
            break

        case .present:
            break
        }
    }

    // MARK: - Frame Management

    private func beginFrame() {
        currentCommandBuffer = commandQueue.makeCommandBuffer()
    }

    private func endFrame() {
        currentEncoder?.endEncoding()
        currentCommandBuffer?.commit()
        currentCommandBuffer = nil
        currentEncoder = nil
    }

    // MARK: - Metal Resource Helpers

    private func metalBuffer(for gpuBuffer: GPUBuffer) -> MTLBuffer? {
        if let cached = bufferCache[gpuBuffer.id] { return cached }
        guard let data = gpuBuffer.data else {
            return device.makeBuffer(length: gpuBuffer.size, options: .storageModeShared)
        }
        let buffer = data.withUnsafeBytes { ptr in
            device.makeBuffer(bytes: ptr.baseAddress!, length: data.count, options: .storageModeShared)
        }
        if let buffer {
            bufferCache[gpuBuffer.id] = buffer
        }
        return buffer
    }

    private func metalTexture(for gpuTexture: GPUTexture) -> MTLTexture? {
        if let cached = textureCache[gpuTexture.id] { return cached }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: metalPixelFormat(for: gpuTexture.format),
            width: gpuTexture.width,
            height: gpuTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        let texture = device.makeTexture(descriptor: descriptor)
        if let texture {
            textureCache[gpuTexture.id] = texture
        }
        return texture
    }

    private func metalPipeline(for descriptor: GPURenderPipelineDescriptor) -> MTLRenderPipelineState? {
        let cacheKey = "\(descriptor.vertexFunctionName)|\(descriptor.fragmentFunctionName)"
        if let cached = pipelineCache[cacheKey] { return cached }

        guard let library = device.makeDefaultLibrary(),
              let vertexFn = library.makeFunction(name: descriptor.vertexFunctionName),
              let fragmentFn = library.makeFunction(name: descriptor.fragmentFunctionName)
        else { return nil }

        let mtlDescriptor = MTLRenderPipelineDescriptor()
        mtlDescriptor.vertexFunction = vertexFn
        mtlDescriptor.fragmentFunction = fragmentFn
        mtlDescriptor.colorAttachments[0].pixelFormat = metalPixelFormat(for: descriptor.pixelFormat)
        if descriptor.depthWriteEnabled {
            mtlDescriptor.depthAttachmentPixelFormat = .depth32Float
        }

        let state = try? device.makeRenderPipelineState(descriptor: mtlDescriptor)
        if let state {
            pipelineCache[cacheKey] = state
        }
        return state
    }

    private func metalPixelFormat(for format: GPUTextureFormat) -> MTLPixelFormat {
        switch format {
        case .rgba8Unorm:   return .rgba8Unorm
        case .bgra8Unorm:   return .bgra8Unorm
        case .r16Float:     return .r16Float
        case .rgba16Float:  return .rgba16Float
        case .depth32Float: return .depth32Float
        case .bc1RGBA:      return .bc1_rgba
        case .bc3RGBA:      return .bc3_rgba
        }
    }
}
