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
    ///   - knownHostFile: The known host file location. Please see `knownHostFile`
    public init(host: String, port: Int = 22, username: String, password: String? = nil, knownHostFile: String? = nil, idRsaLocation: String? = nil) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.knownHostFile = knownHostFile
        self.idRsaLocation = idRsaLocation
    }
    
    /// Hostname or ip address
    public let host: String;
    /// Port. The default is 22
    public var port: Int = 22;
    /// Username
    public var username: String;
    /// Password
    public var password: String?;
    /// The location of the known host file.
    /// - Warning: You need to change this path on iOS
    public var knownHostFile: String?;
    public var idRsaLocation: String?;
}
