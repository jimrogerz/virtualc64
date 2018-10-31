//
//  Shaders.swift
//  VirtualC64
//
//  Created by Dirk Hoffmann on 12.01.18.
//

import Foundation

//
// Base class for all compute kernels
// 

struct C64_TEXTURE {
    static let width = 512
    static let height = 512
    static let cutout_x = 428
    static let cutout_y = 284
}

struct UPSCALED_TEXTURE {
    static let factor_x = 4
    static let factor_y = 4
    static let width = C64_TEXTURE.width * UPSCALED_TEXTURE.factor_x
    static let height = C64_TEXTURE.height * UPSCALED_TEXTURE.factor_y
    static let cutout_x = C64_TEXTURE.cutout_x * UPSCALED_TEXTURE.factor_x
    static let cutout_y = C64_TEXTURE.cutout_y * UPSCALED_TEXTURE.factor_y
}

struct FILTERED_TEXTURE {
    static let factor_x = 4
    static let factor_y = 8
    static let width = C64_TEXTURE.width * FILTERED_TEXTURE.factor_x
    static let height = C64_TEXTURE.height * FILTERED_TEXTURE.factor_y
    static let cutout_x = C64_TEXTURE.cutout_x * FILTERED_TEXTURE.factor_x
    static let cutout_y = C64_TEXTURE.cutout_y * FILTERED_TEXTURE.factor_y
}

class ComputeKernel : NSObject {
    
    var kernel : MTLComputePipelineState!
    var sampler : MTLSamplerState!
    
    var threadgroupSize : MTLSize
    var threadgroupCount : MTLSize

    var samplerLinear : MTLSamplerState!
    var samplerNearest : MTLSamplerState!
    var preBlurTexture: MTLTexture!
    var blurWeightTexture: MTLTexture!

    func isPreBlurRequired() -> Bool {
        return false;
    }
    
    func setPreBlurTexture(texture: MTLTexture) {
        self.preBlurTexture = texture;
    }

    override init()
    {
        // Set thread group size of 16x16
        // TODO: Which thread group size suits best for out purpose?
        let groupSizeX = 16
        let groupSizeY = 16
        threadgroupSize = MTLSizeMake(groupSizeX, groupSizeY, 1 /* depth */)
        
        // Calculate the compute kernel's width and height
        let threadCountX = (FILTERED_TEXTURE.width + groupSizeX -  1) / groupSizeX
        let threadCountY = (FILTERED_TEXTURE.height + groupSizeY - 1) / groupSizeY
        threadgroupCount = MTLSizeMake(threadCountX, threadCountY, 1)
        
        super.init()
    }

    convenience init?(name: String, device: MTLDevice, library: MTLLibrary)
    {
        self.init()
        
        // Lookup kernel function in library
        guard let function = library.makeFunction(name: name) else {
            track("ERROR: Cannot find kernel function '\(name)' in library.")
            return nil
        }
        
        // Create kernel
        do {
            try kernel = device.makeComputePipelineState(function: function)
        } catch {
            track("ERROR: Cannot create compute kernel '\(name)'.")
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.icon = NSImage.init(named: NSImage.Name(rawValue: "metal"))
            alert.messageText = "Failed to create compute kernel."
            alert.informativeText = "Kernel '\(name)' will be ignored when selected."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return nil
        }
        
        // Build texture samplers
        let samplerDescriptor1 = MTLSamplerDescriptor()
        samplerDescriptor1.minFilter = MTLSamplerMinMagFilter.linear
        samplerDescriptor1.magFilter = MTLSamplerMinMagFilter.linear
        samplerDescriptor1.sAddressMode = MTLSamplerAddressMode.clampToEdge
        samplerDescriptor1.tAddressMode = MTLSamplerAddressMode.clampToEdge
        samplerDescriptor1.mipFilter = MTLSamplerMipFilter.notMipmapped
        samplerLinear = device.makeSamplerState(descriptor: samplerDescriptor1)
        
        let samplerDescriptor2 = MTLSamplerDescriptor()
        samplerDescriptor2.minFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor2.magFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor2.sAddressMode = MTLSamplerAddressMode.clampToEdge
        samplerDescriptor2.tAddressMode = MTLSamplerAddressMode.clampToEdge
        samplerDescriptor2.mipFilter = MTLSamplerMipFilter.notMipmapped
        samplerNearest = device.makeSamplerState(descriptor: samplerDescriptor2)
        
        // Set default sampler
        sampler = samplerLinear
    }
    
    func getsampler() -> MTLSamplerState
    {
        return sampler
    }
    
    func configureComputeCommandEncoder(encoder : MTLComputeCommandEncoder)
    {
        // Each specific compute kernel puts its initialization code here
    }
    
    func apply(commandBuffer: MTLCommandBuffer, source: MTLTexture, target: MTLTexture)
    {
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(kernel)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(target, index: 1)
            if (blurWeightTexture != nil) {
                encoder.setTexture(blurWeightTexture, index: 2)
            }
            if (preBlurTexture != nil) {
                encoder.setTexture(preBlurTexture, index: 3);
            }
            configureComputeCommandEncoder(encoder: encoder)

            encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
    }
    
    func getBlurWeights(device: MTLDevice, radius: Float) {
        // Build blur weight texture
        let sigma: Float = radius / 2.0
        let size:  Int   = Int(round(radius) * 2 + 1)
        
        var delta: Float = 0.0;
        var expScale: Float = 0.0
        
        if (radius > 0.0) {
            delta = (radius * 2) / Float(size - 1)
            expScale = -1.0 / (2 * sigma * sigma)
        }
        
        let weights = UnsafeMutablePointer<Float>.allocate(capacity: size)
        
        var weightSum: Float = 0.0;
        
        var x = -radius
        for i in 0 ..< size {
            let weight = expf((x * x) * expScale)
            weights[i] = weight
            weightSum += weight
            x += delta
        }
        
        let weightScale: Float = 1.0 / weightSum
        for j in 0 ..< size {
            weights[j] *= weightScale;
        }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.r32Float, width: size, height: 1, mipmapped: false)
        
        blurWeightTexture = device.makeTexture(descriptor: textureDescriptor)!
        
        let region = MTLRegionMake2D(0, 0, size, 1)
        blurWeightTexture.replace(region: region, mipmapLevel: 0, withBytes: weights, bytesPerRow: size * 4 /* size of float */)
        
        weights.deallocate()
    }
}

//
// Upscalers
//

class BypassUpscaler : ComputeKernel {
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {
        
        self.init(name: "bypassupscaler", device: device, library: library)
        
        // Replace default texture sampler
        sampler = samplerNearest
    }
}

class EPXUpscaler : ComputeKernel {
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {
        
        self.init(name: "epxupscaler", device: device, library: library)
        
        // Replace default texture sampler
        sampler = samplerNearest
    }
}

class XBRUpscaler : ComputeKernel {
    
    convenience init?(device: MTLDevice, library: MTLLibrary)
    {
        self.init(name: "xbrupscaler", device: device, library: library)
        
        // Replace default texture sampler
        sampler = samplerNearest
    }
}


//
// Filters
//

class BypassFilter : ComputeKernel {
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {
        
        self.init(name: "bypass", device: device, library: library)
        sampler = samplerNearest
    }
}

class SmoothFilter : ComputeKernel {
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {
        
        self.init(name: "bypass", device: device, library: library)
        sampler = samplerLinear
    }
}

class BlurFilter : ComputeKernel {
    
    convenience init?(name: String, device: MTLDevice, library: MTLLibrary, radius: Float) {
        self.init(name: name, device: device, library: library)
        getBlurWeights(device: device, radius: radius)
    }
    
    override func isPreBlurRequired() -> Bool {
        return true;
    }
}

class CrtFilter : ComputeKernel {
    
    private var crtParameters: CrtParameters!
    
    struct CrtParameters {
        var bloomingFactor: Float
    }
    
    func setBloomingFactor(_ value : Float) {
        crtParameters.bloomingFactor = value
    }
    
    func bloomingFactor() -> Float {
        return crtParameters.bloomingFactor
    }
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {

        self.init(name: "crt", device: device, library: library)
        self.crtParameters = CrtParameters(bloomingFactor: 1.0);
    }
    
    override func configureComputeCommandEncoder(encoder: MTLComputeCommandEncoder) {
        encoder.setBytes(&crtParameters, length: MemoryLayout<CrtParameters>.stride, index: 0);
    }
    
}

class ScanlineFilter : ComputeKernel {
    
    private var crtParameters: CrtParameters!
    
    struct CrtParameters {
        var bloomingFactor: Float
    }
    
    func setBloomingFactor(_ value : Float) {
        crtParameters.bloomingFactor = value
    }
    
    override func isPreBlurRequired() -> Bool {
        return true;
    }
    
    convenience init?(device: MTLDevice, library: MTLLibrary) {
        self.init(name: "scanline", device: device, library: library)
        self.crtParameters = CrtParameters(bloomingFactor: 1.0);
        sampler = samplerLinear
        getBlurWeights(device: device, radius: 4.0)
    }
    
    override func configureComputeCommandEncoder(encoder: MTLComputeCommandEncoder) {
        encoder.setBytes(&crtParameters, length: MemoryLayout<CrtParameters>.stride, index: 0);
    }
}
