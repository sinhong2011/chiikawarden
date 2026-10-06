import Foundation

public enum CryptoError: Error, Equatable, Sendable {
    case kdfOutOfBounds(String)
    case unsupported(String)
    case malformedEncString
    case unsupportedEncType(Int)
    case macMismatch
    case invalidKeyLength(Int)
    case commonCrypto(Int32)
}
