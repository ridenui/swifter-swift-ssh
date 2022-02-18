//
//  SSHConnection.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 20/12/2021.
//

import Foundation

var cmdId: Int = 0;

class SSHConnection {
    private let options: SSHOption;
    private var session: ssh_session?;
    private var channel: ssh_channel?;
    private var authenticated: Bool = false;
    private var channelRef = 0;
    private var channelLock = NSLock();
    private var sessionLock = NSLock();
    
    public var connected: Bool {
        var connected = false;
        
        if self.session != nil {
            try? self.doUnsafeTaskBlocking(task: {
                connected = ssh_is_connected(self.session) > 0;
            }, timeout: .now() + 1);
        }
        
        return authenticated && connected;
    }
    
    public init(options: SSHOption) async throws {
        self.options = options;
                
        try self.createSession();
    }
    
    private func invalidateSession(lock: Bool = true) {
        if lock {
            self.sessionLock.lock();
        }
        defer {
            if lock {
                self.sessionLock.unlock();
            }
        }
        LogSSH("+ invalidateSession")
        if let session = self.session {
            LogSSH("+ ssh_free")
            try? self.doUnsafeTaskBlocking(task: {
                ssh_free(session);
            }, timeout: .now() + 0.5);
            LogSSH("- ssh_free")
        }
        self.session = nil;
        LogSSH("- invalidateSession")
    }
    
    private func createSession(lock: Bool = true) throws {
        if lock {
            self.sessionLock.lock();
        }
        defer {
            if lock {
                self.sessionLock.unlock();
            }
        }
        LogSSH("+ createSession()")
        self.invalidateSession(lock: false);
        
        var port = options.port;
        
        guard let session = ssh_new() else {
            throw SSHError.CAN_NOT_OPEN_SESSION;
        }
        
        LogSSH("\(options.username)@\(options.host):\(options.port)")
        
        ssh_options_set(session, SSH_OPTIONS_HOST, options.host);
        ssh_options_set(session, SSH_OPTIONS_PORT, &port);
        ssh_options_set(session, SSH_OPTIONS_USER, options.username);
        var logLevel = SSH_LOG_FUNCTIONS;
        ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &logLevel);
        ssh_set_blocking(session, 0);
        
        if let idRsaLocation = options.idRsaLocation {
            ssh_options_set(session, SSH_OPTIONS_ADD_IDENTITY, idRsaLocation);
        }
        
        if let knownHostFile = options.knownHostFile {
            ssh_options_set(session, SSH_OPTIONS_KNOWNHOSTS, knownHostFile);
        }
        
        self.session = session;
        LogSSH("- createSession()")
    }
    
    public func connect() async throws {
        self.sessionLock.lock();
        defer {
            self.sessionLock.unlock();
        }
        var ra: Int32 = SSH_OK;
        
        if self.session != nil {
            self.disconnect(lock: false)
        }
        
        try self.createSession(lock: false)
                
        if ssh_is_connected(self.session!) < 1 || self.connected == false {
            self.authenticated = false;
            
            if let channel = self.channel {
                ssh_channel_free(channel);
                self.channel = nil;
            }
            
            LogSSH("ssh_connect")
            
            if ssh_is_connected(self.session) > 0 {
                self.disconnect(lock: false);
            }
            
            let connectStarted: DispatchTime = .now();
            
            var rc = try await self.doUnsafeTask {
                ssh_connect(self.session);
            };
            
            while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
                try Task.checkCancellation()
                rc = try await self.doUnsafeTask {
                    ssh_connect(self.session);
                };
                try await Task.sleep(nanoseconds: 10000);
            }
            
            try Task.checkCancellation()
            
            let isTimeOut = connectStarted < .now() - 5;
            
            if rc != SSH_OK {
                if isTimeOut {
                    LogSSH("Connection timeout")
                    self.disconnect(lock: false)
                    throw SSHError.SSH_CONNECT_TIMEOUT;
                }
                let errorPointer: UnsafeMutableRawPointer = .init(self.session!);
                if let errorCChar = ssh_get_error(errorPointer) {
                    let errorString = self.convertCharPointerToString(pointer: errorCChar);
                    if errorString.contains("unconnected") {
                        throw SSHError.SOCKET_UNCONNECTED
                    }
                    LogSSH("libssh error string \(errorString)");
                    self.disconnect(lock: false)
                    throw SSHError.CONNECTION_ERROR(errorString);
                } else {
                    self.disconnect(lock: false)
                    throw SSHError.CONNECTION_ERROR("unknown connection error");
                }
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
            self.disconnect(lock: false)
            throw SSHError.AUTH_DENIED;
        } else if ra == SSH_AUTH_ERROR.rawValue {
            self.disconnect(lock: false)
            throw SSHError.AUTH_ERROR;
        } else {
            self.disconnect(lock: false)
            throw SSHError.AUTH_ERROR_OTHER(ssh_auth_e(ra));
        }
    }
    
    private func openChannel() async throws {
        self.cleanUpChannel();
        
        LogSSH("ssh_channel_new")
        
        self.sessionLock.lock();
        
        defer {
            self.sessionLock.unlock();
        }
        
        guard let channel = ssh_channel_new(self.session) else {
            throw SSHError.CAN_NOT_OPEN_CHANNEL;
        }
        
        LogSSH("ssh_channel_open_session")
        
        self.channelLock.lock();
        
        defer {
            self.channelLock.unlock();
        }
        
        var rc = ssh_channel_open_session(channel);
        
        let connectStarted: DispatchTime = .now();
        
        while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
            try Task.checkCancellation()
            rc = ssh_channel_open_session(channel);
            try await Task.sleep(nanoseconds: 10000);
        }
        
        let isTimeOut = connectStarted < .now() - 5;
        
        if rc == SSH_OK {
            self.channel = channel;
            return;
        } else {
            ssh_channel_free(channel);
            if isTimeOut {
                throw SSHError.SSH_CHANNEL_TIMEOUT;
            }
            throw SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
        }
    }
    
    private func cleanUpChannel() {
        self.channelLock.lock();
        defer {
            self.channelLock.unlock();
        }
        self.channelRef += 1;
        if let channel = self.channel {
            let _ = try? self.doUnsafeTaskBlocking(task: {
                LogSSH("Send QUIT")
                ssh_channel_request_send_signal(channel, "QUIT");
            }, timeout: .now() + 0.4)
            
            let _ = try? self.doUnsafeTaskBlocking(task: {
                LogSSH("ssh_channel_free")
                ssh_channel_free(channel);
            }, timeout: .now() + 0.4)
            self.channel = nil;
        }
    }
    
    public func disconnect(lock: Bool = true) {
        self.cleanUpChannel();
        
        try? self.doUnsafeTaskBlocking(task: {
            LogSSH("ssh_disconnect")
            ssh_disconnect(self.session);
        }, timeout: .now() + 1)
        
        self.authenticated = false;
        
        self.invalidateSession(lock: lock);
    }
    
    func exec(command: String) async throws -> SSHExecResult {
        return try await self.exec(command: command, delegate: nil);
    }
    
    func exec(command: String, delegate: SSHExecDelegate?) async throws -> SSHExecResult {
        return try await self.exec(commandInput: command, delegate: delegate, notCancelable: false);
    }
    
    func exec(command: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        return try await self.exec(commandInput: command, delegate: delegate, notCancelable: notCancelable);
    }
    
    func exec(commandInput: String, delegate: SSHExecDelegate?, notCancelable: Bool = false) async throws -> SSHExecResult {
        if !self.connected {
            try await self.connect();
        }
        try await self.openChannel();
        
        let commandUUID = UUID().uuidString;
        let localDispatch = DispatchQueue(label: "ssh-exec-\(commandUUID)");
        
        var command = commandInput;
        
        if !notCancelable {
            let cmd64 = Data(command.utf8).base64EncodedString();
            
            command = """
                bash -c "eval \\`echo \"\(cmd64)\" | base64 --decode\\`" &
                PID=$!
                echo $$ > /tmp/\(commandUUID)-parent.pid
                wait $PID
                EXIT_CODE=$?
                if [[ -f /tmp/\(commandUUID)-parent.pid ]]; then
                    rm /tmp/\(commandUUID)-parent.pid
                fi
                exit $EXIT_CODE
            """
            
            LogSSH("New command: \(command)");
        }
        
        // connect makes sure we have an channel
        let channel = self.channel!;
        let optionalChannel = self.channel;
        let currentChannelRef = self.channelRef;
                        
        try Task.checkCancellation()
                
        actor ExitHandler {
            var exitStatus: Int?;
            var exitSignal: String?;
            
            let semaphore = DispatchSemaphore(value: 0);
            let semaphoreStd = DispatchSemaphore(value: 0);
            
            var canSendSignal = false;
            
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
                LogSSH("+ sendEndSignal \(std)")
                if std {
                    self.semaphoreStd.signal();
                } else {
                    self.semaphore.signal();
                }
                LogSSH("- sendEndSignal \(std)")
            }
            
            func setCanSendSignal(to: Bool) {
                self.canSendSignal = to;
            }
        }
        
        class UserData {
            internal init(exitHandler: ExitHandler, connection: SSHConnection) {
                self.exitHandler = exitHandler
                self.connection = connection
            }
            
            let exitHandler: ExitHandler;
            let connection: SSHConnection;
        }
        
        let exitHandler = ExitHandler(command: command);
        
        let userData = UserData(exitHandler: exitHandler, connection: self);
        
        var cbs = ssh_channel_callbacks_struct();

        cbs.userdata = unsafeBitCast(userData, to: UnsafeMutableRawPointer.self);
        
        cbs.channel_exit_signal_function = { (session, channel, signal, core, errmsg, lang, userdata) in
            guard let userdata = userdata else {
                LogSSH("channel_exit_signal_function - No userdata");
                return;
            }
            guard let signal = signal else {
                LogSSH("channel_exit_signal_function - No signal");
                return;
            }
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue()
            
            let signalString = localUserData.connection.convertCharPointerToString(pointer: signal);
            
            LogSSH("+ channel_exit_signal_function \(signalString)")
            
            Task {
                try Task.checkCancellation()
                await localUserData.exitHandler.setExitSignal(to: signalString);
                LogSSH("- channel_exit_signal_function \(signalString)")
            }
        }
        
        cbs.channel_exit_status_function = { (session, channel, exit_status, userdata) in
            guard let userdata = userdata else {
                LogSSH("channel_exit_status_function - No userdata");
                return;
            }
            let exitStatus = exit_status;
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue()
            
            LogSSH("+ channel_exit_status_function \(exitStatus)")
            
            Task {
                try Task.checkCancellation()
                await localUserData.exitHandler.setExitStatus(to: Int(exitStatus));
                LogSSH("- channel_exit_status_function \(exitStatus)")
            }
        }
        
        cbs.size = MemoryLayout.size(ofValue: cbs);
        
        LogSSH("ssh_set_channel_callbacks")
        
        self.sessionLock.lock();
        self.channelLock.lock();
                            
        ssh_set_channel_callbacks(channel, &cbs);
        
        self.sessionLock.unlock();
        self.channelLock.unlock();
        
        defer {
            if optionalChannel != nil, currentChannelRef == self.channelRef {
                ssh_remove_channel_callbacks(optionalChannel!, &cbs);
            }
        }
        
        LogSSH("ssh_channel_request_exec")
        
        var rc = try await self.doUnsafeTask(task: {
            self.sessionLock.lock();
            self.channelLock.lock();
            defer {
                self.sessionLock.unlock();
                self.channelLock.unlock();
            }
            return ssh_channel_request_exec(channel, command);
        }, timeout: .now() + 3) ?? SSH_ERROR;
        
        while (rc == SSH_AGAIN) {
            try Task.checkCancellation()
            rc = try await self.doUnsafeTask(task: {
                self.sessionLock.lock();
                self.channelLock.lock();
                defer {
                    self.sessionLock.unlock();
                    self.channelLock.unlock();
                }
                return ssh_channel_request_exec(channel, command);
            }, timeout: .now() + 3) ?? SSH_ERROR;
            try await Task.sleep(nanoseconds: 10000);
        }
        
        if let delegate = delegate {
            if let cancelFunction = delegate.cancelFunction {
                localDispatch.async {
                    LogSSH("Pass cancel func")
                    cancelFunction(commandUUID);
                }
            } else {
                LogSSH("cancelFunction is nil")
            }
        } else {
            LogSSH("delegate is nil")
        }
        
        await exitHandler.setCanSendSignal(to: true);
        
        try Task.checkCancellation()
        
        if rc != SSH_OK {
            throw SSHError.REQUEST_EXEC_ERROR(rc);
        }
        
        let result = try await withThrowingTaskGroup(of: Any.self, returning: (std: (stdout: String, stderr: String), exitStatus: (code: Int, signal: String?)).self, body: { taskGroup in
            
            taskGroup.addTask {
                LogSSH("Start stdAsync Task");
                var stdout = "";
                var stderr = "";
                let count = 65536
                let bufferStdout = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                let bufferStderr = UnsafeMutablePointer<CChar>.allocate(capacity: count)
                
                defer {
                    bufferStdout.deallocate();
                    bufferStderr.deallocate();
                }
                
                var readErrorsTimeout = 0
                var readErrors = 0
                
                func lock() -> Bool {
                    self.sessionLock.lock();
                    self.channelLock.lock();
                    return true;
                }
                
                func unlock() {
                    self.sessionLock.unlock();
                    self.channelLock.unlock();
                }
                                    
                while (lock() && ssh_channel_is_open(channel) > 0 && ssh_channel_is_eof(channel) != 1 && currentChannelRef == self.channelRef) {
                    unlock();
                    try Task.checkCancellation()
                    
                    let nbytesStdout = try await self.doUnsafeTask(task: {
                        if currentChannelRef == self.channelRef {
                            let _ = lock()
                            defer {
                                unlock()
                            }
                            return Int(ssh_channel_read_nonblocking(channel, bufferStdout, UInt32(count * MemoryLayout<CChar>.size), 0));
                        }
                        return -1337
                    }, timeout: .now() + 0.8) ?? -1337;
                    
                    if nbytesStdout == -1337 {
                        readErrorsTimeout += 1
                    } else if nbytesStdout < 0 {
                        readErrors += 1
                    }
                    
                    try Task.checkCancellation()
                    
                    let nbytesStderr = try await self.doUnsafeTask(task: {
                        if currentChannelRef == self.channelRef {
                            let _ = lock()
                            defer {
                                unlock()
                            }
                            return Int(ssh_channel_read_nonblocking(channel, bufferStderr, UInt32(count * MemoryLayout<CChar>.size), 1));
                        }
                        return -1337
                    }, timeout: .now() + 0.8) ?? -1337;
                                        
                    if nbytesStderr == -1337 {
                        readErrorsTimeout += 1
                    } else if nbytesStderr < 0 {
                        readErrors += 1
                    }
                    
                    // LogSSH("Read nbytesStdout=\(nbytesStdout) nbytesStderr=\(nbytesStderr)");
                    
                    if nbytesStdout == SSH_EOF, nbytesStderr == SSH_EOF {
                        break;
                    }
                    
                    if nbytesStdout > 0 {
                        let new = self.convertCharPointerToString(pointer: bufferStdout, bytesToCopy: Int32(nbytesStdout));
                        stdout += new;
                        if let delegate = delegate {
                            if let onStdout = delegate.onStdout {
                                localDispatch.async {
                                    onStdout(new);
                                }
                            }
                        }
                    }
                    if nbytesStderr > 0 {
                        let new = self.convertCharPointerToString(pointer: bufferStderr, bytesToCopy: Int32(nbytesStderr));
                        stderr += new;
                        if let delegate = delegate {
                            if let onStderr = delegate.onStderr {
                                localDispatch.async {
                                    onStderr(new);
                                }
                            }
                        }
                    }
                    
                    if readErrors > 10 || readErrorsTimeout > 4 {
                        LogSSH("end std while \(exitHandler.command) nbytesStdout=\(nbytesStdout) nbytesStderr=\(nbytesStderr)")
                        await exitHandler.sendEndSignal(std: true);
                        return (stdout, stderr);
                    }
                    
                    try await Task.sleep(nanoseconds: 500000);
                }
                
                unlock()
                
                try Task.checkCancellation()
                
                LogSSH("end std \(exitHandler.command)")

                await exitHandler.sendEndSignal(std: true);
                
                return (stdout, stderr);
            }
            
            taskGroup.addTask(priority: .background, operation: {
                try Task.checkCancellation()
                LogSSH("Wait std semaphore")
                while (exitHandler.semaphoreStd.wait(timeout: .now() + 0.0000001) == .timedOut) {
                    try await Task.sleep(nanoseconds: 10000000);
                }
                try Task.checkCancellation()
                LogSSH("Wait semaphore")
                let end: DispatchTime = .now() + 0.3;
                while (exitHandler.semaphore.wait(timeout: .now() + 0.00000001) == .timedOut && end > .now()) {
                    try await Task.sleep(nanoseconds: 10000000);
                }
                if end <= .now() {
                    LogSSH("Wait semaphore timeout");
                }
                await exitHandler.setCanSendSignal(to: false);
                let exitStatus = await exitHandler.exitStatus ?? -10;
                let exitSignal = await exitHandler.exitSignal;
                if self.connected {
                    LogSSH("+ ssh_channel_send_eof \( exitHandler.command)");
                    let _ = try? await self.doUnsafeTask(task: {
                        self.channelLock.lock()
                        self.sessionLock.lock()
                        defer {
                            self.channelLock.unlock()
                            self.sessionLock.unlock()
                        }
                        if self.channelRef == currentChannelRef {
                            ssh_channel_send_eof(channel);
                        }
                    }, timeout: .now() + 1);
                    LogSSH("- ssh_channel_send_eof \( exitHandler.command)");
                }
                return (exitStatus, exitSignal);
            })
            
            let std = try await taskGroup.next();
            let exitStatus = try await taskGroup.next();
            
            
            return (std: std as! (stdout: String, stderr: String), exitStatus: exitStatus as! (code: Int, signal: String?));
        })
        
        let std = result.std;
        
        let finalExitState = result.exitStatus;
        
        return SSHExecResult(stdout: std.stdout, stderr: std.stderr, exitCode: Int32(finalExitState.code), exitSignal: finalExitState.signal);
    }
    
    /// Convert a unsafe pointer returned by a libssh function to a normal string with a specific amount of bytes.
    ///
    /// - parameter pointer: Our pointer used in a libssh function
    /// - parameter bytesToCopy: The amount of bytes to copy
    /// - returns: String copied from the pointer
    private nonisolated func convertCharPointerToString(pointer: UnsafeMutablePointer<CChar>, bytesToCopy: Int32) -> String {
        var charDataArray: [UInt8] = [];
        for i in 0..<Int(bytesToCopy) {
            charDataArray.append((pointer + i).pointee.magnitude);
        }
        let data = Data(charDataArray);
        
        return String(data: data, encoding: .utf8) ?? "";
    }
    
    private nonisolated func convertCharPointerToString(pointer: UnsafePointer<CChar>) -> String {
        var charDataArray: [UInt8] = [];
        var i = 0;
        while (true) {
            if (pointer + i).pointee.magnitude == 0 {
                break;
            }
            charDataArray.append((pointer + i).pointee.magnitude);
            i += 1;
        }
        let data = Data(charDataArray);
        
        return String(data: data, encoding: .ascii) ?? "";
    }
    
    /// Run a task on a separate thread and time out after a specific time
    /// This should help us prevent dead locks when we call libssh functions
    /// - Returns: return value of task
    private nonisolated func doUnsafeTask<T>(task: @escaping () -> T, timeout: DispatchTime = .now() + 5) async throws -> T? {
        var returnValue: T?;
        let thread = Thread.init {
            returnValue = task();
        }
        thread.start()
        
        while (!thread.isFinished && !thread.isCancelled) {
            if timeout < .now() {
                thread.cancel()
                LogSSH("doUnsafeTask timed out")
                throw SSHError.GENERAL_UNSAFE_TASK_TIMEOUT;
            }
            try await Task.sleep(nanoseconds: 10000);
        }
        
        return returnValue;
    }
    
    /// Run a task on a separate thread and time out after a specific time
    /// This should help us prevent dead locks when we call libssh functions
    /// - Returns: return value of task
    private nonisolated func doUnsafeTaskBlocking<T>(task: @escaping () -> T, timeout: DispatchTime = .now() + 5) throws -> T? {
        var returnValue: T?;
        let thread = Thread.init {
            returnValue = task();
        }
        thread.start()
        
        while (!thread.isFinished && !thread.isCancelled) {
            if timeout < .now() {
                thread.cancel()
                LogSSH("doUnsafeTaskBlocking timed out")
                throw SSHError.GENERAL_UNSAFE_TASK_TIMEOUT;
            }
        }
        
        return returnValue;
    }
    
    deinit {
        self.disconnect();
    }
    
}
