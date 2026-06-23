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
    required this.attestationObject,
    required this.capability,
  });

  /// Base64url credential id.
  final String credentialId;

  /// The raw WebAuthn **attestation object** as returned by the platform — NOT
  /// the bare public key. The smart-wallet verifier needs the COSE P-256 key,
  /// which must be parsed out of this (`authData → attestedCredentialData →
  /// COSE key`). That extraction is the userOp-signing-migration step (#307);
  /// the PRF reading-key path does not read this field.
  final Uint8List attestationObject;

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
    this.backupEligible = false,
    this.backupState = false,
  });

  final Uint8List signature;
  final Uint8List authenticatorData;
  final Uint8List clientDataJson;

  /// 32-byte WebAuthn PRF (`hmac-secret`) output, or null if unavailable.
  final Uint8List? prfOutput;

  /// `BE` flag read from the authenticator-data of THIS assertion — the
  /// credential is backup-eligible (can sync off-device).
  final bool backupEligible;

  /// `BS` flag — the credential is currently backed up (synced). BE ∧ BS is the
  /// recoverability condition the app's fail-closed gate requires.
  final bool backupState;
}

/// Raised when the platform passkey/PRF operation fails or is unsupported.
class MaktubPasskeyException implements Exception {
  const MaktubPasskeyException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'MaktubPasskeyException($code): $message';
}
