//
//  Shaders.swift
//  VirtualC64
//
//  Created by Dirk Hoffmann on 12.01.18.
//

import Foundation
import Metal
import MetalKit
import MetalPerformanceShaders

//
// Base class for all compute kernels
//

class ComputeKernel : NSObject {
    
    var kernel : MTLComputePipelineState!
    var sampler : MTLSamplerState!
    
    var threadgroupSize : MTLSize
    var threadgroupCount : MTLSize
    
    var samplerLinear : MTLSamplerState!
    var samplerNearest : MTLSamplerState!
    
    init(width: Int, height: Int)
    {
        // Set thread group size of 16x16
        // TODO: Which thread group size suits best for out purpose?
        let groupSizeX = 16
        let groupSizeY = 16
        threadgroupSize = MTLSizeMake(groupSizeX, groupSizeY, 1 /* depth */)
        
        // Calculate the compute kernel's width and height
        let threadCountX = (width + groupSizeX -  1) / groupSizeX
        let threadCountY = (height + groupSizeY - 1) / groupSizeY
        threadgroupCount = MTLSizeMake(threadCountX, threadCountY, 1)
        
        super.init()
    }
    
    convenience init?(name: String, width: Int, height: Int, device: MTLDevice, library: MTLLibrary)
    {
        self.init(width: width, height: height)
        
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
            configureComputeCommandEncoder(encoder: encoder)
            
            encoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            encoder.endEncoding()
        }
    }
}

//
// Upscalers
//

class ScanlineUpscaler : ComputeKernel {
    
    private var crtParameters: CrtParameters!
    
    struct CrtParameters {
        var scanlineWeight: Float
    }
    
    func setScanlineWeight(_ value : Float) {
        crtParameters.scanlineWeight = value
    }
    
    convenience init?(width: Int, height: Int, device: MTLDevice, library: MTLLibrary)
    {
        self.init(name: "scanline_upscaler", width: width, height: height, device: device, library: library)
        crtParameters = CrtParameters.init(scanlineWeight: 0.0)
        // Replace default texture sampler
        sampler = samplerNearest
    }
    
    override func configureComputeCommandEncoder(encoder: MTLComputeCommandEncoder) {
        encoder.setBytes(&crtParameters, length: MemoryLayout<CrtParameters>.stride, index: 0);
    }
}

//
// Filters
//

class GaussFilter : ComputeKernel {
    
    var device : MTLDevice!
    var sigma = Float(0.0)
    
    convenience init?(width:Int, height:Int, device: MTLDevice, library: MTLLibrary, sigma: Float) {
        
        self.init(name: "bypass", width:width, height:height, device: device, library: library)
        self.sigma = sigma
        self.device = device
    }
    
    override func apply(commandBuffer: MTLCommandBuffer, source: MTLTexture, target: MTLTexture) {
        
        if #available(OSX 10.13, *) {
            let gauss = MPSImageGaussianBlur(device: device, sigma: sigma)
            gauss.encode(commandBuffer: commandBuffer,
                         sourceTexture: source,
                         destinationTexture: target)
        } else {
            // Apply bypass on earlier versions
            super.apply(commandBuffer: commandBuffer, source: source, target: target)
        }
    }
}
