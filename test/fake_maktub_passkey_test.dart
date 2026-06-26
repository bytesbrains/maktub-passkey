import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maktub_passkey/maktub_passkey.dart';
import 'package:maktub_passkey/testing.dart';

void main() {
  // The fixed salt the app evaluates PRF with (mirrors mobile `prfSalt()`); a
  // constant here is enough to assert (seed, salt) determinism.
  final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));

  group('FakeMaktubPasskey injected as the platform', () {
    tearDown(() {
      // Always restore the real backend so one test can't leak the fake into
      // another (and so production-shaped tests stay honest).
      MaktubPasskeyPlatform.instance = const MethodChannelMaktubPasskey();
    });

    test('MaktubPasskey() picks up a swapped-in fake instance', () async {
      MaktubPasskeyPlatform.instance = FakeMaktubPasskey();
      final cap = await MaktubPasskey().probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isTrue);
    });

    test('assertWithPrf returns a 32-byte deterministic PRF output', () async {
      final fake = FakeMaktubPasskey();
      final a = await fake.assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: Uint8List(32),
        prfSalt: salt,
      );
      expect(a.prfOutput, isNotNull);
      expect(a.prfOutput!.length, 32);
    });

    test('surfaces credentialId/userHandle: echoes a targeted id, defaults a '
        'discoverable one (#2)', () async {
      final fake = FakeMaktubPasskey(userHandle: 'user-42');
      final targeted = await fake.assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: Uint8List(32),
        prfSalt: salt,
        credentialId: 'cred-abc',
      );
      expect(targeted.credentialId, 'cred-abc'); // echoed back
      expect(targeted.userHandle, 'user-42');

      final discoverable = await fake.assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: Uint8List(32),
        prfSalt: salt,
      );
      expect(discoverable.credentialId, isNotNull); // a chosen id is reported
      expect(discoverable.userHandle, 'user-42');
    });

    test('same syncedSeed + same salt → identical PRF (new-device recovery)',
        () async {
      final seed = Uint8List.fromList(List<int>.filled(32, 0x5A));
      Future<Uint8List?> evalOn(FakeMaktubPasskey f) async => (await f
              .assertWithPrf(
                  relyingPartyId: 'maktub.it',
                  challenge: Uint8List(32),
                  prfSalt: salt))
          .prfOutput;

      final deviceA = await evalOn(FakeMaktubPasskey(syncedSeed: seed));
      final deviceB = await evalOn(FakeMaktubPasskey(syncedSeed: seed));
      expect(deviceB, equals(deviceA)); // synced → reproduces
    });

    test('different syncedSeed → different PRF output', () async {
      Future<Uint8List?> eval(int fill) async => (await FakeMaktubPasskey(
                  syncedSeed: Uint8List.fromList(List<int>.filled(32, fill)))
              .assertWithPrf(
                  relyingPartyId: 'maktub.it',
                  challenge: Uint8List(32),
                  prfSalt: salt))
          .prfOutput;
      expect(await eval(1), isNot(equals(await eval(2))));
    });

    test('different salt → different PRF output (salt-sensitive)', () async {
      final fake = FakeMaktubPasskey();
      Future<Uint8List?> evalSalt(int fill) async => (await fake.assertWithPrf(
                relyingPartyId: 'maktub.it',
                challenge: Uint8List(32),
                prfSalt: Uint8List.fromList(List<int>.filled(32, fill)),
              ))
          .prfOutput;
      expect(await evalSalt(3), isNot(equals(await evalSalt(4))));
    });

    test('device-bound capability (BE=0) is not recoverable and yields no PRF',
        () async {
      final fake = FakeMaktubPasskey(
        capability: const PrfCapability(
            prfSupported: false, backupEligible: false, backupState: false),
      );
      final cap = await fake.probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
      final a = await fake.assertWithPrf(
        relyingPartyId: 'maktub.it',
        challenge: Uint8List(32),
        prfSalt: salt,
      );
      expect(a.prfOutput, isNull); // no PRF surfaced when unsupported
    });

    test('failProbe → unavailable without throwing', () async {
      final cap = await FakeMaktubPasskey(failProbe: true)
          .probePrf(relyingPartyId: 'maktub.it');
      expect(cap.recoverable, isFalse);
    });

    test('failCreate / failAssert surface the configured exception', () async {
      final fake = FakeMaktubPasskey(
        failCreate: const MaktubPasskeyException('user-cancelled', 'nope'),
        failAssert: const MaktubPasskeyException('no-prf', 'unsupported'),
      );
      expect(
        () => fake.create(
          relyingPartyId: 'maktub.it',
          relyingPartyName: 'Maktub',
          userName: 'a@b.co',
          userId: Uint8List(16),
          challenge: Uint8List(32),
        ),
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'user-cancelled')),
      );
      expect(
        () => fake.assertWithPrf(
          relyingPartyId: 'maktub.it',
          challenge: Uint8List(32),
          prfSalt: salt,
        ),
        throwsA(isA<MaktubPasskeyException>()
            .having((e) => e.code, 'code', 'no-prf')),
      );
    });
  });
}
