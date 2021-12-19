//
//  swifter_swift_ssh.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 17.12.21.
//
import Foundation

func LogSSH(_ msg: String, function: String = #function, file: String = #file, line: Int = #line){
    print("[LIBSSH]\(makeTag(function: function, file: file, line: line)) : \(msg)")
}

private func makeTag(function: String, file: String, line: Int) -> String{
    let url = NSURL(fileURLWithPath: file)
    let className = url.lastPathComponent ?? file
    return "\(className) \(function)[\(line)]"
}

public class SSH {

    private var session: ssh_session?;
    private let options: SSHOption;
    private var ssh_connected: Bool = false;
    private let dispatchQueue = DispatchQueue(label: "swifter-ssh")
    private let connectionLock = NSLock();
    private let sessionLock = NSLock();
    
    public init(options: SSHOption) {
        self.options = options;
        
        ssh_set_log_level(Int32(SSH_LOG_WARNING));
    }
    
    private func initSession() {
        self.sessionLock.lock();
        self.session = ssh_new();
        
        var port = options.port;
        
        if self.session != nil {
            ssh_options_set(self.session, SSH_OPTIONS_HOST, options.host);
            ssh_options_set(self.session, SSH_OPTIONS_PORT, &port);
        }
        self.sessionLock.unlock();
    }
    
    public func connect() async throws {
        self.connectionLock.lock();
        if self.session == nil {
            self.initSession();
            
            if self.session == nil {
                self.connectionLock.unlock();
                throw SSHError.CAN_NOT_OPEN_SESSION;
            }
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                let rc = ssh_connect(self.session);
                if rc != SSH_OK {
                    let errorString = String(cString: ssh_get_error(&self.session));
                    continuation.resume(throwing: SSHError.CONNECTION_ERROR(errorString));
                    self.connectionLock.unlock();
                } else {
                    self.ssh_connected = true;
                    continuation.resume();
                }
            }
        }
        
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                let ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
                if ra == SSH_AUTH_SUCCESS.rawValue {
                    continuation.resume();
                } else if ra == SSH_AUTH_DENIED.rawValue {
                    continuation.resume(throwing: SSHError.AUTH_DENIED);
                    self.connectionLock.unlock();
                } else if ra == SSH_AUTH_ERROR.rawValue {
                    continuation.resume(throwing: SSHError.AUTH_ERROR);
                    self.connectionLock.unlock();
                } else {
                    continuation.resume(throwing: SSHError.AUTH_ERROR_OTHER(ssh_auth_e(ra)));
                    self.connectionLock.unlock();
                }
            }
        })
        
        self.connectionLock.unlock();
    }
    
    public func isConnected() async -> Bool {
        self.connectionLock.lock();
        if self.session == nil {
            self.connectionLock.unlock();
            return false;
        }
        
        let result = await withCheckedContinuation({ (continuation: CheckedContinuation<Bool, Never>) in
            self.dispatchQueue.async {
                let rc = ssh_is_connected(self.session);
                if rc > 0 {
                    continuation.resume(returning: true);
                } else {
                    continuation.resume(returning: false);
                }
            }
        })
        self.connectionLock.unlock();
                                                       
        return result;
    }
    
    public func disconnect() async {
        self.connectionLock.lock();
        if self.session == nil {
            self.connectionLock.unlock();
            return;
        }
        
        await withCheckedContinuation({ (continuation: CheckedContinuation<Void, Never>) in
            self.dispatchQueue.async {
                ssh_disconnect(self.session);
                ssh_free(self.session);
                self.session = nil;
                continuation.resume();
            }
        })
        self.connectionLock.unlock();
                                                       
        return;
    }
    
    public func exec(command: String) async throws -> SSHExecResult {
        let commandUUID = UUID().uuidString;
        
        if !(await self.isConnected()) {
            try await self.connect();
        }
        
        LogSSH("exec: \(command)");
        
        actor ExitState {
            var exitStatus: Int?;
            var exitSignal: String?;
            
            let semaphore = DispatchSemaphore(value: 0);
            
            let command: String;
            let uuid: String;
            
            init(command: String, uuid: String) {
                self.command = command;
                self.uuid = uuid;
            }
            
            func setExitStatus(to: Int) -> Void {
                LogSSH("setExitStatus to \(to) \(self.command)");
                self.exitStatus = to;
            }
            
            func setExitSignal(to: String) -> Void {
                LogSSH("setExitSignal to \(to) \(self.command)");
                self.exitSignal = to;
            }
            
            func sendEndSignal() {
                self.semaphore.signal();
            }
        }
        
        let exitState = ExitState(command: command, uuid: commandUUID);
                        
        LogSSH("Try create channel for \(command)");
        
        let channel = try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<ssh_channel, Error>) in
            self.dispatchQueue.async {
                var triesLeft = 5;
                var lastError: SSHError?;
                var success: Bool = false;
                while (triesLeft > 0) {
                    let channel = ssh_channel_new(self.session);
                    if channel == nil {
                        lastError = SSHError.CAN_NOT_OPEN_CHANNEL;
                        triesLeft -= 1;
                        return;
                    }
                    
                    let rc = ssh_channel_open_session(channel);
                    
                    if rc == SSH_OK {
                        continuation.resume(returning: channel!);
                        success = true;
                        break;
                    } else {
                        ssh_channel_free(channel);
                        lastError = SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
                        triesLeft -= 1;
                    }
                }
                if !success, let lastError = lastError {
                    continuation.resume(throwing: lastError);
                }
            }
        });
        
        // free the libssh resources
        defer {
            LogSSH("+ free ssh_channel_close \(command) eof=\(ssh_channel_is_eof(channel))")
            ssh_channel_close(channel);
            LogSSH("* free ssh_channel_free \(command)")
            ssh_channel_free(channel);
            LogSSH("- free \(command)")
        }
        
        // Create callback struct to find out when the command exit
        
        var cbs = ssh_channel_callbacks_struct();

        cbs.userdata = unsafeBitCast(exitState, to: UnsafeMutableRawPointer.self);
                
        cbs.channel_exit_signal_function = { (session, channel, signal, core, errmsg, lang, userdata) in
            Task {
                if let signal = signal, let userdata = userdata {
                    if let signalString = String(cString: signal, encoding: .utf8) {
                        let localExitState = Unmanaged<ExitState>.fromOpaque(userdata).takeUnretainedValue()
                        LogSSH("channel_exit_signal_function for \(localExitState.command)")
                        await localExitState.setExitSignal(to: signalString);
                        // Sometimes we never get a exit signal or channel close event
                        if signalString == "KILL" {
                            await localExitState.sendEndSignal();
                        }
                    }
                }
            }
        }
        
        cbs.channel_exit_status_function = { (session, channel, exit_status, userdata) in
            Task {
                if let userdata = userdata {
                    let localExitState = Unmanaged<ExitState>.fromOpaque(userdata).takeUnretainedValue()
                    LogSSH("channel_exit_status_function + \(localExitState.command)")
                    await localExitState.setExitStatus(to: Int(exit_status));
                    LogSSH("channel_exit_status_function - \(localExitState.command)")
                }
            }
        }
        
        cbs.channel_eof_function = { session, channel, userdata in
            if let userdata = userdata {
                let localExitState = Unmanaged<ExitState>.fromOpaque(userdata).takeUnretainedValue()
                LogSSH("+/- channel_eof_function \(localExitState.command)")
            }
        }
        
        cbs.channel_close_function = { session, channel, userdata in
            Task {
                if let userdata = userdata {
                    let localExitState = Unmanaged<ExitState>.fromOpaque(userdata).takeUnretainedValue()
                    LogSSH("+ channel_close_function \(localExitState.command)")
                    await localExitState.sendEndSignal();
                    LogSSH("- channel_close_function \(localExitState.command)")
                }
            }
        }
        
        cbs.size = MemoryLayout.size(ofValue: cbs);
                            
        ssh_set_channel_callbacks(channel, &cbs);
        
        defer {
            LogSSH("+ ssh_remove_channel_callbacks \(command)")
            ssh_remove_channel_callbacks(channel, &cbs);
            LogSSH("- ssh_remove_channel_callbacks \(command)")
        }
                
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                LogSSH("+ ssh_channel_request_exec for \(command)")
                let rc = ssh_channel_request_exec(channel, command);
                LogSSH("- ssh_channel_request_exec for \(command)")
                if rc == SSH_OK {
                    continuation.resume();
                } else {
                    continuation.resume(throwing: SSHError.REQUEST_EXEC_ERROR(rc));
                }
            }
        })
        
        async let stdout = withCheckedContinuation({ (continuation: CheckedContinuation<String, Never>) in
            self.dispatchQueue.async {
                var stdout = "";
                let count = 256
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                
                defer {
                    buffer.deallocate();
                }
                
                LogSSH("Read \(count) bytes from STDOUT for command \(command)");
                
                var nbytesStdout = ssh_channel_read(channel, buffer, UInt32(count * MemoryLayout<CChar>.size), 0)
                
                LogSSH("Finish reading \(count) bytes from STDOUT for command \(command). Actually read \(nbytesStdout) bytes.");
                
                repeat {
                    stdout += self.convertCharPointerToString(pointer: buffer, bytesToCopy: nbytesStdout);
                    
                    LogSSH("Read \(count) bytes from STDOUT for command \(command). Channel: eof=\(ssh_channel_is_eof(channel)) closed=\(ssh_channel_is_closed(channel))");
                    
                    nbytesStdout = ssh_channel_read(channel, buffer, UInt32(count * MemoryLayout<CChar>.size), 0)
                    
                    LogSSH("Finish reading \(count) bytes from STDOUT for command \(command). Actually read \(nbytesStdout) bytes. Channel: eof=\(ssh_channel_is_eof(channel)) closed=\(ssh_channel_is_closed(channel))");
                } while (nbytesStdout > 0);
                
                LogSSH("End reading STDOUT for \(command) nbytesStdout=\(nbytesStdout)");
                
                continuation.resume(returning: stdout);
            }
        });
        
        async let stderr = withCheckedContinuation({ (continuation: CheckedContinuation<String, Never>) in
            self.dispatchQueue.async {
                var stderr = "";
                let count = 256
                let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                
                defer {
                    buffer.deallocate();
                }
                
                LogSSH("Read \(count) bytes from STDERR for command \(command)");
                
                var nbytesSterr = ssh_channel_read(channel, buffer, UInt32(count * MemoryLayout<CChar>.size), 1)
                
                LogSSH("Finish reading \(count) bytes from STDERR for command \(command). Actually read \(nbytesSterr) bytes.");
                
                repeat {
                    stderr += self.convertCharPointerToString(pointer: buffer, bytesToCopy: nbytesSterr);
                    
                    LogSSH("Read \(count) bytes from STDERR for command \(command). Channel: eof=\(ssh_channel_is_eof(channel)) closed=\(ssh_channel_is_closed(channel))");
                    
                    nbytesSterr = ssh_channel_read(channel, buffer, UInt32(count * MemoryLayout<CChar>.size), 1)
                    
                    LogSSH("Finish reading \(count) bytes from STDERR for command \(command). Actually read \(nbytesSterr) bytes. Channel: eof=\(ssh_channel_is_eof(channel)) closed=\(ssh_channel_is_closed(channel))");
                } while (nbytesSterr > 0);
                
                LogSSH("End reading STDERR for \(command) nbytesSterr=\(nbytesSterr)");
                
                continuation.resume(returning: stderr);
            }
        });
        
        LogSSH("Wait for exit \(command)");
        
        let finalExitState = await withCheckedContinuation { (continuation: CheckedContinuation<(Int, String?), Never>) in
            DispatchQueue(label: "ssh-wait-exit-\(commandUUID)").async {
                Task {
                    exitState.semaphore.wait();
                    let exitStatus = await exitState.exitStatus ?? -3;
                    let exitSignal = await exitState.exitSignal;
                    continuation.resume(returning: (exitStatus, exitSignal));
                }
            }
        };
        
        LogSSH("Wait for std \(command)");
        
        let stdArray = await [stdout, stderr];
        
        LogSSH("Finish \(command) signal=\(finalExitState.1 ?? nil) code=\(Int32(finalExitState.0))");
        
        return SSHExecResult(stdout: stdArray[0], stderr: stdArray[1], exitCode: Int32(finalExitState.0), exitSignal: finalExitState.1);
    }
    
    /// Convert a unsafe pointer returned by a libssh function to a normal string with a specific amount of bytes.
    ///
    /// - parameter pointer: Our pointer used in a libssh function
    /// - parameter bytesToCopy: The amount of bytes to copy
    /// - returns: String copied from the pointer
    private func convertCharPointerToString(pointer: UnsafeMutablePointer<CChar>, bytesToCopy: Int32) -> String {
        var charDataArray: [UInt8] = [];
        for i in 0..<Int(bytesToCopy) {
            charDataArray.append((pointer + i).pointee.magnitude);
        }
        let data = Data(charDataArray);
        
        return String(data: data, encoding: .utf8) ?? "";
    }
    
    deinit {
        self.connectionLock.lock();
        if self.session != nil {
            ssh_free(self.session);
            self.session = nil;
        }
        self.connectionLock.unlock();
    }
}
