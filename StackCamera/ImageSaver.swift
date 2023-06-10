//
//  ImageSaver.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 13.11.2022.
//


import UIKit
import SwiftUI
import Photos

class ImageSaver: NSObject {
    @AppStorage("compressedImageFormat")
    private var compressedImageFormat = CompressedImageFormat.heif.rawValue
    
    static let albumName = "Stack Camera"
    static let shared = ImageSaver()
    
    var assetCollection: PHAssetCollection!
    
    override init() {
        super.init()
        
        if let assetCollection = fetchAssetCollectionForAlbum() {
            self.assetCollection = assetCollection
            return
        }
    }
    
    func requestAuthorizationHandler(status: PHAuthorizationStatus) {
        if PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized {
            self.createAlbum()
        } else {
            print("Album creation failed")
        }
    }
    
    func createAlbum() {
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: ImageSaver.albumName)
        }) { success, error in
            if success {
                self.assetCollection = self.fetchAssetCollectionForAlbum()
            } else {
                print("error \(String(describing: error))")
            }
        }
    }
    
    func fetchAssetCollectionForAlbum() -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", ImageSaver.albumName)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        if let _: AnyObject = collection.firstObject {
            return collection.firstObject
        }
        return nil
    }
    
    func saveCompressedImage(imageURL dngURL: URL) {
        let ciFilter = CIRAWFilter(imageURL: dngURL)!
        ciFilter.colorNoiseReductionAmount = 0.0
        ciFilter.luminanceNoiseReductionAmount = 0.0
        ciFilter.sharpnessAmount = 0.0
        ciFilter.detailAmount = 0.0
        let imageData: Data
        switch CompressedImageFormat(rawValue: compressedImageFormat) {
        case .jpeg:
            imageData = CIContext().jpegRepresentation(of: ciFilter.outputImage!, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        case .heif:
            imageData = CIContext().heifRepresentation(of: ciFilter.outputImage!, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        case .none:
            fatalError("Compressed image format is invalid")
        }
        ImageSaver.shared.save(imageData: imageData)
    }
    
    func saveDNG(imageURL: URL) {
        // Not using addResource(with:fileURL:options:) in order to save image with the default IMG_ prefix
        ImageSaver.shared.save(imageData: try! Data(contentsOf: imageURL))
    }
    
    func save(imageData: Data? = nil, completion: (() -> ())? = nil) {
        if assetCollection == nil {
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            let assetChangeRequest = PHAssetCreationRequest.forAsset()
            let creationOptions = PHAssetResourceCreationOptions()
            creationOptions.shouldMoveFile = true
            if let imageData {
                assetChangeRequest.addResource(with: .photo, data: imageData, options: creationOptions)
            } else {
                fatalError("No image data.")
            }
            let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
            let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection)
            let enumeration: NSArray = [assetPlaceHolder!]
            
            if self.assetCollection.estimatedAssetCount == 0 {
                albumChangeRequest!.addAssets(enumeration)
            }
            else {
                albumChangeRequest!.insertAssets(enumeration, at: [0])
            }
            
        }, completionHandler: { status, error in
            completion?()
        })
    }
}
