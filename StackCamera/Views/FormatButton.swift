//
//  FormatButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 10.11.2022
//

import UIKit
import SwiftUI

class FormatButton: UIButton {
    
    @AppStorage("compressedImageFormat")
    private var compressedImageFormat = CompressedImageFormat.heif.rawValue
    
    enum State: String, CaseIterable {
        case compressed = "JPEG"
        case dng = "DNG"
        case burst = "Burst" // Burst of DNG files
    }
        
    private(set) var formatButtonState: State = .dng

    func changeToNextState() {
        formatButtonState = formatButtonState.next()
        if formatButtonState == .compressed {
            configuration?.subtitle = compressedImageFormat.uppercased()
        } else {
            configuration?.subtitle = formatButtonState.rawValue
        }
    }
}
