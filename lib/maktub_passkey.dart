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
/// The actual work is delegated to a [MaktubPasskeyPlatform] — the real native
/// [MethodChannelMaktubPasskey] in production, a `FakeMaktubPasskey` (in the
/// test-only `package:maktub_passkey/testing.dart`) under test. The native
/// iOS/Android PRF impls live behind the method channel (#306); on a simulator
/// or an unsupported OS they report PRF unavailable, so the app's gate stays
/// fail-closed.
library;

import 'package:flutter/services.dart';

import 'src/platform.dart';
import 'src/types.dart';

export 'src/platform.dart' show MaktubPasskeyPlatform, MethodChannelMaktubPasskey;
export 'src/types.dart';

class MaktubPasskey {
  /// Uses the ambient [MaktubPasskeyPlatform.instance] by default. A specific
  /// [platform] (e.g. a fake) or a custom [channel] may be supplied — the
  /// channel form preserves the original constructor for existing callers.
  MaktubPasskey({MaktubPasskeyPlatform? platform, MethodChannel? channel})
      : assert(platform == null || channel == null,
            'pass either a platform or a channel, not both'),
        _platform = platform ??
            (channel != null
                ? MethodChannelMaktubPasskey(channel: channel)
                : null);

  /// Resolved lazily so a test that swaps [MaktubPasskeyPlatform.instance]
  /// after constructing still sees the swap.
  final MaktubPasskeyPlatform? _platform;
  MaktubPasskeyPlatform get _p => _platform ?? MaktubPasskeyPlatform.instance;

  /// Capability probe only — does the platform support PRF, and is the active
  /// credential backup-eligible/synced? Fails closed: any error or absence ⇒
  /// [PrfCapability.unavailable].
  Future<PrfCapability> probePrf({required String relyingPartyId}) =>
      _p.probePrf(relyingPartyId: relyingPartyId);

  /// Create a passkey credential **with the PRF extension enabled**, so PRF can
  /// be evaluated against it later. Throws [MaktubPasskeyException] on failure.
  Future<PasskeyCreation> create({
    required String relyingPartyId,
    required String relyingPartyName,
    required String userName,
    required Uint8List userId,
    required Uint8List challenge,
  }) =>
      _p.create(
        relyingPartyId: relyingPartyId,
        relyingPartyName: relyingPartyName,
        userName: userName,
        userId: userId,
        challenge: challenge,
      );

  /// Get an assertion AND evaluate PRF with [prfSalt] (the fixed 32-byte
  /// `eval.first`), returning the signature plus the 32-byte PRF output.
  Future<PasskeyAssertion> assertWithPrf({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List prfSalt,
    String? credentialId,
  }) =>
      _p.assertWithPrf(
        relyingPartyId: relyingPartyId,
        challenge: challenge,
        prfSalt: prfSalt,
        credentialId: credentialId,
      );
}
