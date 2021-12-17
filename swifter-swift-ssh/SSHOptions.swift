//
//  SSHOptions.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//

import Foundation

public struct SSHOption {
    let host: String;
    var port: Int = 22;
    var username: String;
    var password: String?;
}
