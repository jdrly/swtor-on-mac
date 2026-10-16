// Checks an appcast against the files it points to and the app's public EdDSA key, the way
// Sparkle will: every enclosure (full update and deltas) must name a file in <dir> with that
// length and a valid sparkle:edSignature for SUPublicEDKey. Used by scripts/release.sh.
//
//   swift scripts/check-appcast.swift <appcast.xml> <dir> <SUPublicEDKey>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write("usage: check-appcast.swift <appcast.xml> <dir> <SUPublicEDKey>\n".data(using: .utf8)!)
    exit(2)
}
let dir = URL(fileURLWithPath: args[2], isDirectory: true)
guard let keyData = Data(base64Encoded: args[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    print("check-appcast: SUPublicEDKey is not a valid Ed25519 public key")
    exit(1)
}
let doc = try XMLDocument(contentsOf: URL(fileURLWithPath: args[1]), options: [])
let enclosures = try doc.nodes(forXPath: "//enclosure").compactMap { $0 as? XMLElement }
var failures = 0
for enclosure in enclosures {
    func attribute(_ name: String) -> String? {
        enclosure.attributes?.first { $0.name == name || $0.localName == name }?.stringValue
    }
    guard let url = attribute("url").flatMap(URL.init(string:)),
          let length = attribute("length").flatMap(Int.init),
          let signature = attribute("sparkle:edSignature").flatMap({ Data(base64Encoded: $0) }) else {
        print("FAIL  enclosure without url, length or sparkle:edSignature: \(enclosure.xmlString)")
        failures += 1
        continue
    }
    let name = url.lastPathComponent
    guard let data = try? Data(contentsOf: dir.appendingPathComponent(name), options: .mappedIfSafe) else {
        print("FAIL  \(name): not in \(dir.path)")
        failures += 1
        continue
    }
    if data.count != length {
        print("FAIL  \(name): \(data.count) bytes, the appcast says \(length)")
        failures += 1
    } else if !key.isValidSignature(signature, for: data) {
        print("FAIL  \(name): sparkle:edSignature does not verify with SUPublicEDKey")
        failures += 1
    } else {
        print("ok    \(name) (\(length) bytes, signature valid) <- \(url.absoluteString)")
    }
}
if enclosures.isEmpty {
    print("FAIL  no enclosures in the appcast")
    failures += 1
}
exit(failures == 0 ? 0 : 1)
