//
//  RAWCaptureDelegate.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 20.09.2022
//

import UIKit
import AVFoundation
import Photos

class RAWCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    enum RawCaptureError: Error {
        case noFileDataRepresentation
    }
    
    private var rawData: Data!
    
    var didFinish: ((Result<Data, Error>) -> Void)?
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        print("Captured RAW Image")
        if let error {
            print("Error capturing photo: \(error)")
            didFinish?(.failure(error))
            return
        }
        
        // Access the file data representation of this photo.
        guard let photoData = photo.fileDataRepresentation() else {
            print("No photo data to write.")
            didFinish?(.failure(RawCaptureError.noFileDataRepresentation))
            return
        }
        
        rawData = photoData
    }
    
    private func makeUniqueDNGFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = ProcessInfo.processInfo.globallyUniqueString
        return tempDir.appendingPathComponent(fileName).appendingPathExtension("dng")
    }
    
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            print("Error capturing photo: \(error)")
            didFinish?(.failure(error))
            return
        }
    
        didFinish?(.success(rawData))
    }
}
