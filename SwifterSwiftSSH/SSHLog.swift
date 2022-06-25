//
//  NewLogger.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 25/06/2022.
//

import Foundation

struct SSHLogger {
    // Current task id
    @TaskLocal static var taskId: Int = -1;
    
    private static var currentTaskId: Int = -1;
    
    private static var currentTaskIdLock = NSLock();
    
    private static var currentIntentLevelMap: [String: Int] = [:]
    
    static var logFile: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        let dateString = formatter.string(from: Date())
        let fileName = "\(dateString)-swifter-swift-ssh.log"
        return documentsDirectory.appendingPathComponent(fileName)
    }
    
    static let shared = SSHLogger()
    
    private enum LogType {
        case open
        case close
        case mid
    }
    
    // Singleton
    private init() { }
    
    func getTaskId() -> Int {
        return SSHLogger.taskId;
    }
    
    func openLog(_ type: String, attributes: [String: CustomStringConvertible] = [:], taskId: Int = SSHLogger.taskId, function: String = #function, file: String = #file, line: Int = #line) {
        SSHLogger.currentTaskIdLock.lock();
        defer {
            SSHLogger.currentTaskIdLock.unlock();
        }
        self.log(self.composeMessage(type: type, attributes: self.addToAttributes(attributes: attributes, function: function, file: file, line: line), taskId: taskId))
    }

    func closeLog(_ type: String, attributes: [String: CustomStringConvertible] = [:], taskId: Int = SSHLogger.taskId, function: String = #function, file: String = #file, line: Int = #line) {
        SSHLogger.currentTaskIdLock.lock();
        defer {
            SSHLogger.currentTaskIdLock.unlock();
        }
        self.log(self.composeMessage(logType: .close, type: type, attributes: self.addToAttributes(attributes: attributes, function: function, file: file, line: line), taskId: taskId))
    }
    
    func midLog(_ type: String, attributes: [String: CustomStringConvertible] = [:], taskId: Int = SSHLogger.taskId, function: String = #function, file: String = #file, line: Int = #line) {
        SSHLogger.currentTaskIdLock.lock();
        defer {
            SSHLogger.currentTaskIdLock.unlock();
        }
        self.log(self.composeMessage(logType: .mid, type: type, attributes: self.addToAttributes(attributes: attributes, function: function, file: file, line: line), taskId: taskId))
    }
    
    func startNewLoggingContext<R>(_ task: () async throws -> R) async rethrows -> R {
        SSHLogger.currentTaskIdLock.lock();
        SSHLogger.currentTaskId += 1;
        let newTaskId = SSHLogger.currentTaskId;
        SSHLogger.currentIntentLevelMap.updateValue(0, forKey: "\(newTaskId)")
        SSHLogger.currentTaskIdLock.unlock();
        
        return try await SSHLogger.$taskId.withValue(newTaskId, operation: {
            let result = try await task();
            SSHLogger.currentTaskIdLock.lock();
            SSHLogger.currentIntentLevelMap.removeValue(forKey: "\(newTaskId)")
            SSHLogger.currentTaskIdLock.unlock();
            return result;
        })
    }
    
    private func addToAttributes(attributes: [String: CustomStringConvertible], function: String, file: String, line: Int) -> [String: CustomStringConvertible] {
        var newAttributes = attributes
//        newAttributes["function"] = function
//        newAttributes["file"] = file
//        newAttributes["line"] = "\(line)"
        for key in newAttributes.keys {
            if let value = newAttributes[key] {
                newAttributes[key] = "\(value)".components(separatedBy: .newlines).joined(separator: "%%");
            }
        }
        return newAttributes
    }
    
    private func composeMessage(logType: LogType = .open, type: String, attributes: [String: CustomStringConvertible] = [:], taskId: Int = SSHLogger.taskId) -> String {
        var logMessage = self.intentPrefix(logType, taskId: taskId);
        switch (logType) {
        case .open:
            logMessage += ">>"
            break;
        case .close:
            logMessage += "<<"
            break;
        case .mid:
            logMessage += "||"
            break;
        }
        logMessage += type;
        logMessage += "(T-ID\(SSHLogger.taskId))"
        for key in attributes.keys {
            guard let value = attributes[key] else {
                continue;
            }
            logMessage += " \(key)=`\(value)`";
        }
        return logMessage;
    }
    
    private func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        print("\(timestamp): \(message)")
        self.writeToFile(message);
    }
    
    private func writeToFile(_ message: String) {
        guard let logFile = SSHLogger.logFile else {
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        guard let logData = (timestamp + ": " + message + "\n").data(using: String.Encoding.utf8) else { return }
        
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logData)
                fileHandle.closeFile()
            }
        } else {
            try? logData.write(to: logFile, options: .atomicWrite)
        }
    }
    
    private func intentPrefix(_ type: LogType = .open, taskId: Int = SSHLogger.taskId) -> String {
        let key = "\(taskId)";
        var intentLevel = SSHLogger.currentIntentLevelMap[key] ?? 0;
        if intentLevel < 0 {
            intentLevel = 0;
        }
        
        if type == .close {
            SSHLogger.currentIntentLevelMap.updateValue(intentLevel - 1, forKey: key)
        }
        
        intentLevel = SSHLogger.currentIntentLevelMap[key] ?? 0;
        if intentLevel < 0 {
            intentLevel = 0;
        }
        
        let prefix = String(repeating: " ", count: intentLevel * 4);
        
        if type == .open {
            SSHLogger.currentIntentLevelMap.updateValue(intentLevel + 1, forKey: key)
        }
        return prefix;
    }
}
