//
//  SSHResult.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 18/12/2021.
//

import Foundation

public struct SSHExecResult {
    public let stdout: String;
    public let stderr: String;
    public let exitCode: Int32;
    public let exitSignal: String?;
}
