//
//  SSHSession.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 20/02/2022.
//

import Foundation

enum ConnectionState {
    case NOT_CONNECTED
    case CONNECTED
    case AUTHENTICATED
    case CHANNEL_OPEN
}

typealias ExitSignalCallback = (_ signal: String, _ core: Bool, _ errmsg: String?) -> Void;

typealias ExitStatusCallback = (_ exitStatus: Int32) -> Void;

class UserData {
    public var channel_exit_signal_function: ExitSignalCallback?;
    public var channel_exit_status_function: ExitStatusCallback?;
    
    public var taskId: Int = -2;
}

var globalId = 0;

actor SSHSession {

    private var ssh_session: ssh_session?;
    private var ssh_channel: ssh_channel?;
    private var callbackStruct: ssh_channel_callbacks_struct?;
    private var options: SSHOption;
    private var connectionState: ConnectionState = .NOT_CONNECTED;
    private var userData: UserData = UserData();
    private var id: UUID = UUID();
    private var sessionLock = NSLock();
    private var exceptionHandler = ExceptionHandler();
    
    public var connected: Bool {
        self.connectionState == .CHANNEL_OPEN;
    }
    
    init(options: SSHOption) async throws {
        self.options = options;
        
        self.userData.taskId = SSHLogger.shared.getTaskId();
        
        try self.createSession();
    }
    
    private func createSession() throws {
        SSHLogger.shared.openLog("SSHSessionCreateSession", attributes: ["id": self.id])
        defer {
            SSHLogger.shared.closeLog("SSHSessionCreateSession", attributes: ["id": self.id])
        }
        
        self.ssh_session = ssh_new();
        
        if self.ssh_session == nil {
            throw SSHError.CAN_NOT_OPEN_SESSION;
        }
        
        var port = options.port;
        
        ssh_options_set(self.ssh_session, SSH_OPTIONS_HOST, options.host);
        ssh_options_set(self.ssh_session, SSH_OPTIONS_PORT, &port);
        ssh_options_set(self.ssh_session, SSH_OPTIONS_USER, options.username);
        //var logLevel = SSH_LOG_FUNCTIONS;
        //ssh_options_set(self.ssh_session, SSH_OPTIONS_LOG_VERBOSITY, &logLevel);
        ssh_set_blocking(self.ssh_session, 0);
        
        if let idRsaLocation = options.idRsaLocation {
            ssh_options_set(self.ssh_session, SSH_OPTIONS_ADD_IDENTITY, idRsaLocation);
        }
        
        if let knownHostFile = options.knownHostFile {
            ssh_options_set(self.ssh_session, SSH_OPTIONS_KNOWNHOSTS, knownHostFile);
        }
    }
    
    public func connect() async throws {
        SSHLogger.shared.openLog("SSHSessionConnect", attributes: ["id": self.id])
        defer {
            SSHLogger.shared.closeLog("SSHSessionConnect", attributes: ["id": self.id])
        }
        self.sessionLock.lock()
        defer {
            self.sessionLock.unlock()
        }
        
        if self.ssh_session == nil {
            try self.createSession();
        }
        
        if (self.connectionState != .AUTHENTICATED || self.connectionState == .CHANNEL_OPEN), ssh_is_connected(self.ssh_session) > 0 {
            return
        }
        
        var connectStarted: DispatchTime = .now();
        
        var rc: Int32 = 0;
        
        var isTimeOut = connectStarted < .now() - 5;
        
        if self.connectionState != .AUTHENTICATED || ssh_is_connected(self.ssh_session) < 1 {
            SSHLogger.shared.openLog("SSHSession:ssh_connect", attributes: ["id": self.id])
            defer {
                SSHLogger.shared.closeLog("SSHSession:ssh_connect", attributes: ["id": self.id])
            }
                        
            try self.exceptionHandler.execute({
                rc = ssh_connect(self.ssh_session)
            });
            
            while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
                try Task.checkCancellation()
                try self.exceptionHandler.execute({
                    rc = ssh_connect(self.ssh_session)
                });
                try await Task.sleep(nanoseconds: 10000);
            }
            
            if rc != SSH_OK {
                if isTimeOut {
                    throw SSHError.SSH_CONNECT_TIMEOUT;
                }
                let errorPointer: UnsafeMutableRawPointer = .init(self.ssh_session!);
                if let errorCChar = ssh_get_error(errorPointer) {
                    let errorString = SSHSession.convertCharPointerToString(pointer: errorCChar);
                    if errorString.contains("unconnected") {
                        throw SSHError.SOCKET_UNCONNECTED
                    }
                    SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["msg": "libssh error", "error": errorString, "id": self.id])
                    throw SSHError.CONNECTION_ERROR(errorString);
                } else {
                    throw SSHError.CONNECTION_ERROR("unknown connection error");
                }
            }
            
            self.connectionState = .CONNECTED;
            
            
            SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["connectionState": ".CONNECTED", "id": self.id])
            
            var ra: Int32 = SSH_ERROR;
            
            try self.exceptionHandler.execute({
                ra = ssh_userauth_password(self.ssh_session, self.options.username, self.options.password);
            });
            
            while (ra == SSH_AUTH_AGAIN.rawValue) {
                try Task.checkCancellation()
                try self.exceptionHandler.execute({
                    ra = ssh_userauth_password(self.ssh_session, self.options.username, self.options.password);
                })
                try await Task.sleep(nanoseconds: 10000);
            }
            
            if ra == SSH_AUTH_SUCCESS.rawValue {
                self.connectionState = .AUTHENTICATED;
                SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["connectionState": ".AUTHENTICATED", "id": self.id])
            } else if ra == SSH_AUTH_DENIED.rawValue {
                throw SSHError.AUTH_DENIED;
            } else if ra == SSH_AUTH_ERROR.rawValue {
                throw SSHError.AUTH_ERROR;
            } else {
                throw SSHError.AUTH_ERROR_OTHER(ssh_auth_e(ra));
            }
        }
        
        guard let channel = ssh_channel_new(self.ssh_session) else {
            throw SSHError.CAN_NOT_OPEN_CHANNEL;
        }
        
        if self.ssh_session == nil || ssh_is_connected(self.ssh_session) < 1 {
            SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["error": "SSH Error for ssh_channel_open_session", "id": self.id])
            rc = SSH_ERROR;
        } else {
            try self.exceptionHandler.execute({
                rc = ssh_channel_open_session(channel);
            });
        }
        
        connectStarted = .now();
        
        while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
            try Task.checkCancellation()
            if self.ssh_session == nil || ssh_is_connected(self.ssh_session) < 1 {
                SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["error": "SSH Error for ssh_channel_open_session", "id": self.id])
                rc = SSH_ERROR;
            } else {
                try self.exceptionHandler.execute({
                    rc = ssh_channel_open_session(channel);
                });
            }
            
            try await Task.sleep(nanoseconds: 10000);
        }
        
        isTimeOut = connectStarted < .now() - 5;
        
        if rc == SSH_OK {
            self.connectionState = .CHANNEL_OPEN;
            SSHLogger.shared.midLog("SSHSession:ssh_connect", attributes: ["connectionState": ".CHANNEL_OPEN", "id": self.id])
            self.ssh_channel = channel;
        } else {
            if self.ssh_session != nil {
                try self.exceptionHandler.execute({
                    ssh_channel_free(channel);
                });
            }
            if isTimeOut {
                throw SSHError.SSH_CHANNEL_TIMEOUT;
            }
            throw SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
        }
                
        self.callbackStruct = ssh_channel_callbacks_struct();
        
        self.userData.taskId = SSHLogger.shared.getTaskId()
        
        self.callbackStruct!.userdata = unsafeBitCast(userData, to: UnsafeMutableRawPointer.self);
                
        self.callbackStruct!.channel_exit_signal_function = { (session, channel, signal, core, errmsg, lang, userdata) in
            guard let userdata = userdata else {
                SSHLogger.shared.midLog("channel_exit_signal_function", attributes: ["error": "No userdata"]);
                return;
            }
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue();
            
            let taskId = localUserData.taskId;
            
            SSHLogger.shared.openLog("channel_exit_signal_function", taskId: taskId);
            defer {
                SSHLogger.shared.closeLog("channel_exit_signal_function", taskId: taskId);
            }
            
            guard let signal = signal else {
                SSHLogger.shared.midLog("channel_exit_signal_function", attributes: ["error": "No signal"], taskId: taskId);
                return;
            }
            
            SSHLogger.shared.midLog("channel_exit_signal_function", attributes: ["msg": "Got with signal", "signal": "\(signal)"], taskId: taskId);
            
            guard let channel_exit_signal_function = localUserData.channel_exit_signal_function else {
                SSHLogger.shared.midLog("channel_exit_signal_function", attributes: ["error": "No channel_exit_signal_function"], taskId: taskId);
                return;
            }
            
            let signalString = SSHSession.convertCharPointerToString(pointer: signal);
            
            var errMsg: String?;
            
            if errmsg != nil {
                errMsg = SSHSession.convertCharPointerToString(pointer: errmsg!);
            }
            
            channel_exit_signal_function(signalString, core > 0, errMsg);
        }
                
        self.callbackStruct!.channel_exit_status_function = { (session, channel, exit_status, userdata) in
            guard let userdata = userdata else {
                SSHLogger.shared.midLog("channel_exit_status_function", attributes: ["error": "No userdata"]);
                return;
            }
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue();
                        
            let taskId = localUserData.taskId;
            
            SSHLogger.shared.openLog("channel_exit_status_function", taskId: taskId);
            defer {
                SSHLogger.shared.closeLog("channel_exit_status_function", taskId: taskId);
            }
            
            let exitStatus = exit_status;
            
            SSHLogger.shared.midLog("channel_exit_status_function", attributes: ["msg": "Got with exitStatus", "exitStatus": "\(exitStatus)"], taskId: taskId);
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue()
                        
            guard let channel_exit_status_function = localUserData.channel_exit_status_function else {
                return;
            }
            
            channel_exit_status_function(exitStatus);
        }
                
        self.callbackStruct!.size = MemoryLayout.size(ofValue: self.callbackStruct!);
        
        let _ = try self.exceptionHandler.execute({
            ssh_set_channel_callbacks(self.ssh_channel, &self.callbackStruct!);
        })
    }
    
    public func disconnect() async throws {
        SSHLogger.shared.openLog("SSHSessionDisconnect", attributes: ["id": self.id])
        defer {
            SSHLogger.shared.closeLog("SSHSessionDisconnect", attributes: ["id": self.id])
        }
        
        let lockBefore = DispatchTime.now() + 5;
        
        let lockResult = self.sessionLock.lock(before: lockBefore.toDate());
        
        defer {
            if lockResult {
                self.sessionLock.unlock();
            }
        }
        
        if !lockResult {
            SSHLogger.shared.midLog("SSHSessionDisconnect", attributes: ["warning": "Warning bypass sessionLock for disconnect", "id": self.id])
        }
        
        if self.ssh_session == nil || self.connectionState == .NOT_CONNECTED {
            return;
        }
        
        if self.connectionState == .CHANNEL_OPEN || self.ssh_channel != nil {
            try self.closeChannel()
            self.connectionState = .AUTHENTICATED;
        }
        
        if ssh_is_connected(self.ssh_session) > 0 {
            SSHLogger.shared.openLog("SSHSessionDisconnect:ssh_disconnect", attributes: ["id": self.id])
            defer {
                SSHLogger.shared.closeLog("SSHSessionDisconnect:ssh_disconnect", attributes: ["id": self.id])
            }
            try self.exceptionHandler.execute({
                ssh_disconnect(self.ssh_session);
            })
        }
                
        try self.exceptionHandler.execute({
            ssh_free(self.ssh_session);
        })
        self.ssh_session = nil;
        self.connectionState = .NOT_CONNECTED;
    }
    
    public func requestExec(command: String) async throws {
        var rc: Int32 = SSH_ERROR;
        
        try await self.runLibsshFunctionAsync { channel in
            return try self.exceptionHandler.execute({
                rc = ssh_channel_request_exec(channel, command)
            });
        };
        
        while (rc == SSH_AGAIN) {
            try await self.runLibsshFunctionAsync { channel in
                return try self.exceptionHandler.execute({
                    rc = ssh_channel_request_exec(channel, command)
                });
            };
            try await Task.sleep(nanoseconds: 10000);
        }
        
        if rc != SSH_OK {
            throw SSHError.REQUEST_EXEC_ERROR(rc);
        }
    }
    
    public func closeChannel() throws {
        if self.callbackStruct != nil, self.ssh_channel != nil {
            var cbs = self.callbackStruct!;
            
            try self.exceptionHandler.execute({
                ssh_remove_channel_callbacks(self.ssh_channel, &cbs);
            })
        }
        if ssh_channel != nil {
            try self.exceptionHandler.execute({
                ssh_channel_send_eof(self.ssh_channel);
                ssh_channel_free(self.ssh_channel);
            })
            self.ssh_channel = nil;
        }
        self.connectionState = .AUTHENTICATED;
    }
    
    public func readNonBlocking(stderr: Bool = false) async throws -> (read: Int32, std: String?) {
        let count = 256
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: count + 1);
        defer {
            buffer.deallocate();
        }
        var read: Int32 = 0;
        let _ = try await self.runLibsshFunction(task: { channel in
            let stdType = Int32(stderr ? 1 : 0);
            let size = UInt32(count * MemoryLayout<CChar>.stride);
            try self.exceptionHandler.execute({
                read = ssh_channel_read_nonblocking(channel, buffer, size, stdType);
            });
        });
        var readString: String?;
        if read > 0 {
            readString = SSHSession.convertCharPointerToString(pointer: buffer, bytesToCopy: Int32(read))
        }
        return (read, readString);
    }
    
    public func setCallbacks(exitStatus: ExitStatusCallback?, exitSignal: ExitSignalCallback?) {
        self.userData.channel_exit_status_function = exitStatus;
        self.userData.channel_exit_signal_function = exitSignal;
    }
    
    /// Teardown all libssh related structures
    public func teardown() throws {
        SSHLogger.shared.openLog("SSHSessionTeardown", attributes: ["id": self.id])
        defer {
            SSHLogger.shared.closeLog("SSHSessionTeardown", attributes: ["id": self.id])
        }
        guard let ssh_session = ssh_session else {
            return
        }
        
        guard let ssh_channel = ssh_channel else {
            try self.exceptionHandler.execute({
                ssh_free(ssh_session);
            })
            return
        }

        if self.callbackStruct != nil {
            var cbs = self.callbackStruct!;
            let _ = try self.exceptionHandler.execute({
                ssh_remove_channel_callbacks(ssh_channel, &cbs);
            })
        }
        try self.exceptionHandler.execute({
            ssh_channel_free(ssh_channel);
        })
        self.ssh_channel = nil;
        try self.exceptionHandler.execute({
            ssh_free(ssh_session);
        })
        self.ssh_session = nil;
    }
    
    private func runLibsshFunction<T>(task: @escaping (_ channel: ssh_channel) throws -> T) async throws -> T {
        self.sessionLock.lock()
        defer {
            self.sessionLock.unlock()
        }
        if self.connectionState != .CHANNEL_OPEN || self.ssh_channel == nil || self.ssh_session == nil {
            throw SSHError.SSH_SESSION_INVALIDATED;
        }
        return try task(self.ssh_channel!);
    }
    
    private func runLibsshFunctionAsync<T>(task: @escaping (_ channel: ssh_channel) async throws -> T) async throws -> T {
        self.sessionLock.lock()
        defer {
            self.sessionLock.unlock()
        }
        if self.connectionState != .CHANNEL_OPEN || self.ssh_channel == nil || self.ssh_session == nil {
            throw SSHError.SSH_SESSION_INVALIDATED;
        }
        return try await task(self.ssh_channel!);
    }
    
    /// Run a task on a separate thread and time out after a specific time
    /// This should help us prevent dead locks when we call libssh functions
    /// - Returns: return value of task
    private func doUnsafeTask<T>(task: @escaping () throws -> T, timeout: DispatchTime = .now() + 5) async throws -> T {
        var returnValue: T?;
        var threadError: Error?;
        let thread = Thread.init {
            do {
                returnValue = try task();
            } catch {
                threadError = error;
            }
        }
        thread.start()
        
        while (!thread.isFinished && !thread.isCancelled) {
            if timeout < .now() {
                thread.cancel()
                throw SSHError.GENERAL_UNSAFE_TASK_TIMEOUT;
            }
            try await Task.sleep(nanoseconds: 10000);
        }
        if threadError != nil {
            throw threadError!;
        }
        return returnValue!;
    }
    
    /// Convert a unsafe pointer returned by a libssh function to a normal string with a specific amount of bytes.
    ///
    /// - parameter pointer: Our pointer used in a libssh function
    /// - parameter bytesToCopy: The amount of bytes to copy
    /// - returns: String copied from the pointer
    static func convertCharPointerToString(pointer: UnsafeMutablePointer<CChar>, bytesToCopy: Int32) -> String {
        pointer[Int(bytesToCopy)] = 0; // Insert zero
        return String(cString: pointer)
    }
    
    static func convertCharPointerToString(pointer: UnsafePointer<CChar>) -> String {
        return String(cString: pointer, encoding: .ascii) ?? "";
    }
    
    deinit {
        try? self.teardown();
    }
}
