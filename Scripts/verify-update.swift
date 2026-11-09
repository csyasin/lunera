import CryptoKit
import Foundation

// Verify against the public key shipped in the app, rather than the CI key.
do {
    guard CommandLine.arguments.count == 4,
          let publicKeyData = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "LuneraUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid signature verification arguments"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "LuneraUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "Update signature does not match the application's public key"])
    }
    print("Update EdDSA signature verified.")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
