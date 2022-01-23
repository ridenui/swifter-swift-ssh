//
//  HostKey.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 17/01/2022.
//

import Foundation

public struct SSHHostKeyt {
    public let hostname: String;
    public let comment: String;
    
    public let keyType: String;
    
    public let flags: Int32;
    
    public let publicKey: [UInt8];
    public let privateKey: [UInt8];
}
