//
//  ImageSaver.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 13.11.2022.
//


import UIKit
import SwiftUI
import Photos

final class ImageSaver: NSObject {
    var isAuthorized: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }
    
    @AppStorage("compressedImageFormat")
    private var compressedImageFormat = CompressedImageFormat.heif.rawValue
    
    private static let albumName = "Stack Camera"
    static let shared = ImageSaver()
    
    private var assetCollection: PHAssetCollection!
    
    private override init() {
        super.init()
        
        if let assetCollection = fetchAssetCollectionForAlbum() {
            self.assetCollection = assetCollection
            return
        }
    }
    
    func requestAuthorizationIfNeeded(completion: @escaping (_ success: Bool) -> Void) {
        // Not possible to create a custom folder with .addOnly access
        // https://stackoverflow.com/questions/69062763/camera-app-create-new-album-with-phphotolibrary-with-addonly-phaccesslevel
        
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                self.requestAuthorizationIfNeeded(completion: completion)
            }
        case .authorized:
            self.createAlbumIfNeeded { success in
                completion(success)
            }
        default:
            completion(false)
        }
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
        save(imageData: imageData)
    }
    
    func saveDNG(imageURL: URL) {
        // Not using addResource(with:fileURL:options:) in order to save image with the default IMG_ prefix
        save(imageData: try! Data(contentsOf: imageURL))
    }
    
    private func save(imageData: Data? = nil, completion: (() -> ())? = nil) {
        createAlbumIfNeeded()
        guard let assetCollection else { return }
        PHPhotoLibrary.shared().performChanges {
            let assetChangeRequest = PHAssetCreationRequest.forAsset()
            let creationOptions = PHAssetResourceCreationOptions()
            creationOptions.shouldMoveFile = true
            if let imageData {
                assetChangeRequest.addResource(with: .photo, data: imageData, options: creationOptions)
            } else {
                fatalError("No image data.")
            }
            let assetPlaceHolder = assetChangeRequest.placeholderForCreatedAsset
            let albumChangeRequest = PHAssetCollectionChangeRequest(for: assetCollection)
            let enumeration: NSArray = [assetPlaceHolder!]
            
            if assetCollection.estimatedAssetCount == 0 {
                albumChangeRequest!.addAssets(enumeration)
            } else {
                albumChangeRequest!.insertAssets(enumeration, at: [0])
            }
        } completionHandler: { status, error in
            if let error { print ("Error: \(error.localizedDescription)")}
            completion?()
        }
    }
    
    private func createAlbumIfNeeded(completion: ((_ success: Bool) -> Void)? = nil) {
        if let assetCollection = fetchAssetCollectionForAlbum() {
            // Album already exists
            self.assetCollection = assetCollection
            completion?(true)
        } else {
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: ImageSaver.albumName)
            }) { success, error in
                if success {
                    self.assetCollection = self.fetchAssetCollectionForAlbum()
                    completion?(true)
                } else {
                    // Unable to create album
                    completion?(false)
                }
            }
        }
    }
    
    private func fetchAssetCollectionForAlbum() -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", ImageSaver.albumName)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        if let _: AnyObject = collection.firstObject {
            return collection.firstObject
        }
        return nil
    }
}
