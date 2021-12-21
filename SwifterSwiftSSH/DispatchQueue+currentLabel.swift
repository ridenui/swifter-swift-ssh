//
//  DispatchQueue+currentLabel.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 21/12/2021.
//

import Foundation

extension DispatchQueue {
    class var currentLabel: String? {
        return String(validatingUTF8: __dispatch_queue_get_label(nil))
    }
}
