package it.maktub.passkey

import android.app.Activity
import android.os.Build
import android.util.Base64
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONObject

// maktub_passkey — Android plugin.
//
// Passkey (WebAuthn / P-256) create + assert plus the WebAuthn PRF
// (`hmac-secret`) extension via androidx.credentials (Credential Manager):
//   - create:        CreatePublicKeyCredentialRequest with the `prf` extension
//                    in the request JSON (enables hmac-secret).
//   - assertWithPrf: GetPublicKeyCredentialOption with `prf.eval.first = salt`
//                    → clientExtensionResults.prf.results.first (32 bytes).
//   - probePrf:      report PRF support + BE/BS so the app's fail-closed gate
//                    can refuse device-bound credentials.
//
// PRF requires a recent Credential Manager / authenticator; where it is absent
// the assert simply yields no prf result and the gate fails closed, so passkey
// accounts stay gated off. Real-device cross-device QA stays the GA blocker
// (#306 §10 / #307 C3). See maktub#304 (spec) and #301.
class MaktubPasskeyPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private var activity: Activity? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "it.maktub.passkey")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "probePrf" -> {
        // PRF rides on Credential Manager passkeys (API 28+ with Play
        // Services). Whether a given authenticator actually enables hmac-secret
        // — and whether the credential is BE/BS — is only knowable from a real
        // create/assert result, which the gate confirms. Report support by API
        // level and leave BE/BS false so a missing flag never reads recoverable.
        result.success(
          mapOf(
            "prfSupported" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P),
            "backupEligible" to false,
            "backupState" to false,
          )
        )
      }
      "create" -> handleCreate(call, result)
      "assertWithPrf" -> handleAssert(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleCreate(call: MethodCall, result: Result) {
    val act = activity ?: return result.error(
      "no-activity", "no foreground activity for the passkey ceremony", null)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
      return result.error(
        "prf-unsupported", "passkeys require Android 9 (API 28) or later", null)
    }
    val rpId = call.argument<String>("rpId")
    val rpName = call.argument<String>("rpName")
    val userName = call.argument<String>("userName")
    val userId = call.argument<ByteArray>("userId")
    val challenge = call.argument<ByteArray>("challenge")
    if (rpId == null || rpName == null || userName == null ||
      userId == null || challenge == null
    ) {
      return result.error("bad-args", "missing or malformed arguments", null)
    }

    val requestJson = JSONObject().apply {
      put("challenge", b64url(challenge))
      put("rp", JSONObject().put("id", rpId).put("name", rpName))
      put("user", JSONObject()
        .put("id", b64url(userId))
        .put("name", userName)
        .put("displayName", userName))
      put("pubKeyCredParams", org.json.JSONArray().put(
        JSONObject().put("type", "public-key").put("alg", -7))) // ES256
      put("authenticatorSelection", JSONObject()
        .put("residentKey", "required")
        .put("requireResidentKey", true)
        .put("userVerification", "required"))
      put("attestation", "none")
      // Enable hmac-secret AT CREATION — PRF cannot be retrofitted later.
      put("extensions", JSONObject().put("prf", JSONObject()))
    }.toString()

    val cm = CredentialManager.create(act)
    cm.createCredentialAsync(
      act,
      CreatePublicKeyCredentialRequest(requestJson),
      null,
      act.mainExecutor,
      // createCredentialAsync's callback is typed on the BASE CreateCredentialResponse;
      // narrow to the public-key response inside onResult.
      object : CredentialManagerCallback<CreateCredentialResponse, CreateCredentialException> {
        override fun onResult(res: CreateCredentialResponse) {
          val pk = res as? CreatePublicKeyCredentialResponse
            ?: return result.error(
              "unexpected-credential", "not a public-key credential response", null)
          try {
            result.success(parseRegistration(pk.registrationResponseJson))
          } catch (e: Exception) {
            result.error("parse-error", e.message, null)
          }
        }

        override fun onError(e: CreateCredentialException) {
          val code = if (e is CreateCredentialCancellationException)
            "user-cancelled" else "create-error"
          result.error(code, e.message, null)
        }
      },
    )
  }

  private fun handleAssert(call: MethodCall, result: Result) {
    val act = activity ?: return result.error(
      "no-activity", "no foreground activity for the passkey ceremony", null)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
      return result.error(
        "prf-unsupported", "passkeys require Android 9 (API 28) or later", null)
    }
    val rpId = call.argument<String>("rpId")
    val challenge = call.argument<ByteArray>("challenge")
    val prfSalt = call.argument<ByteArray>("prfSalt")
    val credentialId = call.argument<String>("credentialId")
    if (rpId == null || challenge == null || prfSalt == null) {
      return result.error("bad-args", "missing or malformed arguments", null)
    }

    val requestJson = JSONObject().apply {
      put("challenge", b64url(challenge))
      put("rpId", rpId)
      put("userVerification", "required")
      if (credentialId != null) {
        put("allowCredentials", org.json.JSONArray().put(
          JSONObject()
            .put("type", "public-key")
            .put("id", credentialId)))
      }
      // Evaluate PRF with the fixed salt as eval.first.
      put("extensions", JSONObject().put("prf",
        JSONObject().put("eval", JSONObject().put("first", b64url(prfSalt)))))
    }.toString()

    val cm = CredentialManager.create(act)
    cm.getCredentialAsync(
      act,
      GetCredentialRequest(listOf(GetPublicKeyCredentialOption(requestJson))),
      null,
      act.mainExecutor,
      object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
        override fun onResult(res: GetCredentialResponse) {
          try {
            val cred = res.credential
            if (cred !is PublicKeyCredential) {
              return result.error(
                "unexpected-credential", "not a public-key credential", null)
            }
            result.success(parseAssertion(cred.authenticationResponseJson))
          } catch (e: Exception) {
            result.error("parse-error", e.message, null)
          }
        }

        override fun onError(e: GetCredentialException) {
          val code = if (e is GetCredentialCancellationException)
            "user-cancelled" else "get-error"
          result.error(code, e.message, null)
        }
      },
    )
  }

  // ── response JSON parsing ──────────────────────────────────────────────────

  private fun parseRegistration(json: String): Map<String, Any?> {
    val root = JSONObject(json)
    val ext = root.optJSONObject("clientExtensionResults")
    val prf = ext?.optJSONObject("prf")
    // `prf.enabled == true` ⇒ hmac-secret was switched on for this credential.
    val prfSupported = prf?.optBoolean("enabled", false) ?: false
    val attObj = root.optJSONObject("response")?.optString("attestationObject")
    return mapOf(
      "credentialId" to root.optString("id"),
      "attestationObject" to (attObj?.let { b64urlDecode(it) } ?: ByteArray(0)),
      "prfSupported" to prfSupported,
      // BE/BS confirmed from the enrollment-proof assertion, not here.
      "backupEligible" to false,
      "backupState" to false,
    )
  }

  private fun parseAssertion(json: String): Map<String, Any?> {
    val root = JSONObject(json)
    val response = root.optJSONObject("response")
    val authData = response?.optString("authenticatorData")
      ?.let { b64urlDecode(it) } ?: ByteArray(0)
    val signature = response?.optString("signature")
      ?.let { b64urlDecode(it) } ?: ByteArray(0)
    val clientData = response?.optString("clientDataJSON")
      ?.let { b64urlDecode(it) } ?: ByteArray(0)

    val ext = root.optJSONObject("clientExtensionResults")
    val prfResults = ext?.optJSONObject("prf")?.optJSONObject("results")
    val prfFirst = prfResults?.optString("first", null)
      ?.let { b64urlDecode(it) }

    val (be, bs) = backupFlags(authData)
    val out = hashMapOf<String, Any?>(
      "signature" to signature,
      "authenticatorData" to authData,
      "clientDataJson" to clientData,
      "backupEligible" to be,
      "backupState" to bs,
    )
    // The credential the user actually picked — required so a discoverable
    // assertion (no allowCredentials) can bind later PRF recovery to it (#2).
    // `id` is the base64url rawId; `response.userHandle` may be absent.
    root.optString("id", null)?.takeIf { it.isNotEmpty() }
      ?.let { out["credentialId"] = it }
    response?.optString("userHandle", null)?.takeIf { it.isNotEmpty() }
      ?.let { out["userHandle"] = it }
    if (prfFirst != null && prfFirst.isNotEmpty()) out["prfOutput"] = prfFirst
    return out
  }

  // WebAuthn authenticator-data flags byte at offset 32 (after the 32-byte
  // rpIdHash): bit 3 (0x08) = BE, bit 4 (0x10) = BS. Both true ⇒ the credential
  // survives a device change, which is what makes a derived reading key
  // recoverable on a new phone.
  private fun backupFlags(authData: ByteArray): Pair<Boolean, Boolean> {
    if (authData.size <= 32) return false to false
    val flags = authData[32].toInt()
    return ((flags and 0x08) != 0) to ((flags and 0x10) != 0)
  }

  private fun b64url(bytes: ByteArray): String =
    Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

  private fun b64urlDecode(s: String): ByteArray =
    Base64.decode(s, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
}
