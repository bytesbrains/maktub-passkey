import 'dart:typed_data';

/// Whether the active passkey can back a *recoverable* reading key (#301).
///
/// A `smartWallet` reading key is recoverable only when the authenticator
/// supports the WebAuthn PRF (`hmac-secret`) extension AND the credential is
/// backup-eligible (synced). Anything less is device-local — treat as no PRF.
class PrfCapability {
  const PrfCapability({
    required this.prfSupported,
    required this.backupEligible,
    required this.backupState,
  });

  /// Authenticator reports the PRF / hmac-secret extension is available.
  final bool prfSupported;

  /// `BE` flag — the credential is *eligible* to sync off this device.
  final bool backupEligible;

  /// `BS` flag — the credential is *currently* backed up (synced).
  final bool backupState;

  /// The only state in which deriving a reading key now will reproduce on a new
  /// device: PRF available, credential backup-eligible AND backed up.
  bool get recoverable => prfSupported && backupEligible && backupState;

  /// A device-local credential (no sync) — PRF may "work" here but the key
  /// would be stranded on a new device, so it must be treated as unrecoverable.
  bool get deviceBound => !backupEligible;

  const PrfCapability.unavailable()
      : prfSupported = false,
        backupEligible = false,
        backupState = false;
}

/// A freshly created passkey credential, with whether PRF was enabled on it.
class PasskeyCreation {
  const PasskeyCreation({
    required this.credentialId,
    required this.publicKeyDer,
    required this.capability,
  });

  /// Base64url credential id.
  final String credentialId;

  /// The credential's COSE/DER P-256 public key (for the smart-wallet verifier).
  final Uint8List publicKeyDer;

  /// PRF / backup capability observed at creation (the fail-closed gate input).
  final PrfCapability capability;
}

/// An assertion plus, when requested, the 32-byte PRF output evaluated with the
/// caller's salt. [prfOutput] is null when PRF was not available.
class PasskeyAssertion {
  const PasskeyAssertion({
    required this.signature,
    required this.authenticatorData,
    required this.clientDataJson,
    required this.prfOutput,
  });

  final Uint8List signature;
  final Uint8List authenticatorData;
  final Uint8List clientDataJson;

  /// 32-byte WebAuthn PRF (`hmac-secret`) output, or null if unavailable.
  final Uint8List? prfOutput;
}

/// Raised when the platform passkey/PRF operation fails or is unsupported.
class MaktubPasskeyException implements Exception {
  const MaktubPasskeyException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'MaktubPasskeyException($code): $message';
}
