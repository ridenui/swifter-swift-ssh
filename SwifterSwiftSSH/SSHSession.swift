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
    
    public var connected: Bool {
        self.connectionState == .CHANNEL_OPEN;
    }
    
    init(options: SSHOption) async throws {
        self.options = options;
        
        try self.createSession();
    }
    
    private func createSession() throws {
        LogSSH("+ createSession() (\(self.id))")
        
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
                
        LogSSH("- createSession() (\(self.id))")
    }
    
    public func connect() async throws {
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
            LogSSH("ssh_connect (\(self.id))");
            
            var rc = ssh_connect(self.ssh_session)
            
            while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
                try Task.checkCancellation()
                rc = ssh_connect(self.ssh_session)
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
                    LogSSH("libssh error string \(errorString)");
                    throw SSHError.CONNECTION_ERROR(errorString);
                } else {
                    throw SSHError.CONNECTION_ERROR("unknown connection error");
                }
            }
            
            self.connectionState = .CONNECTED;
            
            LogSSH("connectionState = .CONNECTED (\(self.id))")
            
            var ra: Int32 = ssh_userauth_password(self.ssh_session, self.options.username, self.options.password);
            
            while (ra == SSH_AUTH_AGAIN.rawValue) {
                try Task.checkCancellation()
                ra = ssh_userauth_password(self.ssh_session, self.options.username, self.options.password);
                try await Task.sleep(nanoseconds: 10000);
            }
            
            if ra == SSH_AUTH_SUCCESS.rawValue {
                self.connectionState = .AUTHENTICATED;
                LogSSH("connectionState = .AUTHENTICATED (\(self.id))")
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
            LogSSH("SSH Error for ssh_channel_open_session")
            rc = SSH_ERROR;
        } else {
            rc = ssh_channel_open_session(channel);
        }
        
        connectStarted = .now();
        
        while (rc == SSH_AGAIN && !(connectStarted < .now() - 5)) {
            try Task.checkCancellation()
            if self.ssh_session == nil || ssh_is_connected(self.ssh_session) < 1 {
                LogSSH("SSH Error for ssh_channel_open_session")
                rc = SSH_ERROR;
            } else {
                rc = ssh_channel_open_session(channel);
            }
            
            try await Task.sleep(nanoseconds: 10000);
        }
        
        isTimeOut = connectStarted < .now() - 5;
        
        if rc == SSH_OK {
            self.connectionState = .CHANNEL_OPEN;
            LogSSH("connectionState = .CHANNEL_OPEN (\(self.id))")
            self.ssh_channel = channel;
        } else {
            if self.ssh_session != nil {
                ssh_channel_free(channel);
            }
            if isTimeOut {
                throw SSHError.SSH_CHANNEL_TIMEOUT;
            }
            throw SSHError.CAN_NOT_OPEN_CHANNEL_SESSION(rc);
        }
        
        self.callbackStruct = ssh_channel_callbacks_struct();
        
        self.callbackStruct!.userdata = unsafeBitCast(userData, to: UnsafeMutableRawPointer.self);
                
        self.callbackStruct!.channel_exit_signal_function = { (session, channel, signal, core, errmsg, lang, userdata) in
            guard let userdata = userdata else {
                LogSSH("channel_exit_signal_function - No userdata");
                return;
            }
            guard let signal = signal else {
                LogSSH("channel_exit_signal_function - No signal");
                return;
            }
            
            LogSSH("channel_exit_signal_function with signal \(signal)");
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue();
            
            guard let channel_exit_signal_function = localUserData.channel_exit_signal_function else {
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
                LogSSH("channel_exit_status_function - No userdata");
                return;
            }
            let exitStatus = exit_status;
            
            LogSSH("channel_exit_status_function with exitStatus \(exitStatus)");
            
            let localUserData = Unmanaged<UserData>.fromOpaque(userdata).takeUnretainedValue()
                        
            guard let channel_exit_status_function = localUserData.channel_exit_status_function else {
                return;
            }
            
            channel_exit_status_function(exitStatus);
        }
                
        self.callbackStruct!.size = MemoryLayout.size(ofValue: self.callbackStruct!);
        
        ssh_set_channel_callbacks(self.ssh_channel, &self.callbackStruct!);
    }
    
    public func disconnect() async throws {
        LogSSH("+(\(self.id)) disconnect")
        
        let lockBefore = DispatchTime.now() + 5;
        
        let lockResult = self.sessionLock.lock(before: lockBefore.toDate());
        
        defer {
            if lockResult {
                self.sessionLock.unlock();
            }
        }
        
        if !lockResult {
            LogSSH("+(\(self.id)) Warning bypass sessionLock for disconnect")
        }
        
        if self.ssh_session == nil || self.connectionState == .NOT_CONNECTED {
            return;
        }
        
        if self.connectionState == .CHANNEL_OPEN || self.ssh_channel != nil {
            self.closeChannel()
            self.connectionState = .AUTHENTICATED;
        }
        
        if ssh_is_connected(self.ssh_session) > 0 {
            LogSSH("ssh_disconnect for (\(self.id))")
            ssh_disconnect(self.ssh_session);
        }
                
        ssh_free(self.ssh_session);
        self.ssh_session = nil;
        self.connectionState = .NOT_CONNECTED;
        LogSSH("-(\(self.id)) disconnect")
    }
    
    public func requestExec(command: String) async throws {
        var rc = try await self.runLibsshFunctionAsync { channel in
            ssh_channel_request_exec(channel, command)
        };
        
        while (rc == SSH_AGAIN) {
            rc = try await self.runLibsshFunctionAsync { channel in
                ssh_channel_request_exec(channel, command)
            };
            try await Task.sleep(nanoseconds: 10000);
        }
        
        if rc != SSH_OK {
            throw SSHError.REQUEST_EXEC_ERROR(rc);
        }
    }
    
    public func closeChannel() {
        if self.callbackStruct != nil, self.ssh_channel != nil {
            var cbs = self.callbackStruct!;
            
            ssh_remove_channel_callbacks(self.ssh_channel, &cbs);
        }
        if ssh_channel != nil {
            ssh_channel_send_eof(self.ssh_channel);
            ssh_channel_free(self.ssh_channel);
            self.ssh_channel = nil;
        }
        self.connectionState = .AUTHENTICATED;
    }
    
    public func readNonBlocking(stderr: Bool = false) async throws -> (read: Int32, std: String?) {
        let count = 65536
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: count);
        let read = try await self.runLibsshFunction(task: { channel -> Int32 in
            let stdType = Int32(stderr ? 1 : 0);
            let size = UInt32(count * MemoryLayout<CChar>.size);
            return ssh_channel_read_nonblocking(channel, buffer, size, stdType);
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
    public func teardown() {
        LogSSH("+(\(self.id)) teardown")
        guard let ssh_session = ssh_session else {
            return
        }
        
        guard let ssh_channel = ssh_channel else {
            ssh_free(ssh_session);
            return
        }

        if self.callbackStruct != nil {
            var cbs = self.callbackStruct!;
            ssh_remove_channel_callbacks(ssh_channel, &cbs);
        }
        ssh_channel_free(ssh_channel);
        self.ssh_channel = nil;
        ssh_free(ssh_session);
        self.ssh_session = nil;
        LogSSH("-(\(self.id)) teardown")
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
                LogSSH("doUnsafeTask timed out")
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
        var charDataArray: [UInt8] = [];
        for i in 0..<Int(bytesToCopy) {
            charDataArray.append((pointer + i).pointee.magnitude);
        }
        let data = Data(charDataArray);
        
        return String(data: data, encoding: .utf8) ?? "";
    }
    
    static func convertCharPointerToString(pointer: UnsafePointer<CChar>) -> String {
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
    
    deinit {
        self.teardown();
    }
}
