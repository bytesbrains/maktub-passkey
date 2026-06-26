import AuthenticationServices
import CryptoKit
import Flutter
import UIKit

// maktub_passkey — iOS plugin.
//
// Passkey (WebAuthn / P-256) create + assert plus the WebAuthn PRF
// (`hmac-secret`) extension, via AuthenticationServices:
//   - create:        ASAuthorizationPlatformPublicKeyCredentialProvider
//                    .createCredentialRegistrationRequest(...) with
//                    ASAuthorizationPublicKeyCredentialPRFRegistrationInputs
//                    so the credential is created with hmac-secret enabled.
//   - assertWithPrf: ...createCredentialAssertionRequest(...) with
//                    ASAuthorizationPublicKeyCredentialPRFAssertionInputs(
//                      inputValues: .init(saltInput1: prfSalt))
//                    → result.prf.first (32 bytes). iOS 18+.
//   - probePrf:      report PRF support + the BE/BS backup flags so the app's
//                    fail-closed gate can refuse device-bound credentials.
//
// PRF is iOS 18+. On older OSes (or the simulator, where platform passkeys are
// unavailable) probePrf reports unavailable and create/assert fail closed, so
// the app keeps passkey accounts gated off. Real-device cross-device QA stays
// the GA blocker (#306 §10 / #307 C3). See maktub#304 (spec) and #301.
public class MaktubPasskeyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "it.maktub.passkey",
      binaryMessenger: registrar.messenger())
    let instance = MaktubPasskeyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  // Holds the in-flight ceremony's delegate so ARC doesn't release it before
  // the authorization controller calls back. One ceremony at a time. Typed as
  // NSObject (not PasskeyFlow) because PasskeyFlow is iOS 18+ only and this
  // class compiles back to the app's iOS 13 deployment target — a stored
  // property of an availability-restricted type at class scope is illegal.
  private var activeFlow: NSObject?

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probePrf":
      // Capability is a static platform fact: PRF requires iOS 18+. The BE/BS
      // backup flags are credential-specific and only knowable from a real
      // create/assert result, so probe reports prfSupported only and leaves the
      // gate to confirm BE=1/BS=1 from the create result.
      if #available(iOS 18.0, *) {
        result([
          "prfSupported": true,
          "backupEligible": false,
          "backupState": false,
        ])
      } else {
        result([
          "prfSupported": false,
          "backupEligible": false,
          "backupState": false,
        ])
      }

    case "create":
      guard #available(iOS 18.0, *) else {
        result(prfUnsupportedError()); return
      }
      guard
        let args = call.arguments as? [String: Any],
        let rpId = args["rpId"] as? String,
        let userName = args["userName"] as? String,
        let userId = (args["userId"] as? FlutterStandardTypedData)?.data,
        let challenge = (args["challenge"] as? FlutterStandardTypedData)?.data
      else {
        result(argError()); return
      }
      runCreate(
        rpId: rpId, userName: userName, userId: userId,
        challenge: challenge, result: result)

    case "assertWithPrf":
      guard #available(iOS 18.0, *) else {
        result(prfUnsupportedError()); return
      }
      guard
        let args = call.arguments as? [String: Any],
        let rpId = args["rpId"] as? String,
        let challenge = (args["challenge"] as? FlutterStandardTypedData)?.data,
        let prfSalt = (args["prfSalt"] as? FlutterStandardTypedData)?.data
      else {
        result(argError()); return
      }
      let credentialId = args["credentialId"] as? String
      runAssert(
        rpId: rpId, challenge: challenge, prfSalt: prfSalt,
        credentialId: credentialId, result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Ceremonies

  @available(iOS 18.0, *)
  private func runCreate(
    rpId: String, userName: String, userId: Data, challenge: Data,
    result: @escaping FlutterResult
  ) {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: rpId)
    let request = provider.createCredentialRegistrationRequest(
      challenge: challenge, name: userName, userID: userId)
    // Enable hmac-secret AT CREATION — PRF can never be retrofitted onto a
    // credential made without it, so this must happen here.
    request.prf = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.checkForSupport
    start(request: request, result: result)
  }

  @available(iOS 18.0, *)
  private func runAssert(
    rpId: String, challenge: Data, prfSalt: Data, credentialId: String?,
    result: @escaping FlutterResult
  ) {
    let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier: rpId)
    let request = provider.createCredentialAssertionRequest(challenge: challenge)
    if let credentialId, let raw = Data(base64URLEncoded: credentialId) {
      request.allowedCredentials = [
        ASAuthorizationPlatformPublicKeyCredentialDescriptor(
          credentialID: raw)
      ]
    }
    // The Swift-refined PRF assertion input is a struct built via its
    // `inputValues(_:perCredentialInputValues:)` factory, not an initializer.
    let prfInputValues = ASAuthorizationPublicKeyCredentialPRFAssertionInput
      .InputValues(saltInput1: prfSalt, saltInput2: nil)
    request.prf = .inputValues(prfInputValues, perCredentialInputValues: nil)
    start(request: request, result: result)
  }

  @available(iOS 18.0, *)
  private func start(
    request: ASAuthorizationRequest, result: @escaping FlutterResult
  ) {
    let controller = ASAuthorizationController(authorizationRequests: [request])
    let flow = PasskeyFlow(result: result) { [weak self] in
      self?.activeFlow = nil  // release after the ceremony settles
    }
    activeFlow = flow
    controller.delegate = flow
    controller.presentationContextProvider = flow
    controller.performRequests()
  }

  // MARK: - Errors

  private func prfUnsupportedError() -> FlutterError {
    FlutterError(
      code: "prf-unsupported",
      message: "WebAuthn PRF requires iOS 18 or later.",
      details: nil)
  }

  private func argError() -> FlutterError {
    FlutterError(code: "bad-args", message: "missing or malformed arguments",
      details: nil)
  }
}

// MARK: - ASAuthorizationController delegate

@available(iOS 18.0, *)
private final class PasskeyFlow: NSObject,
  ASAuthorizationControllerDelegate,
  ASAuthorizationControllerPresentationContextProviding
{
  private let result: FlutterResult
  private let onDone: () -> Void

  init(result: @escaping FlutterResult, onDone: @escaping () -> Void) {
    self.result = result
    self.onDone = onDone
  }

  func presentationAnchor(for controller: ASAuthorizationController)
    -> ASPresentationAnchor
  {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first ?? ASPresentationAnchor()
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    defer { onDone() }
    switch authorization.credential {
    case let reg as ASAuthorizationPlatformPublicKeyCredentialRegistration:
      handleRegistration(reg)
    case let asn as ASAuthorizationPlatformPublicKeyCredentialAssertion:
      handleAssertion(asn)
    default:
      result(FlutterError(
        code: "unexpected-credential",
        message: "unrecognized credential type", details: nil))
    }
  }

  func authorizationController(
    controller: ASAuthorizationController, didCompleteWithError error: Error
  ) {
    defer { onDone() }
    let code: String
    if let authErr = error as? ASAuthorizationError {
      code = authErr.code == .canceled ? "user-cancelled" : "auth-error"
    } else {
      code = "auth-error"
    }
    result(FlutterError(
      code: code, message: error.localizedDescription, details: nil))
  }

  private func handleRegistration(
    _ reg: ASAuthorizationPlatformPublicKeyCredentialRegistration
  ) {
    // PRF support is reported by the registration's prf result being present
    // and enabled. Whether it is *actually* recoverable also needs BE/BS, read
    // from the assertion at enrollment-proof time; at creation we surface the
    // enabled flag so the app can short-circuit a no-PRF authenticator.
    var prfSupported = false
    if let prf = reg.prf {
      prfSupported = prf.isSupported
    }
    result([
      "credentialId": reg.credentialID.base64URLEncodedString(),
      "attestationObject": FlutterStandardTypedData(
        bytes: reg.rawAttestationObject ?? Data()),
      "prfSupported": prfSupported,
      // BE/BS are not exposed on the registration object; the gate confirms
      // them from the subsequent enrollment-proof assertion. Report false here
      // so a missing flag never reads as recoverable.
      "backupEligible": false,
      "backupState": false,
    ])
  }

  private func handleAssertion(
    _ asn: ASAuthorizationPlatformPublicKeyCredentialAssertion
  ) {
    var prfOutput: Data?
    if let prf = asn.prf {
      // The 32-byte hmac-secret output for saltInput1 is a CryptoKit
      // SymmetricKey in the Swift-refined API; copy its raw bytes out.
      prfOutput = prf.first.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
    }
    // On the concrete assertion class signature/rawAuthenticatorData are
    // optional (rawClientDataJSON is not); default the optionals to empty.
    let authData = asn.rawAuthenticatorData ?? Data()
    let (be, bs) = backupFlags(fromAuthenticatorData: authData)
    var payload: [String: Any] = [
      "signature": FlutterStandardTypedData(bytes: asn.signature ?? Data()),
      "authenticatorData": FlutterStandardTypedData(bytes: authData),
      "clientDataJson": FlutterStandardTypedData(bytes: asn.rawClientDataJSON),
      // The credential the user actually picked — required so a discoverable
      // assertion (no allowedCredentials) can bind later PRF recovery to it (#2).
      "credentialId": asn.credentialID.base64URLEncodedString(),
      "userHandle": asn.userID.base64URLEncodedString(),
      "backupEligible": be,
      "backupState": bs,
    ]
    if let prfOutput {
      payload["prfOutput"] = FlutterStandardTypedData(bytes: prfOutput)
    }
    result(payload)
  }

  // The WebAuthn authenticator-data flags byte (offset 32, after the 32-byte
  // rpIdHash): bit 3 (0x08) = BE (backup eligible), bit 4 (0x10) = BS (backup
  // state / currently synced). Both true ⇒ the credential survives a device
  // change, which is what makes a derived reading key recoverable.
  private func backupFlags(fromAuthenticatorData data: Data) -> (Bool, Bool) {
    guard data.count > 32 else { return (false, false) }
    let flags = data[data.startIndex + 32]
    return ((flags & 0x08) != 0, (flags & 0x10) != 0)
  }
}

// MARK: - base64url helpers

private extension Data {
  init?(base64URLEncoded s: String) {
    var b64 = s.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while b64.count % 4 != 0 { b64.append("=") }
    guard let d = Data(base64Encoded: b64) else { return nil }
    self = d
  }

  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
