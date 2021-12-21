//
//  SSHLog.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 21/12/2021.
//

import Foundation

func LogSSH(_ msg: String, function: String = #function, file: String = #file, line: Int = #line) {
    if let label = DispatchQueue.currentLabel {
        print("[LIBSSH Q-\(label)]\(makeTag(function: function, file: file, line: line)) : \(msg)")
    } else {
        print("[LIBSSH]\(makeTag(function: function, file: file, line: line)) : \(msg)")
    }
}

private func makeTag(function: String, file: String, line: Int) -> String{
    let url = NSURL(fileURLWithPath: file)
    let className = url.lastPathComponent ?? file
    return "\(className) \(function)[\(line)]"
}
