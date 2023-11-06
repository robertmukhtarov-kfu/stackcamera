//
//  ImageProcessor.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 08.12.2022.
//

import MetalKit
import MetalPerformanceShaders

enum AlignmentError: Error {
    case lessThanTwoImagesProvided
}

enum ImageIOError: Error {
    case loadError
}

struct TileInfo {
    var tileSize: Int
    var searchDist: Int
    var nTilesX: Int
    var nTilesY: Int
    var nPos1D: Int
    var nPos2D: Int
}

enum UpscaleMode {
    case bilinear
    case nearest
}

let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let mtlLibrary = device.makeDefaultLibrary()!


let fillWithZerosState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "fillWithZeros")!)
let textureUInt16ToFloatState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "textureUInt16ToFloat")!)
let sumTexturesState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "sumTextures")!)
let sumTexturesWeightedState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "sumTexturesWeighted")!)
let upsampleTextureNearestState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "upsampleTextureNearest")!)
let upsampleTextureBilinearState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "upsampleTextureBilinear")!)
let averagePoolState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "averagePool")!)
let calculateMergedAverageState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "calculateMergedAverage")!)
let calculateTileDifferencesState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "calculateTileDifferences")!)
let calculateTileAlignmentsState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "calculateTileAlignments")!)
let shiftTilesState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "shiftTiles")!)
let blurOverXState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "blurOverX")!)
let blurOverYState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "blurOverY")!)
let colorDifferenceState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "colorDifference")!)
let averageOverYState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "averageOverY")!)
let averageOverXState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "averageOverX")!)
let calculateMergeWeightsState = try! device.makeComputePipelineState(function: mtlLibrary.makeFunction(name: "calculateMergeWeights")!)

func loadImages(imageBuffer: [Data]) throws -> ([MTLTexture], Int) {
    var texturesDict: [Int: MTLTexture] = [:]
    let computeGroup = DispatchGroup()
    let computeQueue = DispatchQueue.global()
    let accessQueue = DispatchQueue(label: "AccessQueue")
    var mosaicPatternSize: Int?

    for i in 0..<imageBuffer.count {
        computeQueue.async(group: computeGroup) {
            if let texture = imageDataToBayerMTLTexture(imageData: imageBuffer[i], device: device) {
                print("Loaded image texture")
                accessQueue.sync {
                    texturesDict[i] = texture
                    mosaicPatternSize = 2
                }
            }
        }
    }
    computeGroup.wait()
    
    var textures: [MTLTexture] = []
    for i in 0..<imageBuffer.count {
        try accessQueue.sync {
            if let texture = texturesDict[i] {
                textures.append(texture)
            } else {
                throw ImageIOError.loadError
            }
        }
    }
    
    return (textures, mosaicPatternSize!)
}

func calculateThreadsPerThreadGroup(state: MTLComputePipelineState, threadsPerGrid: MTLSize) -> MTLSize {
    var availableThreads = state.maxTotalThreadsPerThreadgroup
    if threadsPerGrid.depth > availableThreads {
        return MTLSize(width: 1, height: 1, depth: availableThreads)
    } else {
        availableThreads /= threadsPerGrid.depth
        if threadsPerGrid.height > availableThreads {
            return MTLSize(width: 1, height: availableThreads, depth: threadsPerGrid.depth)
        } else {
            availableThreads /= threadsPerGrid.height
            return MTLSize(width: availableThreads, height: threadsPerGrid.height, depth: threadsPerGrid.depth)
        }
    }
}

func fillWithZeros(texture: MTLTexture) {
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = fillWithZerosState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: texture.width, height: texture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(texture, index: 0)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
}

func textureUInt16ToFloat(inTexture: MTLTexture) -> MTLTexture {
    let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: inTexture.width, height: inTexture.height, mipmapped: false)
    outTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outTexture = device.makeTexture(descriptor: outTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = textureUInt16ToFloatState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: inTexture.width, height: inTexture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(inTexture, index: 0)
    commandEncoder.setTexture(outTexture, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return outTexture
}

func upsample(inputTexture: MTLTexture, width: Int, height: Int, mode: UpscaleMode) -> MTLTexture {
    let scaleX = Double(width) / Double(inputTexture.width)
    let scaleY = Double(height) / Double(inputTexture.height)
    
    let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: inputTexture.pixelFormat, width: width, height: height, mipmapped: false)
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = mode == .bilinear ? upsampleTextureBilinearState : upsampleTextureNearestState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(inputTexture, index: 0)
    commandEncoder.setTexture(outputTexture, index: 1)
    commandEncoder.setBytes([Float32(scaleX)], length: MemoryLayout<Float32>.stride, index: 0)
    commandEncoder.setBytes([Float32(scaleY)], length: MemoryLayout<Float32>.stride, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return outputTexture
}

func averagePool(inputTexture: MTLTexture, scale: Int) -> MTLTexture {
    let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: inputTexture.pixelFormat, width: inputTexture.width / scale, height: inputTexture.height / scale, mipmapped: false)
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = averagePoolState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(inputTexture, index: 0)
    commandEncoder.setTexture(outputTexture, index: 1)
    commandEncoder.setBytes([Int32(scale)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()

    return outputTexture
}

func calculateMergedAverageState(inputTexture: MTLTexture, n: Int) -> MTLTexture {
    let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Uint, width: inputTexture.width, height: inputTexture.height, mipmapped: false)
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)!

    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = calculateMergedAverageState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(inputTexture, index: 0)
    commandEncoder.setTexture(outputTexture, index: 1)
    commandEncoder.setBytes([Int32(n)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()

    return outputTexture
}

func buildPyramid(inputTexture: MTLTexture, downscaleFactorList: Array<Int>) -> Array<MTLTexture> {
    var pyramid: Array<MTLTexture> = []
    for (i, downscaleFactor) in downscaleFactorList.enumerated() {
        if i == 0 {
            pyramid.append(averagePool(inputTexture: inputTexture, scale: downscaleFactor))
        } else {
            pyramid.append(averagePool(inputTexture: pyramid.last!, scale: downscaleFactor))
        }
    }
    return pyramid
}

func makeSimilarTexture(inputTexture: MTLTexture) -> MTLTexture {
    let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: inputTexture.pixelFormat, width: inputTexture.width, height: inputTexture.height, mipmapped: false)
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)!
    return outputTexture
}

func calculateTileDifferences(referenceTexture: MTLTexture, alternateTexture: MTLTexture, previousAlignment: MTLTexture, downscaleFactor: Int, tileInfo: TileInfo) -> MTLTexture {
    
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.textureType = .type3D
    textureDescriptor.pixelFormat = .r32Float
    textureDescriptor.width = tileInfo.nTilesX
    textureDescriptor.height = tileInfo.nTilesY
    textureDescriptor.depth = tileInfo.nPos2D
    textureDescriptor.usage = [.shaderRead, .shaderWrite]
    let tileDifferences = device.makeTexture(descriptor: textureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = calculateTileDifferencesState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: tileInfo.nTilesX, height: tileInfo.nTilesY, depth: tileInfo.nPos2D)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(referenceTexture, index: 0)
    commandEncoder.setTexture(alternateTexture, index: 1)
    commandEncoder.setTexture(previousAlignment, index: 2)
    commandEncoder.setTexture(tileDifferences, index: 3)
    commandEncoder.setBytes([Int32(downscaleFactor)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.setBytes([Int32(tileInfo.tileSize)], length: MemoryLayout<Int32>.stride, index: 1)
    commandEncoder.setBytes([Int32(tileInfo.searchDist)], length: MemoryLayout<Int32>.stride, index: 2)
    commandEncoder.setBytes([Int32(tileInfo.nTilesX)], length: MemoryLayout<Int32>.stride, index: 3)
    commandEncoder.setBytes([Int32(tileInfo.nTilesY)], length: MemoryLayout<Int32>.stride, index: 4)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return tileDifferences
}

func calculateTileAlignments(tileDifferences: MTLTexture, previousAlignment: MTLTexture, currentAlignment: MTLTexture, downscaleFactor: Int, tileInfo: TileInfo) {
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = calculateTileAlignmentsState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: tileInfo.nTilesX, height: tileInfo.nTilesY, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(tileDifferences, index: 0)
    commandEncoder.setTexture(previousAlignment, index: 1)
    commandEncoder.setTexture(currentAlignment, index: 2)
    commandEncoder.setBytes([Int32(downscaleFactor)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.setBytes([Int32(tileInfo.searchDist)], length: MemoryLayout<Int32>.stride, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
}

func shiftTiles(textureToWarp: MTLTexture, alignment: MTLTexture, tileInfo: TileInfo, downscaleFactor: Int) -> MTLTexture {
    let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: textureToWarp.pixelFormat, width: textureToWarp.width, height: textureToWarp.height, mipmapped: false)
    outTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let warpedTexture = device.makeTexture(descriptor: outTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = shiftTilesState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: textureToWarp.width, height: textureToWarp.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(textureToWarp, index: 0)
    commandEncoder.setTexture(warpedTexture, index: 1)
    commandEncoder.setTexture(alignment, index: 2)
    commandEncoder.setBytes([Int32(downscaleFactor)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.setBytes([Int32(tileInfo.tileSize)], length: MemoryLayout<Int32>.stride, index: 1)
    commandEncoder.setBytes([Int32(tileInfo.nTilesX)], length: MemoryLayout<Int32>.stride, index: 2)
    commandEncoder.setBytes([Int32(tileInfo.nTilesY)], length: MemoryLayout<Int32>.stride, index: 3)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return warpedTexture
}

func sumTextures(texture1: MTLTexture, texture2: MTLTexture) {
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = sumTexturesState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: texture1.width, height: texture1.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(texture1, index: 0)
    commandEncoder.setTexture(texture2, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
}

func sumTexturesWeighted(texture1: MTLTexture, texture2: MTLTexture, weightTexture: MTLTexture) -> MTLTexture {
    let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture1.pixelFormat, width: texture1.width, height: texture1.height, mipmapped: false)
    outTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outTexture = device.makeTexture(descriptor: outTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = sumTexturesWeightedState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: texture1.width, height: texture1.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(texture1, index: 0)
    commandEncoder.setTexture(texture2, index: 1)
    commandEncoder.setTexture(weightTexture, index: 2)
    commandEncoder.setTexture(outTexture, index: 3)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return outTexture
}

func blurTexture(inTexture: MTLTexture, kernelSize: Int, mosaicPatternSize: Int) -> MTLTexture {
    let blurX = makeSimilarTexture(inputTexture: inTexture)
    let blurXY = makeSimilarTexture(inputTexture: inTexture)
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = blurOverXState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: inTexture.width, height: inTexture.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(inTexture, index: 0)
    commandEncoder.setTexture(blurX, index: 1)
    commandEncoder.setBytes([Int32(kernelSize)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.setBytes([Int32(mosaicPatternSize)], length: MemoryLayout<Int32>.stride, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)

    let state2 = blurOverYState
    commandEncoder.setComputePipelineState(state2)
    commandEncoder.setTexture(blurX, index: 0)
    commandEncoder.setTexture(blurXY, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    
    commandEncoder.endEncoding()
    commandBuffer.commit()
    return blurXY
}

func colorDifference(texture1: MTLTexture, texture2: MTLTexture, mosaicPatternSize: Int) -> MTLTexture {
    let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture1.pixelFormat, width: texture1.width / mosaicPatternSize, height: texture1.height / mosaicPatternSize, mipmapped: false)
    outTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outTextureDescriptor)!

    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = colorDifferenceState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: texture1.width / 2, height: texture1.height / 2, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(texture1, index: 0)
    commandEncoder.setTexture(texture2, index: 1)
    commandEncoder.setTexture(outputTexture, index: 2)
    commandEncoder.setBytes([Int32(mosaicPatternSize)], length: MemoryLayout<Int32>.stride, index: 0)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return outputTexture
}

func textureMean(inTexture: MTLTexture) -> MTLBuffer {
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.textureType = .type1D
    textureDescriptor.pixelFormat = inTexture.pixelFormat
    textureDescriptor.width = inTexture.width
    textureDescriptor.usage = [.shaderRead, .shaderWrite]
    let avgY = device.makeTexture(descriptor: textureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = averageOverYState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: inTexture.width, height: 1, depth: 1)
    let maxThreadsPerThreadGroup = state.maxTotalThreadsPerThreadgroup
    let threadsPerThreadGroup = MTLSize(width: maxThreadsPerThreadGroup, height: 1, depth: 1)
    commandEncoder.setTexture(inTexture, index: 0)
    commandEncoder.setTexture(avgY, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    
    let state2 = averageOverXState
    commandEncoder.setComputePipelineState(state2)
    let avgBuffer = device.makeBuffer(length: MemoryLayout<Float32>.size, options: .storageModeShared)!
    commandEncoder.setTexture(avgY, index: 0)
    commandEncoder.setBuffer(avgBuffer, offset: 0, index: 0)
    commandEncoder.setBytes([Int32(inTexture.width)], length: MemoryLayout<Int32>.stride, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    return avgBuffer
}

func estimateColorNoise(texture: MTLTexture, textureBlurred: MTLTexture, mosaicPatternSize: Int) -> MTLBuffer {
    let textureDiff = colorDifference(texture1: texture, texture2: textureBlurred, mosaicPatternSize: mosaicPatternSize)
    let meanDiff = textureMean(inTexture: textureDiff)
    return meanDiff
}

func robustMerge(referenceTexture: MTLTexture, referenceTextureBlurred: MTLTexture, alternateTexture: MTLTexture, kernelSize: Int, robustness: Double, noiseSD: MTLBuffer, mosaicPatternSize: Int) -> MTLTexture {
    if robustness == 0 { return alternateTexture }
    
    let alternateTextureBlurred = blurTexture(inTexture: alternateTexture, kernelSize: kernelSize, mosaicPatternSize: mosaicPatternSize)
    let textureDiff = colorDifference(texture1: referenceTextureBlurred, texture2: alternateTextureBlurred, mosaicPatternSize: mosaicPatternSize)
    let weightTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: textureDiff.width, height: textureDiff.height, mipmapped: false)
    weightTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let weightTexture = device.makeTexture(descriptor: weightTextureDescriptor)!
    
    let commandBuffer = commandQueue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    let state = calculateMergeWeightsState
    commandEncoder.setComputePipelineState(state)
    let threadsPerGrid = MTLSize(width: textureDiff.width, height: textureDiff.height, depth: 1)
    let threadsPerThreadGroup = calculateThreadsPerThreadGroup(state: state, threadsPerGrid: threadsPerGrid)
    commandEncoder.setTexture(textureDiff, index: 0)
    commandEncoder.setTexture(weightTexture, index: 1)
    commandEncoder.setBuffer(noiseSD, offset: 0, index: 0)
    commandEncoder.setBytes([Float32(robustness)], length: MemoryLayout<Float32>.stride, index: 1)
    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadGroup)
    commandEncoder.endEncoding()
    commandBuffer.commit()
    
    let weightTextureUpsampled = upsample(inputTexture: weightTexture, width: referenceTexture.width, height: referenceTexture.height, mode: .bilinear)
    let outputTexture = sumTexturesWeighted(texture1: referenceTexture, texture2: alternateTexture, weightTexture: weightTextureUpsampled)
    
    return outputTexture
}

func alignAndMerge(images: [Data], tileSize: Int = 16, kernelSize: Int = 5, robustness: Double = 1.0) throws -> MTLTexture {
    let imageCount = images.count
    let refIndex: Int
    if imageCount < 2 {
        throw AlignmentError.lessThanTwoImagesProvided
    } else if imageCount <= 5 {
        refIndex = imageCount - 1
    } else {
        refIndex = 6
    }
    
    var (textures, mosaicPatternSize) = try loadImages(imageBuffer: images)
    textures = textures.map {
        textureUInt16ToFloat(inTexture: $0)
    }
    
    let referenceTexture = textures[refIndex]
    let searchDistance = 64
    let maxMinLayerResolution = searchDistance
    let minImageDimensions = min(referenceTexture.width, referenceTexture.height)
    var downscaleFactors = [mosaicPatternSize]
    var searchDistances = [2]
    var tileSizes = [tileSize]
    var resolution = minImageDimensions / downscaleFactors[0]
    while (resolution > maxMinLayerResolution) {
        downscaleFactors.append(2)
        searchDistances.append(2)
        tileSizes.append(max(tileSizes.last! / 2, 8))
        resolution /= 2
    }
    
    let referencePyramid = buildPyramid(inputTexture: referenceTexture, downscaleFactorList: downscaleFactors)
    let referenceTextureBlurred = blurTexture(inTexture: referenceTexture, kernelSize: kernelSize, mosaicPatternSize: mosaicPatternSize)
    let noiseSD = estimateColorNoise(texture: referenceTexture, textureBlurred: referenceTextureBlurred, mosaicPatternSize: mosaicPatternSize)
    
    let outputTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: referenceTexture.width, height: referenceTexture.height, mipmapped: false)
    outputTextureDescriptor.usage = [.shaderRead, .shaderWrite]
    let outputTexture = device.makeTexture(descriptor: outputTextureDescriptor)!
    fillWithZeros(texture: outputTexture)

    for alternateIndex in 0..<imageCount {
        if alternateIndex == refIndex {
            sumTextures(texture1: referenceTexture, texture2: outputTexture)
            continue
        }
        
        let alternatePyramid = buildPyramid(inputTexture: textures[alternateIndex], downscaleFactorList: downscaleFactors)

        let alignmentDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Sint, width: 1, height: 1, mipmapped: false)
        alignmentDescriptor.usage = [.shaderRead, .shaderWrite]
        var previousAlignment = device.makeTexture(descriptor: alignmentDescriptor)!
        var currentAlignment = device.makeTexture(descriptor: alignmentDescriptor)!
        var tileInfo = TileInfo(tileSize: 0, searchDist: 0, nTilesX: 0, nTilesY: 0, nPos1D: 0, nPos2D: 0)

        for i in (0 ... downscaleFactors.count-1).reversed() {
            let tileSize = tileSizes[i]
            let searchDistance = searchDistances[i]
            let referenceLayer = referencePyramid[i]
            let alternateLayer = alternatePyramid[i]
            
            let nTilesX = referenceLayer.width / (tileSize / 2) - 1
            let nTilesY = referenceLayer.height / (tileSize / 2) - 1
            let nPos1D = 2 * searchDistance + 1
            let nPos2D = nPos1D * nPos1D
            
            tileInfo = TileInfo(tileSize: tileSize, searchDist: searchDistance, nTilesX: nTilesX, nTilesY: nTilesY, nPos1D: nPos1D, nPos2D: nPos2D)
            
            var downscaleFactor: Int
            if (i < downscaleFactors.count - 1){
                downscaleFactor = downscaleFactors[i + 1]
            } else {
                downscaleFactor = 0
            }
            previousAlignment = upsample(inputTexture: currentAlignment, width: nTilesX, height: nTilesY, mode: .nearest)
            currentAlignment = makeSimilarTexture(inputTexture: previousAlignment)
            
            let tileDiff = calculateTileDifferences(referenceTexture: referenceLayer, alternateTexture: alternateLayer, previousAlignment: previousAlignment, downscaleFactor: downscaleFactor, tileInfo: tileInfo)
            calculateTileAlignments(tileDifferences: tileDiff, previousAlignment: previousAlignment, currentAlignment: currentAlignment, downscaleFactor: downscaleFactor, tileInfo: tileInfo)
        }
        
        tileInfo.tileSize *= downscaleFactors[0]
        let alignedTexture = shiftTiles(textureToWarp: textures[alternateIndex], alignment: currentAlignment, tileInfo: tileInfo, downscaleFactor: downscaleFactors[0])
        let mergedTexture = robustMerge(referenceTexture: referenceTexture, referenceTextureBlurred: referenceTextureBlurred, alternateTexture: alignedTexture, kernelSize: kernelSize, robustness: robustness, noiseSD: noiseSD, mosaicPatternSize: mosaicPatternSize)
        sumTextures(texture1: mergedTexture, texture2: outputTexture)
    }
    
    let outputTextureAveraged = calculateMergedAverageState(inputTexture: outputTexture, n: imageCount)
    return outputTextureAveraged
}
