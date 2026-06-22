/// `maktub_passkey` — passkey (WebAuthn / P-256) create + assert, plus the
/// WebAuthn **PRF (`hmac-secret`)** extension.
///
/// This plugin owns the *whole* passkey flow on purpose: PRF must be requested
/// inside the same `makeCredential` (creation) and `getAssertion` (eval) calls,
/// so it can't be a PRF-only add-on bolted onto another plugin's credential.
/// Its job is narrow — return the bytes Maktub needs to reproduce a smartWallet
/// reading key from the passkey:
///
///   * [create]        — make a credential WITH PRF enabled; report capability.
///   * [assertWithPrf] — sign AND evaluate PRF with a fixed salt → 32-byte output.
///   * [probePrf]      — capability only (PRF supported? backup-eligible/synced?).
///
/// The 32-byte PRF output + capability flags feed the app-side derivation and
/// the fail-closed creation gate (Maktub's `probePasskeyPrf()` seam). See the
/// reading-key spec (maktub#304) and the PRD (#306; umbrella #301).
///
/// **Status: scaffold.** The native iOS/Android PRF implementations are stubbed
/// fail-closed (PRF reported unavailable) until #301 lands them and a
/// real-device cross-device QA run passes. Until then the app keeps passkey
/// account creation gated off.
library;

import 'package:flutter/services.dart';

import 'src/types.dart';

export 'src/types.dart';

class MaktubPasskey {
  MaktubPasskey({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('it.maktub.passkey');

  final MethodChannel _channel;

  /// Capability probe only — does the platform support PRF, and is the active
  /// credential backup-eligible/synced? Fails closed: any error or absence ⇒
  /// [PrfCapability.unavailable].
  Future<PrfCapability> probePrf({required String relyingPartyId}) async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'probePrf',
        {'rpId': relyingPartyId},
      );
      if (r == null) return const PrfCapability.unavailable();
      return PrfCapability(
        prfSupported: r['prfSupported'] == true,
        backupEligible: r['backupEligible'] == true,
        backupState: r['backupState'] == true,
      );
    } on PlatformException {
      return const PrfCapability.unavailable();
    } on MissingPluginException {
      return const PrfCapability.unavailable();
    }
  }

  /// Create a passkey credential **with the PRF extension enabled**, so PRF can
  /// be evaluated against it later. Throws [MaktubPasskeyException] on failure.
  Future<PasskeyCreation> create({
    required String relyingPartyId,
    required String relyingPartyName,
    required String userName,
    required Uint8List userId,
    required Uint8List challenge,
  }) async {
    final r = await _invoke('create', {
      'rpId': relyingPartyId,
      'rpName': relyingPartyName,
      'userName': userName,
      'userId': userId,
      'challenge': challenge,
    });
    return PasskeyCreation(
      credentialId: r['credentialId'] as String,
      publicKeyDer: r['publicKeyDer'] as Uint8List,
      capability: PrfCapability(
        prfSupported: r['prfSupported'] == true,
        backupEligible: r['backupEligible'] == true,
        backupState: r['backupState'] == true,
      ),
    );
  }

  /// Get an assertion AND evaluate PRF with [prfSalt] (the fixed 32-byte
  /// `eval.first`), returning the signature plus the 32-byte PRF output.
  Future<PasskeyAssertion> assertWithPrf({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List prfSalt,
    String? credentialId,
  }) async {
    final r = await _invoke('assertWithPrf', {
      'rpId': relyingPartyId,
      'challenge': challenge,
      'prfSalt': prfSalt,
      'credentialId': credentialId,
    });
    final prf = r['prfOutput'];
    return PasskeyAssertion(
      signature: r['signature'] as Uint8List,
      authenticatorData: r['authenticatorData'] as Uint8List,
      clientDataJson: r['clientDataJson'] as Uint8List,
      prfOutput: prf is Uint8List ? prf : null,
    );
  }

  Future<Map<String, dynamic>> _invoke(
    String method,
    Map<String, dynamic> args,
  ) async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(method, args);
      if (r == null) {
        throw const MaktubPasskeyException('null-result', 'no result');
      }
      return r;
    } on PlatformException catch (e) {
      throw MaktubPasskeyException(e.code, e.message ?? 'platform error');
    } on MissingPluginException {
      throw const MaktubPasskeyException(
        'not-implemented',
        'maktub_passkey native side not implemented on this platform (#301)',
      );
    }
  }
}
