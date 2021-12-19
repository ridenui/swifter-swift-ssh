//
//  SSHOptions.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//

import Foundation

public struct SSHOption {
    public init(host: String, port: Int = 22, username: String, password: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
    
    public let host: String;
    public var port: Int = 22;
    public var username: String;
    public var password: String?;
}
