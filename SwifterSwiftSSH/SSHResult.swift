//
//  SSHResult.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 18/12/2021.
//

import Foundation

public struct SSHExecResult {
    let stdout: String;
    let stderr: String;
    let exitCode: Int32;
    let exitSignal: String?;
}
