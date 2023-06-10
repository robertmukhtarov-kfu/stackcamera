//
//  Extensions.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 07.11.2022
//

import AVFoundation
import UIKit

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}

// https://stackoverflow.com/a/71126836
extension CaseIterable where Self: Equatable {
    func previous() -> Self {
        let all = Self.allCases
        var idx = all.firstIndex(of: self)!
        if idx == all.startIndex {
            let lastIndex = all.index(all.endIndex, offsetBy: -1)
            return all[lastIndex]
        } else {
            all.formIndex(&idx, offsetBy: -1)
            return all[idx]
        }
    }
    
    func next() -> Self {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        let next = all.index(after: idx)
        return all[next == all.endIndex ? all.startIndex : next]
    }
    
    func advanced(by n: Int) -> Self {
        let all = Array(Self.allCases)
        let idx = (all.firstIndex(of: self)! + n) % all.count
        if idx >= 0 {
            return all[idx]
        } else {
            return all[all.count + idx]
        }
    }
}
