//
//  SSHLog.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 21/12/2021.
//

import Foundation

var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return formatter
}()

func LogSSH(_ msg: String, function: String = #function, file: String = #file, line: Int = #line) {
    if let label = DispatchQueue.currentLabel {
        print("[LIBSSH \(dateFormatter.string(from: Date())) T\(String(withInt: Thread.current.value(forKeyPath: "private.seqNum")! as! Int, leadingZeros: 5)) Q-\(label)]\(makeTag(function: function, file: file, line: line)) : \(msg)")
    } else {
        print("[LIBSSH \(dateFormatter.string(from: Date())) T\(String(withInt: Thread.current.value(forKeyPath: "private.seqNum")! as! Int, leadingZeros: 5)) ]\(makeTag(function: function, file: file, line: line)) : \(msg)")
    }
}

private func makeTag(function: String, file: String, line: Int) -> String{
    let url = NSURL(fileURLWithPath: file)
    let className = url.lastPathComponent ?? file
    return "\(className) \(function)[\(line)]"
}

extension String {

    init(withInt int: Int, leadingZeros: Int = 2) {
        self.init(format: "%0\(leadingZeros)d", int)
    }

    func leadingZeros(_ zeros: Int) -> String {
        if let int = Int(self) {
            return String(withInt: int, leadingZeros: zeros)
        }
        print("Warning: \(self) is not an Int")
        return ""
    }
    
}
