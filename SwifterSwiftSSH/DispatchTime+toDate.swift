//
//  DispatchTime+toDate.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 25/02/2022.
//

import Foundation

public extension DispatchTime {
    
    // https://stackoverflow.com/questions/31792306/in-swift-how-can-i-get-an-nsdate-from-a-dispatch-time-t
    func toDate() -> Date {
        let nanoSeconds = -Int64(bitPattern: self.rawValue)

        let wallTimeAsSeconds = Double(nanoSeconds) / Double(NSEC_PER_SEC)
        let date = Date(timeIntervalSince1970: wallTimeAsSeconds)
        return date
    }
    
}
