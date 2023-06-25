//
//  Extensions.swift
//  StackCamera
//
//  Created by Robert Mukhtarov on 07.11.2022
//

import Foundation

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
