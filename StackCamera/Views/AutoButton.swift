//
//  AutoButton.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 10.11.2022
//

import UIKit

class AutoButton: UIButton {
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
