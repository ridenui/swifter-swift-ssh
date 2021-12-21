//
//  SSHConnection.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 20/12/2021.
//

import Foundation

actor SSHConnection {
    private let options: SSHOption;
    private var session: ssh_session;
    private var channel: ssh_channel?;
    private var authenticated: Bool = false;
    
    public var connected: Bool {
        return authenticated && ssh_is_connected(self.session) > 0;
    }
    
    public init(options: SSHOption) throws {
        self.options = options;
                
        var port = options.port;
        
        guard let session = ssh_new() else {
            throw SSHError.CAN_NOT_OPEN_SESSION;
        }
        
        ssh_options_set(session, SSH_OPTIONS_HOST, options.host);
        ssh_options_set(session, SSH_OPTIONS_PORT, &port);
        ssh_set_blocking(session, 0);
        
        self.session = session;
    }
    
    public func connect() async throws {
        var ra: Int32 = SSH_OK;
                
        if ssh_is_connected(self.session) < 1 {
            self.authenticated = false;
            
            if let channel = self.channel {
                ssh_channel_free(channel);
                self.channel = nil;
            }
            
            LogSSH("ssh_connect")
            
            var rc = ssh_connect(self.session);
            
            while (rc == SSH_AGAIN) {
                try Task.checkCancellation()
                rc = ssh_connect(self.session);
                try await Task.sleep(nanoseconds: 10000);
            }
            
            try Task.checkCancellation()
            
            if rc != SSH_OK {
                let errorString = String(cString: ssh_get_error(&self.session));
                throw SSHError.CONNECTION_ERROR(errorString);
            }
            
            LogSSH("ssh_userauth_password")
            
            ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
            
            while (ra == SSH_AUTH_AGAIN.rawValue) {
                try Task.checkCancellation()
                ra = ssh_userauth_password(self.session, self.options.username, self.options.password);
                try await Task.sleep(nanoseconds: 10000);
            }
        }
        
        try Task.checkCancellation()
        
        if ra == SSH_AUTH_SUCCESS.rawValue {
            self.authenticated = true;
        } else if ra == SSH_AUTH_DENIED.rawValue {
            ssh_disconnect(self.session);
            throw SSHError.AUTH_DENIED;
        } else if ra == SSH_AUTH_ERROR.rawValue {
            ssh_disconnect(self.session);
            throw SSHError.AUTH_ERROR;
        } else {
            ssh_disconnect(self.session);
            throw SSHError.AUTH_ERROR_OTHER(ssh_auth_e(ra));
        }
    }
    
    private func openChannel() async throws {
        self.cleanUpChannel();
        
        LogSSH("ssh_channel_new")
        
        guard let channel = ssh_channel_new(self.session) else {
            throw SSHError.CAN_NOT_OPEN_CHANNEL;
        }
        
        LogSSH("ssh_channel_open_session")
        
        var rc = ssh_channel_open_session(channel);
        
        while (rc == SSH_AGAIN) {
            try Task.checkCancellation()
            rc = ssh_channel_open_session(channel);
            try await Task.sleep(nanoseconds: 10000);
        }
        
        if rc == SSH_OK {
            self.channel = channel;
            return;
        } else {
            ssh_channel_free(channel);
            throw SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
        }
    }
    
    private func cleanUpChannel() {
        if let channel = self.channel {
            ssh_channel_request_send_signal(channel, "QUIT");
            
            ssh_channel_free(channel);
            self.channel = nil;
        }
    }
    
    public func disconnect() {
        self.cleanUpChannel();
        
        ssh_disconnect(self.session);
        self.authenticated = false;
    }
    
    func exec(command: String) async throws -> SSHExecResult {
        if !self.connected {
            try await self.connect();
        }
        try await self.openChannel();
        
        let commandUUID = UUID().uuidString;
        let localDispatch = DispatchQueue(label: "ssh-exec-\(commandUUID)");
        
        // connect makes sure we have an channel
        let channel = self.channel!;
        
        try Task.checkCancellation()
                
        actor ExitHandler {
            var exitStatus: Int?;
            var exitSignal: String?;
            
            let semaphore = DispatchSemaphore(value: 0);
            let semaphoreStd = DispatchSemaphore(value: 0);
            
            let command: String;
            
            init(command: String) {
                self.command = command;
            }
            
            func setExitStatus(to: Int) -> Void {
                LogSSH("setExitStatus \(to) \(command)");
                self.exitStatus = to;
            }
            
            func setExitSignal(to: String) -> Void {
                LogSSH("setExitSignal \(to) \(command)");
                self.exitSignal = to;
            }
            
            func sendEndSignal(std: Bool = false) {
                if std {
                    self.semaphoreStd.signal();
                } else {
                    self.semaphore.signal();
                }
            }
        }
        
        let exitHandler = ExitHandler(command: command);
        
        var cbs = ssh_channel_callbacks_struct();

        cbs.userdata = unsafeBitCast(exitHandler, to: UnsafeMutableRawPointer.self);
        
        cbs.channel_exit_signal_function = { (session, channel, signal, core, errmsg, lang, userdata) in
            Task {
                try Task.checkCancellation()
                if let signal = signal, let userdata = userdata {
                    if let signalString = String(cString: signal, encoding: .utf8) {
                        let localExitHandler = Unmanaged<ExitHandler>.fromOpaque(userdata).takeUnretainedValue()
                        await localExitHandler.setExitSignal(to: signalString);
                        LogSSH("channel_exit_signal_function \(signalString)")
                    }
                }
            }
        }
        
        cbs.channel_eof_function = { (session, channel, userdata) in
            Task {
                try Task.checkCancellation()
                if let userdata = userdata {
                    let localExitHandler = Unmanaged<ExitHandler>.fromOpaque(userdata).takeUnretainedValue()
                    let exit_status = ssh_channel_get_exit_status(channel);
                    LogSSH("channel_eof_function \(localExitHandler.command) \(exit_status)")
                    await localExitHandler.setExitStatus(to: Int(exit_status));
                }
            }
        }
        
        cbs.size = MemoryLayout.size(ofValue: cbs);
        
        LogSSH("ssh_set_channel_callbacks")
                            
        ssh_set_channel_callbacks(channel, &cbs);
        
        defer {
            ssh_remove_channel_callbacks(channel, &cbs);
        }
        
        LogSSH("ssh_channel_request_exec")
        
        var rc = ssh_channel_request_exec(channel, command);
        
        while (rc == SSH_AGAIN) {
            try Task.checkCancellation()
            rc = ssh_channel_request_exec(channel, command);
            try await Task.sleep(nanoseconds: 10000);
        }
        
        try Task.checkCancellation()
        
        if rc != SSH_OK {
            throw SSHError.REQUEST_EXEC_ERROR(rc);
        }
        
        async let stdAsync = withCheckedThrowingContinuation({ (continuation: CheckedContinuation<(stdout: String, stderr: String), Error>) in
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
                        try Task.checkCancellation()
                        let nbytesStdout = ssh_channel_read_nonblocking(channel, bufferStdout, UInt32(count * MemoryLayout<CChar>.size), 0);
                        try Task.checkCancellation()
                        let nbytesStderr = ssh_channel_read_nonblocking(channel, bufferStderr, UInt32(count * MemoryLayout<CChar>.size), 1);
                                            
                        if nbytesStdout == SSH_EOF, nbytesStderr == SSH_EOF {
                            break;
                        }
                        
                        if nbytesStdout > 0 {
                            stdout += await self.convertCharPointerToString(pointer: bufferStdout, bytesToCopy: nbytesStdout);
                        }
                        if nbytesStderr > 0 {
                            stderr += await self.convertCharPointerToString(pointer: bufferStderr, bytesToCopy: nbytesStderr);
                        }
                        
                        if nbytesStdout < 0 || nbytesStderr < 0 {
                            LogSSH("end std while")
                            await exitHandler.sendEndSignal(std: true);
                            continuation.resume(returning: (stdout, stderr));
                            return;
                        }
                        
                        try await Task.sleep(nanoseconds: 1000);
                    }
                    
                    try Task.checkCancellation()
                    
                    LogSSH("end std")

                    await exitHandler.sendEndSignal(std: true);
                    
                    continuation.resume(returning: (stdout, stderr));
                }
            }
        });
        
        try Task.checkCancellation()
        
        let finalExitState = await withCheckedContinuation { (continuation: CheckedContinuation<(code: Int, signal: String?), Never>) in
            localDispatch.async {
                Task {
                    try Task.checkCancellation()
                    exitHandler.semaphoreStd.wait();
                    try Task.checkCancellation()
                    let _ = exitHandler.semaphore.wait(timeout: .now() + 0.3);
                    LogSSH("Real exit \(ssh_channel_get_exit_status(channel)) for \(await exitHandler.command)");
                    let exitStatus = await exitHandler.exitStatus ?? Int(ssh_channel_get_exit_status(channel));
                    let exitSignal = await exitHandler.exitSignal;
                    continuation.resume(returning: (exitStatus, exitSignal));
                }
            }
        };
        
        try Task.checkCancellation()
        
        let std = try await stdAsync;
        
        try Task.checkCancellation()
        
        return SSHExecResult(stdout: std.stdout, stderr: std.stderr, exitCode: Int32(finalExitState.code), exitSignal: finalExitState.signal);
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
        self.disconnect();
        ssh_free(self.session);
    }
    
}
