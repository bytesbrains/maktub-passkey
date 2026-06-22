package it.maktub.passkey

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

// maktub_passkey — Android plugin.
//
// SCAFFOLD (fail-closed). The real implementation (#301) uses
// androidx.credentials (Credential Manager):
//   - create:        CreatePublicKeyCredentialRequest with the `prf` extension
//                    in the request JSON (enables hmac-secret).
//   - assertWithPrf: GetCredentialRequest / GetPublicKeyCredentialOption with
//                    `prf.eval.first = prfSalt` → clientExtensionResults.prf
//                    .results.first (32 bytes).
//   - capability:    report PRF support + the BE/BS backup flags so the app's
//                    fail-closed gate can refuse device-bound credentials.
//
// Until that lands AND a real-device cross-device QA run passes, every method
// reports PRF unavailable / not-implemented so the app keeps passkey accounts
// gated off (no false "recoverable" claim). See maktub#304 (spec) and #301.
class MaktubPasskeyPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "it.maktub.passkey")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "probePrf" -> result.success(
        mapOf(
          "prfSupported" to false,
          "backupEligible" to false,
          "backupState" to false,
        )
      )
      "create", "assertWithPrf" -> result.error(
        "not-implemented",
        "maktub_passkey Android PRF not implemented yet (#301)",
        null,
      )
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
