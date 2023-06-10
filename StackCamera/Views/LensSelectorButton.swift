//
//  LensSelectorButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 10.11.2022
//

import UIKit

enum LensType: String {
    case ultrawide = "ULTRA WIDE"
    case wide = "WIDE"
    case telephoto = "TELE"
}

protocol LensSelectorButtonDelegate: AnyObject {
    func didSelectLens(_ type: LensType)
}

final class LensSelectorButton: UIButton {
    private var availableLenses: [LensType] = []
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        titleLabel?.textAlignment = .center
    }
    
    func setLens(_ type: LensType) {
        setTitle(type.rawValue, for: .normal)
    }
}
