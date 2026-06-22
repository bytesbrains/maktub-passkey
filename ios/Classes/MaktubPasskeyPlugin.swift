import Flutter
import UIKit

// maktub_passkey — iOS plugin.
//
// SCAFFOLD (fail-closed). The real implementation (#301) uses
// AuthenticationServices:
//   - create:        ASAuthorizationPlatformPublicKeyCredentialProvider
//                    .createCredentialRegistrationRequest(...) with
//                    ASAuthorizationPublicKeyCredentialPRFRegistrationInputs
//                    so the credential is created with hmac-secret enabled.
//   - assertWithPrf: ...createCredentialAssertionRequest(...) with
//                    ASAuthorizationPublicKeyCredentialPRFAssertionInputs(
//                      inputValues: .init(saltInput1: prfSalt))
//                    → result.prf.first (32 bytes). iOS 18+.
//   - capability:    report PRF support + the BE/BS backup flags so the app's
//                    fail-closed gate can refuse device-bound credentials.
//
// Until that lands AND a real-device cross-device QA run passes, every method
// reports PRF unavailable / not-implemented so the app keeps passkey accounts
// gated off (no false "recoverable" claim). See maktub#304 (spec) and #301.
public class MaktubPasskeyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "it.maktub.passkey",
      binaryMessenger: registrar.messenger())
    let instance = MaktubPasskeyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probePrf":
      // Fail closed: PRF reported unavailable until #301 wires AuthenticationServices.
      result([
        "prfSupported": false,
        "backupEligible": false,
        "backupState": false,
      ])
    case "create", "assertWithPrf":
      result(FlutterError(
        code: "not-implemented",
        message: "maktub_passkey iOS PRF not implemented yet (#301)",
        details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
