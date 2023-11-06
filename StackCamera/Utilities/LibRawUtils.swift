//
//  LibRawUtils.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 30.11.2022
//

import Foundation
import MetalKit

func imageDataToBayerMTLTexture(imageData: Data, device: MTLDevice) -> MTLTexture? {
    let rawData = libraw_init(0)
    let image = imageData
    let imageURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try! image.write(to: imageURL, options: .atomic)
    
    var msg = libraw_open_file(rawData, imageURL.path)
    if (msg != LIBRAW_SUCCESS.rawValue) {
        libraw_close(rawData)
        return nil
    }
    msg = libraw_unpack(rawData)
    if (msg != LIBRAW_SUCCESS.rawValue) {
        libraw_close(rawData)
        return nil
    }

    guard let bayerMatrixBytes = rawData!.pointee.rawdata.raw_image else {
        libraw_close(rawData)
        return nil
    }
    
    let width = Int(libraw_get_raw_width(rawData))
    let height = Int(libraw_get_raw_height(rawData))
    let bytesPerPixel = 2
    let bytesPerRow = bytesPerPixel * width
    let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Uint, width: width, height: height, mipmapped: false)
    textureDescriptor.usage = [.shaderRead, .shaderWrite]
    guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
        libraw_close(rawData)
        return nil
    }
    let mtlRegion = MTLRegionMake2D(0, 0, width, height)
    texture.replace(region: mtlRegion, mipmapLevel: 0, withBytes: bayerMatrixBytes, bytesPerRow: bytesPerRow)
    
    libraw_close(rawData)
    return texture
}
