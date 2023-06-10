//
//  SettingButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 10.11.2022
//

import UIKit

class SettingButton: UIButton {
    
    enum State {
        case auto
        case autoHighlighted
        case manual
        case manualHighlighted
    }
        
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        
    }
}
