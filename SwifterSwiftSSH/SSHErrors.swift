//
//  SSHErrors.swift
//  swifter-swift-ssh
//
//  Created by Nils Bergmann on 18/12/2021.
//

import Foundation

public enum SSHError: Error {
    case CAN_NOT_OPEN_SESSION
    case CAN_NOT_OPEN_CHANNEL
    case CAN_NOT_OPEN_CHANNEL_SESSION(Int32)
    case CONNECTION_ERROR(String)
    case AUTH_DENIED
    case AUTH_ERROR
    case AUTH_ERROR_OTHER(ssh_auth_e)
    case REQUEST_EXEC_ERROR(Int32)
    /// General ssh error
    case SSH_ERROR
    case SSH_IO_ERROR
    case SSH_CONNECT_TIMEOUT
    case SSH_CHANNEL_TIMEOUT
    
    case GENERAL_UNSAFE_TASK_TIMEOUT
    
    public var errorDescription: String? {
        switch self {
        case .CAN_NOT_OPEN_SESSION:
            return "Can not open session"
        case .CAN_NOT_OPEN_CHANNEL:
            return "Can not open channel"
        case .CAN_NOT_OPEN_CHANNEL_SESSION(_):
            return "Can not open channel session"
        case .CONNECTION_ERROR(msg: let msg):
            return "Connection error: \(msg)"
        case .AUTH_DENIED:
            return "Auth denied"
        case .AUTH_ERROR:
            return "Auth error"
        case .AUTH_ERROR_OTHER(_):
            return "Unknown auth error"
        case .REQUEST_EXEC_ERROR(_):
            return "REQUEST_EXEC_ERROR"
        case .SSH_ERROR:
            return "General SSH Error"
        case .SSH_IO_ERROR:
            return "SSH io error"
        case .SSH_CONNECT_TIMEOUT:
            return "SSH connect timedout"
        case .SSH_CHANNEL_TIMEOUT:
            return "Open SSH channel timedout"
        case .GENERAL_UNSAFE_TASK_TIMEOUT:
            return "General task timeout. This can happen when a call to libssh never returns. This error helps us to prevent a dead lock on the main thread"
        }
    }
}
