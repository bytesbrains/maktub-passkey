/// **TEST-ONLY.** A deterministic in-memory [MaktubPasskeyPlatform] for unit,
/// widget and simulator tests — never for production.
///
/// A real authenticator's PRF output is a hardware/keychain secret we cannot
/// reproduce off-device; the fake stands in for it with a deterministic
/// function of a `syncedSeed` so tests can exercise OUR logic (probe → derive →
/// store → register, the fail-closed branches, the enrollment proof, and a
/// simulated new-device recovery) without a phone. It deliberately CANNOT
/// demonstrate the platform property that PRF is stable across two synced
/// devices — that stays the real-device QA blocker (#306 §10 / #307 C3).
///
/// **Release exclusion (non-negotiable, #307 C1).** This library is imported
/// only by tests; app `lib/` must never import it (a CI guard enforces that),
/// and the constructor asserts it is not running in a release build. So even if
/// it were wired by mistake, a release binary would trip the assert rather than
/// silently believe a non-recoverable key is recoverable.
library;

import 'package:flutter/foundation.dart';

import 'maktub_passkey.dart';

/// Deterministic, configurable fake. The `syncedSeed` models the credential's
/// synced PRF secret: two `FakeMaktubPasskey`s built with the SAME seed
/// reproduce the SAME PRF output for a given salt — that is how a "new synced
/// device" is simulated in tests.
@visibleForTesting
class FakeMaktubPasskey extends MaktubPasskeyPlatform {
  FakeMaktubPasskey({
    this.capability = const PrfCapability(
      prfSupported: true,
      backupEligible: true,
      backupState: true,
    ),
    Uint8List? syncedSeed,
    this.attestationObject,
    this.failProbe = false,
    MaktubPasskeyException? failCreate,
    MaktubPasskeyException? failAssert,
  })  : assert(
          !kReleaseMode,
          'FakeMaktubPasskey must never run in a release build (#307 C1).',
        ),
        _seed = syncedSeed ?? _defaultSeed,
        _failCreate = failCreate,
        _failAssert = failAssert {
    assert(_seed.length == 32, 'syncedSeed must be 32 bytes');
  }

  /// What [probePrf] / [create] report. Set to a non-recoverable value to
  /// exercise the fail-closed branches (no PRF, device-bound BE=0, not-backed-up
  /// BS=0).
  PrfCapability capability;

  /// Optional attestation object returned from [create]; defaults to a fixed
  /// 91-byte filler (its shape is irrelevant to the PRF reading-key tests).
  final Uint8List? attestationObject;

  /// When true, [probePrf] returns [PrfCapability.unavailable] (simulates a
  /// platform/probe failure without throwing).
  final bool failProbe;

  final Uint8List _seed;
  final MaktubPasskeyException? _failCreate;
  final MaktubPasskeyException? _failAssert;

  static final Uint8List _defaultSeed =
      Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 13) & 0xff));

  @override
  Future<PrfCapability> probePrf({required String relyingPartyId}) async =>
      failProbe ? const PrfCapability.unavailable() : capability;

  @override
  Future<PasskeyCreation> create({
    required String relyingPartyId,
    required String relyingPartyName,
    required String userName,
    required Uint8List userId,
    required Uint8List challenge,
  }) async {
    if (_failCreate != null) throw _failCreate;
    return PasskeyCreation(
      credentialId: 'fake-cred',
      attestationObject: attestationObject ??
          Uint8List.fromList(List<int>.filled(91, 4)),
      capability: capability,
    );
  }

  @override
  Future<PasskeyAssertion> assertWithPrf({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List prfSalt,
    String? credentialId,
  }) async {
    if (_failAssert != null) throw _failAssert;
    // PRF is exposed only when the capability would actually surface it; a
    // device-bound / no-PRF credential yields no output, exactly like a real
    // authenticator that did not enable hmac-secret.
    final prf = capability.prfSupported ? _prf(prfSalt) : null;
    return PasskeyAssertion(
      signature: Uint8List.fromList(List<int>.filled(64, 1)),
      authenticatorData: Uint8List.fromList(List<int>.filled(37, 2)),
      clientDataJson: Uint8List(0),
      prfOutput: prf,
      backupEligible: capability.backupEligible,
      backupState: capability.backupState,
    );
  }

  /// Deterministic 32-byte PRF: a function of the synced seed AND the salt, so
  /// the same (seed, salt) always reproduces (the stability a real synced
  /// authenticator provides) while a different salt yields a different output.
  Uint8List _prf(Uint8List salt) {
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final s = salt.isEmpty ? 0 : salt[i % salt.length];
      out[i] = (_seed[i] + s + i) & 0xff;
    }
    return out;
  }
}
