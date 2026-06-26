import 'package:flutter/services.dart';

import 'types.dart';

/// The swappable backend behind [MaktubPasskey].
///
/// Two implementations exist: [MethodChannelMaktubPasskey] (the real native
/// path, the production default) and `FakeMaktubPasskey` (in the separate
/// `package:maktub_passkey/testing.dart` library, test-only). Splitting the
/// platform out is what lets a test inject a deterministic PRF without the
/// native side, while keeping the production binary on the real probe — the
/// fake is never compiled into app code (see the testing library + the
/// integration gate, #306 §9 / #307 C1).
abstract class MaktubPasskeyPlatform {
  const MaktubPasskeyPlatform();

  /// The active platform. Defaults to the real method-channel backend; a test
  /// may swap in a fake and MUST restore it in tearDown. Production code never
  /// sets this — the only other implementation lives in a test-only library.
  static MaktubPasskeyPlatform instance = const MethodChannelMaktubPasskey();

  /// Capability probe only — does the platform support PRF, and is the active
  /// credential backup-eligible/synced? Fails closed: any error or absence ⇒
  /// [PrfCapability.unavailable].
  Future<PrfCapability> probePrf({required String relyingPartyId});

  /// Create a passkey credential **with the PRF extension enabled**, so PRF can
  /// be evaluated against it later. Throws [MaktubPasskeyException] on failure.
  Future<PasskeyCreation> create({
    required String relyingPartyId,
    required String relyingPartyName,
    required String userName,
    required Uint8List userId,
    required Uint8List challenge,
  });

  /// Get an assertion AND evaluate PRF with [prfSalt] (the fixed 32-byte
  /// `eval.first`), returning the signature plus the 32-byte PRF output.
  Future<PasskeyAssertion> assertWithPrf({
    required String relyingPartyId,
    required Uint8List challenge,
    required Uint8List prfSalt,
    String? credentialId,
  });
}

/// The real backend: a [MethodChannel] to the native iOS/Android PRF code.
///
/// All the marshaling (native map → typed result, defensive bool/bytes coercion,
/// fail-closed on absence) lives here so the fake can return typed objects
/// directly without re-implementing it.
class MethodChannelMaktubPasskey extends MaktubPasskeyPlatform {
  const MethodChannelMaktubPasskey({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('it.maktub.passkey');

  final MethodChannel _channel;

  @override
  Future<PrfCapability> probePrf({required String relyingPartyId}) async {
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'probePrf',
        {'rpId': relyingPartyId},
      );
      if (r == null) return const PrfCapability.unavailable();
      return _capabilityFrom(r);
    } on PlatformException {
      return const PrfCapability.unavailable();
    } on MissingPluginException {
      return const PrfCapability.unavailable();
    }
  }

  @override
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
      attestationObject: r['attestationObject'] as Uint8List,
      capability: _capabilityFrom(r),
    );
  }

  @override
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
      // The credential the platform actually used — the only way to identify it
      // after a discoverable assertion (#2). Defensive: a non-String reads as
      // null rather than surfacing a garbage id.
      credentialId: r['credentialId'] is String ? r['credentialId'] as String : null,
      userHandle: r['userHandle'] is String ? r['userHandle'] as String : null,
      // Defensive: a missing/garbage flag reads as false so a malformed native
      // map can never claim a recoverable (BE∧BS) credential.
      backupEligible: r['backupEligible'] == true,
      backupState: r['backupState'] == true,
    );
  }

  /// Defensive: any non-`true` value (missing key, `1`, `"yes"`, null) is read
  /// as false, so a malformed native map can never claim a recoverable key.
  static PrfCapability _capabilityFrom(Map<String, dynamic> r) => PrfCapability(
        prfSupported: r['prfSupported'] == true,
        backupEligible: r['backupEligible'] == true,
        backupState: r['backupState'] == true,
      );

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
