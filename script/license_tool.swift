#!/usr/bin/env swift
import Foundation
import CryptoKit

// WalkAway license tool.
// Offline Ed25519-signed license keys — store-agnostic. Generate a keypair
// once, embed the PUBLIC key in the app (LicenseStore.publicKeyBase64), keep
// the PRIVATE key secret and use it to issue keys from your store webhook or
// by hand.
//
//   swift script/license_tool.swift generate-keys
//   swift script/license_tool.swift issue <privateKeyB64> "buyer@example.com"
//   swift script/license_tool.swift verify <publicKeyB64> <licenseKey>

func b64urlEncode(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

func b64urlDecode(_ string: String) -> Data? {
  var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
  while s.count % 4 != 0 { s += "=" }
  return Data(base64Encoded: s)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
  print("usage: license_tool.swift [generate-keys | issue <privB64> <payload> | verify <pubB64> <key>]")
  exit(2)
}

switch args[1] {
case "generate-keys":
  let priv = Curve25519.Signing.PrivateKey()
  print("PRIVATE (keep secret): \(priv.rawRepresentation.base64EncodedString())")
  print("PUBLIC  (embed in app): \(priv.publicKey.rawRepresentation.base64EncodedString())")

case "issue":
  guard args.count == 4, let privData = Data(base64Encoded: args[2]),
        let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
    print("error: issue <privateKeyBase64> <payload>"); exit(2)
  }
  let payload = Data(args[3].utf8)
  let sig = try! priv.signature(for: payload)
  print("\(b64urlEncode(payload)).\(b64urlEncode(sig))")

case "verify":
  guard args.count == 4, let pubData = Data(base64Encoded: args[2]),
        let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
    print("error: verify <publicKeyBase64> <licenseKey>"); exit(2)
  }
  let parts = args[3].split(separator: ".")
  guard parts.count == 2, let payload = b64urlDecode(String(parts[0])),
        let sig = b64urlDecode(String(parts[1])) else {
    print("INVALID (malformed)"); exit(1)
  }
  if pub.isValidSignature(sig, for: payload) {
    print("VALID payload=\(String(data: payload, encoding: .utf8) ?? "?")")
  } else {
    print("INVALID (bad signature)"); exit(1)
  }

default:
  print("unknown command"); exit(2)
}
