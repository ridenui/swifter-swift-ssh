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
}
