import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maktub_passkey/maktub_passkey.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: 'maktub_passkey example', home: HomePage());
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Change to a domain your app is associated with — Associated Domains on iOS,
  // assetlinks.json on Android. Passkey calls fail without that setup.
  static const _rpId = 'example.com';

  // A fixed, app-wide salt. The SAME salt on every device is what makes the
  // derived secret reproducible — it is not itself a secret.
  static final Uint8List _salt = Uint8List.fromList(
    List<int>.generate(32, (i) => i),
  );

  final _pk = MaktubPasskey();
  final _log = <String>[];
  String? _credentialId;

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.insert(0, line));
  }

  // 32 cryptographically-random bytes. In production the challenge usually comes
  // from your server so the assertion can be verified server-side.
  Uint8List _random32() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  // 1) Capability probe — never throws; fails closed to "unavailable".
  Future<void> _probe() async {
    final cap = await _pk.probePrf(relyingPartyId: _rpId);
    _append(
      'probe: supported=${cap.prfSupported} BE=${cap.backupEligible} '
      'BS=${cap.backupState} recoverable=${cap.recoverable}',
    );
  }

  // 2) Create a passkey with PRF enabled (PRF can't be retrofitted later).
  Future<void> _create() async {
    try {
      final c = await _pk.create(
        relyingPartyId: _rpId,
        relyingPartyName: 'Example',
        userName: 'you@example.com',
        userId: _random32(), // any stable per-user id; random here for the demo
        challenge: _random32(),
      );
      _credentialId = c.credentialId;
      _append('create: credentialId=${c.credentialId}');
    } on MaktubPasskeyException catch (e) {
      _append('create failed: ${e.code} — ${e.message}');
    }
  }

  // 3) Assert AND evaluate PRF → a reproducible 32-byte secret. Gate on
  //    recoverability first so we never derive a key that can't come back.
  Future<void> _assert() async {
    try {
      final cap = await _pk.probePrf(relyingPartyId: _rpId);
      if (!cap.recoverable) {
        _append('assert skipped: credential not recoverable (fail-closed)');
        return;
      }
      final a = await _pk.assertWithPrf(
        relyingPartyId: _rpId,
        challenge: _random32(),
        prfSalt: _salt,
        credentialId:
            _credentialId, // null → discoverable (user picks a passkey)
      );
      final prf = a.prfOutput;
      _append(
        'assert: chosenId=${a.credentialId} userHandle=${a.userHandle} '
        'prf=${prf == null ? 'null' : '${prf.length} bytes'}',
      );
    } on MaktubPasskeyException catch (e) {
      _append('assert failed: ${e.code} — ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('maktub_passkey example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: _probe, child: const Text('Probe')),
                FilledButton(onPressed: _create, child: const Text('Create')),
                FilledButton(
                  onPressed: _assert,
                  child: const Text('Assert + PRF'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Log (newest first):'),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder:
                    (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        _log[i],
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
