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
    private let cmdLock = NSLock();
    
    public init(options: SSHOption) {
        self.options = options;
        
        ssh_init();
        
        ssh_set_log_level(Int32(SSH_LOG_WARNING));
    }
    
    private func initSession() {
        self.sessionLock.lock();
        self.session = ssh_new();
        
        var port = options.port;
        
        if self.session != nil {
            ssh_options_set(self.session, SSH_OPTIONS_HOST, options.host);
            ssh_options_set(self.session, SSH_OPTIONS_PORT, &port);
            ssh_set_blocking(self.session, 0);
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
                        
        var ssh_callbacks = ssh_callbacks_struct();
        
        ssh_callbacks.channel_open_request_auth_agent_function = { session, userdata in
            LogSSH("Deny channel_open_request_auth_agent_function")
            return nil;
        }
        
        
        ssh_callbacks.connect_status_function = { session, status in
            LogSSH("Connection progress: \(status)")
        }
        
        ssh_callbacks.size = MemoryLayout.size(ofValue: ssh_callbacks);
        
        ssh_set_callbacks(self.session, &ssh_callbacks);
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                Task {
                    var rc = ssh_connect(self.session);
                    
                    while (rc == SSH_AGAIN) {
                        rc = ssh_connect(self.session);
                        LogSSH("ssh_connect == SSH_AGAIN")
                        try await Task.sleep(nanoseconds: 10000);
                    }
                    
                    if rc != SSH_OK {
                        let errorString = String(cString: ssh_get_error(&self.session));
                        LogSSH("ssh_connect != SSH_OK: \(errorString)")
                        continuation.resume(throwing: SSHError.CONNECTION_ERROR(errorString));
                        self.connectionLock.unlock();
                    } else {
                        self.ssh_connected = true;
                        continuation.resume();
                    }
                }
            }
        }
        
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            self.dispatchQueue.async {
                Task {
                    var ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
                    
                    while (ra == SSH_AUTH_AGAIN.rawValue) {
                        ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
                        LogSSH("ssh_userauth_password == SSH_AUTH_AGAIN")
                        try await Task.sleep(nanoseconds: 10000);
                    }
                    
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
        self.cmdLock.lock();
        var regularUnlock = false;
        let commandUUID = UUID().uuidString;
        let localDispatch = DispatchQueue(label: "ssh-exec-\(commandUUID)");
        
        defer {
            if !regularUnlock {
                self.cmdLock.unlock();
            }
        }
        
        if !(await self.isConnected()) {
            try await self.connect();
        }
        
        LogSSH("exec: \(command)");
        
        actor ExitState {
            var exitStatus: Int?;
            var exitSignal: String?;
            
            let semaphore = DispatchSemaphore(value: 0);
            let semaphoreStd = DispatchSemaphore(value: 0);
            
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
            localDispatch.async {
                Task {
                    var triesLeft = 5;
                    var lastError: SSHError?;
                    var success: Bool = false;
                    while (triesLeft > 0) {
                        LogSSH("+ ssh_channel_new for \(command)")
                        let channel = ssh_channel_new(self.session);
                        LogSSH("- ssh_channel_new for \(command)")
                        if channel == nil {
                            LogSSH("CAN_NOT_OPEN_CHANNEL: Tries left \(triesLeft) for \(command)");
                            lastError = SSHError.CAN_NOT_OPEN_CHANNEL;
                            triesLeft -= 1;
                            return;
                        }
                        
                        LogSSH("+ ssh_channel_open_session for \(command)")
                        
                        var rc = ssh_channel_open_session(channel);
                        
                        LogSSH("- ssh_channel_open_session for \(command)")
                        
                        while (rc == SSH_AGAIN) {
                            rc = ssh_channel_open_session(channel);
                            LogSSH("ssh_channel_open_session = SSH_AGAIN");
                            try await Task.sleep(nanoseconds: 10000);
                        }
                        
                        if rc == SSH_OK {
                            continuation.resume(returning: channel!);
                            success = true;
                            break;
                        } else {
                            ssh_channel_free(channel);
                            lastError = SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
                            triesLeft -= 1;
                            LogSSH("CAN_NOT_OPEN_CHANNEL_SESSION: Tries left \(triesLeft) for \(command)");
                        }
                    }
                    if !success, let lastError = lastError {
                        continuation.resume(throwing: lastError);
                    } else {
                        
                        LogSSH("Got here")
                    }
                }
            }
        });
        
        self.cmdLock.unlock();
        regularUnlock = true;
        
        LogSSH("Channel for \(command) created");
        
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
        
        self.cmdLock.lock();
        regularUnlock = false;
                
        try await withCheckedThrowingContinuation({ (continuation: CheckedContinuation<Void, Error>) in
            localDispatch.async {
                Task {
                    LogSSH("+ ssh_channel_request_exec for \(command)")
                    var rc = ssh_channel_request_exec(channel, command);
                    
                    while (rc == SSH_AGAIN) {
                        rc = ssh_channel_request_exec(channel, command);
                        LogSSH("ssh_channel_request_exec = SSH_AGAIN");
                        try await Task.sleep(nanoseconds: 10000);
                    }
                    
                    LogSSH("- ssh_channel_request_exec for \(command)")
                    if rc == SSH_OK {
                        continuation.resume();
                    } else {
                        continuation.resume(throwing: SSHError.REQUEST_EXEC_ERROR(rc));
                    }
                }
            }
        })
        
        self.cmdLock.unlock();
        regularUnlock = true;
        
        async let std = withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(stdout: String, stderr: String), Error>) in
            localDispatch.async {
                Task {
                    var stdout = "";
                    var stderr = "";
                    let count = 65536
                    let bufferStdout = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                    let bufferStderr = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                    
                    defer {
                        bufferStdout.deallocate();
                        bufferStderr.deallocate();
                    }
                    
                    while (ssh_channel_is_open(channel) > 0 && ssh_channel_is_eof(channel) != 1) {
                        LogSSH("Read \(count) bytes from STD for command \(command)");
                        
                        let nbytesStdout = ssh_channel_read_nonblocking(channel, bufferStdout, UInt32(count * MemoryLayout<CChar>.size), 0);
                        
                        let nbytesStderr = ssh_channel_read_nonblocking(channel, bufferStderr, UInt32(count * MemoryLayout<CChar>.size), 1);
                        
                        LogSSH("Finish reading \(count) bytes from STDOUT for command \(command). Actually read \(nbytesStdout) bytes.");
                        LogSSH("Finish reading \(count) bytes from STDERR for command \(command). Actually read \(nbytesStderr) bytes.");
                    
                        if nbytesStdout == SSH_EOF, nbytesStderr == SSH_EOF {
                            break;
                        }
                        
                        if nbytesStdout > 0 {
                            stdout += self.convertCharPointerToString(pointer: bufferStdout, bytesToCopy: nbytesStdout);
                        }
                        if nbytesStderr > 0 {
                            stderr += self.convertCharPointerToString(pointer: bufferStderr, bytesToCopy: nbytesStderr);
                        }
                        
                        if nbytesStdout < 0 || nbytesStderr < 0 {
                            exitState.semaphoreStd.signal();
                            continuation.resume(returning: (stdout, stderr));
                            return;
                        }
                        
                        try await Task.sleep(nanoseconds: 1000);
                    }
                    
                    LogSSH("End reading STD for \(command)");
                    
                    exitState.semaphoreStd.signal();
                    
                    continuation.resume(returning: (stdout, stderr));
                }
            }
        });
        
        LogSSH("Wait for exit \(command)");
        
        let finalExitState = await withCheckedContinuation { (continuation: CheckedContinuation<(Int, String?), Never>) in
            localDispatch.async {
                Task {
                    exitState.semaphoreStd.wait();
                    let _ = exitState.semaphore.wait(timeout: .now() + 0.1);
                    let exitStatus = await exitState.exitStatus ?? Int(ssh_channel_get_exit_status(channel));
                    let exitSignal = await exitState.exitSignal;
                    continuation.resume(returning: (exitStatus, exitSignal));
                }
            }
        };
        
        LogSSH("Wait for std \(command)");
        
        let stdArray = try await std;
                
        return SSHExecResult(stdout: stdArray.stdout, stderr: stdArray.stderr, exitCode: Int32(finalExitState.0), exitSignal: finalExitState.1);
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
