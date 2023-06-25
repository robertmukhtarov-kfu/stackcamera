//
//  FormatButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 10.11.2022
//

import UIKit
import SwiftUI

final class FormatButton: UIButton {
    
    @AppStorage("compressedImageFormat")
    private static var compressedImageFormat = CompressedImageFormat.heif.rawValue
    
    private(set) var formatButtonState: State = .dng {
        didSet {
            configuration?.subtitle = formatButtonState.title
        }
    }
    
    enum State: CaseIterable {
        case compressed
        case dng
        case burst // Burst of DNG files
        
        var title: String {
            switch self {
            case .compressed:
                return compressedImageFormat.uppercased()
            case .dng:
                return "DNG"
            case .burst:
                return "Burst"
            }
        }
    }
        
    func changeToNextState() {
        formatButtonState = formatButtonState.next()
    }
}
