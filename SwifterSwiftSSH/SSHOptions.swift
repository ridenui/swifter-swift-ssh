//
//  SSHOptions.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//

import Foundation

/// SSH options required for `SSH`
public struct SSHOption {
    /// Initialize SSHOptions
    /// - Parameters:
    ///   - host: Hostname or ip address
    ///   - port: Port. The default is 22
    ///   - username: Username
    ///   - password: Password
    public init(host: String, port: Int = 22, username: String, password: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
    
    /// Hostname or ip address
    public let host: String;
    /// Port. The default is 22
    public var port: Int = 22;
    /// Username
    public var username: String;
    /// Password
    public var password: String?;
}
