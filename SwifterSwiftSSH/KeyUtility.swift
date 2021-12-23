//
//  KeyUtility.swift
//  SwifterSwiftSSH
//
//  Created by Nils Bergmann on 22.12.21.
//

import Foundation

/// This code is based of: https://stackoverflow.com/questions/45914097/how-to-generate-public-private-key-pair-with-like-below-in-ios-swift/45916908#45916908

enum KeyError: Error {
    case FAILED_TO_GENERATE_SEC_KEY_PAIR
    case FAILED_TO_GENERATE_EXTERNAL_REP_PRIVATE_KEY(Error)
    case FAILED_TO_GENERATE_EXTERNAL_REP_PUBLIC_KEY(Error)
}

/// Generate a RSA public and private key
public func generateRSAKeyPair() throws -> (privateKey: String, publicKey: String) {
    let publicKeyTag: String = "io.noim.riden.ssh-key.public"
    let privateKeyTag: String = "io.noim.riden.ssh-key.private"
    guard let keyPair = generateKeyPair(publicKeyTag, privateTag: privateKeyTag, keySize: 2048) else {
        throw KeyError.FAILED_TO_GENERATE_SEC_KEY_PAIR;
    }
    var pbError:Unmanaged<CFError>?
    var prError:Unmanaged<CFError>?
    guard let pbData = SecKeyCopyExternalRepresentation(keyPair.publicKey, &pbError) as Data? else {
        throw KeyError.FAILED_TO_GENERATE_EXTERNAL_REP_PRIVATE_KEY(pbError!.takeRetainedValue() as Error);
    }
    guard let prData = SecKeyCopyExternalRepresentation(keyPair.privateKey, &prError) as Data? else {
        throw KeyError.FAILED_TO_GENERATE_EXTERNAL_REP_PUBLIC_KEY(prError!.takeRetainedValue() as Error);
    }
    let strPublicKey = appendPrefixSuffixTo(pbData.base64EncodedString(options: .lineLength64Characters), prefix: "-----BEGIN RSA PUBLIC KEY-----\n", suffix: "\n-----END RSA PUBLIC KEY-----")

    let strPrivateKey = appendPrefixSuffixTo(prData.base64EncodedString(options: .lineLength64Characters), prefix: "-----BEGIN RSA PRIVATE KEY-----\n", suffix: "\n-----END RSA PRIVATE KEY-----")
    
    return (privateKey: strPrivateKey, publicKey: strPublicKey);
}

typealias KeyPair = (publicKey: SecKey, privateKey: SecKey);

func generateKeyPair(_ publicTag: String, privateTag: String, keySize: Int) -> KeyPair? {
    var sanityCheck: OSStatus = noErr
    var publicKey: SecKey?
    var privateKey: SecKey?
    // Container dictionaries
    var privateKeyAttr = [AnyHashable : Any]()
    var publicKeyAttr = [AnyHashable: Any]()
    var keyPairAttr = [AnyHashable : Any]()
    // Set top level dictionary for the keypair
    keyPairAttr[(kSecAttrKeyType ) as AnyHashable] = (kSecAttrKeyTypeRSA as Any)
    keyPairAttr[(kSecAttrKeySizeInBits as AnyHashable)] = Int(keySize)
    // Set private key dictionary
    privateKeyAttr[(kSecAttrIsPermanent as AnyHashable)] = Int(truncating: true)
    privateKeyAttr[(kSecAttrApplicationTag as AnyHashable)] = privateTag
    // Set public key dictionary.
    publicKeyAttr[(kSecAttrIsPermanent as AnyHashable)] = Int(truncating: true)
    publicKeyAttr[(kSecAttrApplicationTag as AnyHashable)] = publicTag

    keyPairAttr[(kSecPrivateKeyAttrs as AnyHashable)] = privateKeyAttr
    keyPairAttr[(kSecPublicKeyAttrs as AnyHashable)] = publicKeyAttr
    sanityCheck = SecKeyGeneratePair((keyPairAttr as CFDictionary), &publicKey, &privateKey)
    if sanityCheck == noErr && publicKey != nil && privateKey != nil {
        return KeyPair(publicKey: publicKey!, privateKey: privateKey!)
    }
    return nil
}

func appendPrefixSuffixTo(_ string: String, prefix: String, suffix: String) -> String {
    return "\(prefix)\(string)\(suffix)"
}
