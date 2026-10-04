import Foundation
import CryptoKit

func verify(_ archive: Data, signature: Data, publicKey: Data) throws -> Bool {
    try Curve25519.Signing.PublicKey(rawRepresentation: publicKey).isValidSignature(signature, for: archive)
}

if CommandLine.arguments.dropFirst().first == "--self-test" {
    let key = Curve25519.Signing.PrivateKey()
    let data = Data("ephemeral verification fixture".utf8)
    let signature = try key.signature(for: data)
    guard try verify(data, signature: signature, publicKey: key.publicKey.rawRepresentation),
          try !verify(data + Data([0]), signature: signature, publicKey: key.publicKey.rawRepresentation),
          try !verify(data, signature: signature, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation) else {
        fatalError("Signature verification regression")
    }
    print("Valid, tampered, and mismatched-key signature checks passed")
} else {
    guard CommandLine.arguments.count == 4 else { fatalError("Usage: verify-update-signature.swift APPCAST APP DMG") }
    let xml = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let info = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("Contents/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any]
    guard let key = plist?["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: key),
          let enclosure = try xml.nodes(forXPath: "/rss/channel/item/enclosure").first as? XMLElement,
          let encoded = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let signature = Data(base64Encoded: encoded) else { fatalError("Missing embedded public key or feed signature") }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
    guard try verify(data, signature: signature, publicKey: keyData) else { fatalError("Update signature does not match the shipped public key and exact DMG") }
    print("DMG signature verified against the app's embedded public key")
}
