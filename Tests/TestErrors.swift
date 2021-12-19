//
//  TestErrors.swift
//  Tests
//
//  Created by Nils Bergmann on 19/12/2021.
//

import Foundation

enum TestErrors: Error {
    case MISSING_CREDENTIALS
    case INVALID_CREDENTIALS_PLIST
    case MISSING_HOST
    case MISSING_USERNAME
    case MISSING_PASSWORD
    case CONFIG_IS_NIL
}
