import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_passkey/maktub_passkey.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('it.maktub.passkey');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Records the last MethodCall so tests can assert the marshaled args, and
  // returns whatever `reply` yields (or throws to simulate a platform error).
  late MethodCall? lastCall;
  void onCall(Future<Object?> Function(MethodCall) reply) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      lastCall = call;
      return reply(call);
    });
  }

  setUp(() => lastCall = null);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Uint8List bytes(int n, [int fill = 0]) =>
      Uint8List.fromList(List<int>.filled(n, fill));

  Map<Object?, Object?> args() => lastCall!.arguments as Map<Object?, Object?>;

  // ── PrfCapability — the recoverable truth table ───────────────────────────
  group('PrfCapability', () {
    test('recoverable iff PRF supported AND backup-eligible AND backed up', () {
      PrfCapability cap(bool prf, bool be, bool bs) => PrfCapability(
          prfSupported: prf, backupEligible: be, backupState: bs);
      expect(cap(true, true, true).recoverable, isTrue);
      expect(cap(false, true, true).recoverable, isFalse); // no PRF
      expect(cap(true, false, true).recoverable, isFalse); // not eligible
      expect(cap(true, true, false).recoverable, isFalse); // not backed up
      expect(cap(false, false, false).recoverable, isFalse);
    });

    test('deviceBound iff not backup-eligible (PRF alone is not enough)', () {
      expect(
        const PrfCapability(
                prfSupported: true, backupEligible: false, backupState: false)
            .deviceBound,
        isTrue,
      );
      expect(
        const PrfCapability(
                prfSupported: true, backupEligible: true, backupState: true)
            .deviceBound,
        isFalse,
      );
    });

    test('unavailable() is all-false and never recoverable', () {
      const u = PrfCapability.unavailable();
      expect(u.prfSupported, isFalse);
      expect(u.backupEligible, isFalse);
      expect(u.backupState, isFalse);
      expect(u.recoverable, isFalse);
      expect(u.deviceBound, isTrue);
    });
  });

  // ── probePrf — capability, fail-closed everywhere ─────────────────────────
  group('probePrf', () {
    test('maps a full native capability map and sends rpId', () async {
      onCall((_) async => {
            'prfSupported': true,
            'backupEligible': true,
            'backupState': true,
          });
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isTrue);
      expect(lastCall!.method, 'probePrf');
      expect(args()['rpId'], 'maktub.it');
    });

    test('missing/partial keys default to false (defensive)', () async {
      onCall((_) async => <String, dynamic>{'prfSupported': true});
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.prfSupported, isTrue);
      expect(cap.backupEligible, isFalse);
      expect(cap.backupState, isFalse);
      expect(cap.recoverable, isFalse);
    });

    test('non-bool / garbage values are treated as false', () async {
      onCall((_) async => <String, dynamic>{
            'prfSupported': 'yes',
            'backupEligible': 1,
            'backupState': null,
          });
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
      expect(cap.prfSupported, isFalse);
    });

    test('null native result → unavailable', () async {
      onCall((_) async => null);
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
    });

    test('PlatformException → unavailable (never throws)', () async {
      onCall((_) async => throw PlatformException(code: 'boom'));
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
      expect(cap.prfSupported, isFalse);
    });

    test('missing plugin (no handler) → unavailable, never throws', () async {
      // No mock handler installed.
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
    });
  });

  // ── create ────────────────────────────────────────────────────────────────
  group('create', () {
    Future<PasskeyCreation> doCreate() => MaktubPasskey().create(
          relyingPartyId: 'maktub.it',
          relyingPartyName: 'Maktub',
          userName: 'a@b.co',
          userId: bytes(16, 7),
          challenge: bytes(32, 9),
        );

    test('maps the result and marshals all args', () async {
      onCall((_) async => {
            'credentialId': 'cred-123',
            'attestationObject': bytes(91, 4),
            'prfSupported': true,
            'backupEligible': true,
            'backupState': true,
          });
      final c = await doCreate();
      expect(c.credentialId, 'cred-123');
      expect(c.attestationObject.length, 91);
      expect(c.capability.recoverable, isTrue);

      expect(lastCall!.method, 'create');
      final a = args();
      expect(a['rpId'], 'maktub.it');
      expect(a['rpName'], 'Maktub');
      expect(a['userName'], 'a@b.co');
      expect((a['userId'] as Uint8List).length, 16);
      expect((a['challenge'] as Uint8List).length, 32);
    });

    test('PlatformException → MaktubPasskeyException carrying code+message',
        () async {
      onCall((_) async =>
          throw PlatformException(code: 'user-cancelled', message: 'nope'));
      expect(
        doCreate,
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'user-cancelled')
            .having((e) => e.message, 'message', 'nope')),
      );
    });

    test('missing plugin → not-implemented MaktubPasskeyException', () async {
      // No handler installed → MissingPluginException.
      expect(
        doCreate,
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'not-implemented')),
      );
    });

    test('null result → null-result MaktubPasskeyException', () async {
      onCall((_) async => null);
      expect(
        doCreate,
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'null-result')),
      );
    });
  });

  // ── assertWithPrf ──────────────────────────────────────────────────────────
  group('assertWithPrf', () {
    Map<String, Object?> reply({Object? prf}) => {
          'signature': bytes(64),
          'authenticatorData': bytes(37),
          'clientDataJson': bytes(0),
          if (prf != null) 'prfOutput': prf,
        };

    test('surfaces the 32-byte PRF output and marshals args', () async {
      final prf = bytes(32, 0xAB);
      onCall((_) async => reply(prf: prf));
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32, 1),
        prfSalt: bytes(32, 2),
        credentialId: 'cred-9',
      );
      expect(a.prfOutput, equals(prf));
      expect(a.signature.length, 64);
      expect(a.authenticatorData.length, 37);

      expect(lastCall!.method, 'assertWithPrf');
      final m = args();
      expect(m['rpId'], 'maktub.it');
      expect((m['challenge'] as Uint8List).length, 32);
      expect((m['prfSalt'] as Uint8List)[0], 2);
      expect(m['credentialId'], 'cred-9');
    });

    test('surfaces the chosen credentialId/userHandle from a discoverable '
        'assertion (#2)', () async {
      onCall((_) async => {
            ...reply(prf: bytes(32)),
            'credentialId': 'picked-cred',
            'userHandle': 'picked-user',
          });
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
        // No credentialId → discoverable; the caller learns the picked one.
      );
      expect(a.credentialId, 'picked-cred');
      expect(a.userHandle, 'picked-user');
    });

    test('credentialId/userHandle default to null when native omits them, and '
        'a non-String reads as null (defensive)', () async {
      onCall((_) async => reply(prf: bytes(32)));
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(a.credentialId, isNull);
      expect(a.userHandle, isNull);

      onCall((_) async => {
            ...reply(prf: bytes(32)),
            'credentialId': 42,
            'userHandle': <int>[1, 2, 3],
          });
      final b = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(b.credentialId, isNull);
      expect(b.userHandle, isNull);
    });

    test('marshals BE/BS flags; missing flags default to false (defensive)',
        () async {
      onCall((_) async => {
            ...reply(prf: bytes(32)),
            'backupEligible': true,
            'backupState': true,
          });
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(a.backupEligible, isTrue);
      expect(a.backupState, isTrue);

      // A reply without the flags reads as false, never a phantom recoverable.
      onCall((_) async => reply(prf: bytes(32)));
      final b = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(b.backupEligible, isFalse);
      expect(b.backupState, isFalse);
    });

    test('null prfOutput when native omits it', () async {
      onCall((_) async => reply());
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(a.prfOutput, isNull);
    });

    test('non-bytes prfOutput is treated as null (defensive)', () async {
      onCall((_) async => reply(prf: 'not-bytes'));
      final a = await MaktubPasskey().assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: bytes(32),
        prfSalt: bytes(32),
      );
      expect(a.prfOutput, isNull);
    });

    test('PlatformException → MaktubPasskeyException', () async {
      onCall((_) async => throw PlatformException(code: 'no-prf'));
      expect(
        () => MaktubPasskey().assertWithPrf(
          relyingPartyId: 'maktub.it',
          challenge: bytes(32),
          prfSalt: bytes(32),
        ),
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'no-prf')),
      );
    });
  });

  // ── MaktubPasskeyException ──────────────────────────────────────────────────
  test('MaktubPasskeyException exposes code+message and a readable toString',
      () {
    const e = MaktubPasskeyException('x-code', 'x-message');
    expect(e.code, 'x-code');
    expect(e.message, 'x-message');
    expect(e.toString(), contains('x-code'));
    expect(e.toString(), contains('x-message'));
  });
}
