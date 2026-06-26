# maktub_passkey

[![pub package](https://img.shields.io/pub/v/maktub_passkey.svg)](https://pub.dev/packages/maktub_passkey)
[![pub points](https://img.shields.io/pub/points/maktub_passkey.svg)](https://pub.dev/packages/maktub_passkey/score)
[![likes](https://img.shields.io/pub/likes/maktub_passkey.svg)](https://pub.dev/packages/maktub_passkey/score)
[![CI](https://github.com/bytesbrains/maktub-passkey/actions/workflows/ci.yml/badge.svg)](https://github.com/bytesbrains/maktub-passkey/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Passkey (WebAuthn / P-256) **create + assert** for Flutter, plus the WebAuthn
**PRF (`hmac-secret`) extension** — so you can derive a **stable, per-credential
secret** from a synced passkey and reproduce it on another of the user's devices
(e.g. to re-derive an encryption key after a device change). It's the PRF API
the common Flutter passkey plugins don't expose.

> ⚠️ **EXPERIMENTAL — pre-release (`0.1.x-dev`).** The native iOS
> (`AuthenticationServices`) and Android (`androidx.credentials`) PRF
> implementations are in place and unit/simulator-tested, but the **stability of
> the PRF output across two *synced* devices** — the property that the *same*
> secret comes back on a second device — is **not yet verified on real
> hardware**. The plugin is **fail-closed**: where PRF is unavailable,
> device-bound, or not synced, it reports the credential as unrecoverable rather
> than returning a secret that can't be reproduced. **Validate cross-device
> recovery on your own synced devices before relying on it.** Because it's a
> pre-release, `^` version constraints won't auto-select it — opt in explicitly.

## When to use this

Reach for this when you need a **stable secret derived from a passkey that
reproduces across a user's synced devices** — e.g. re-deriving an end-to-end
encryption key on a new phone with no server-side escrow. That cross-device
*reproducibility* is the WebAuthn PRF (`hmac-secret`) capability, and it's the
specific gap this plugin fills.

It is **not** a passkey *login* library. If you only need authentication
(register / sign-in against your server), use a full WebAuthn stack instead —
this plugin deliberately exposes just the create / assert / PRF primitives needed
to derive and reproduce key material, paired with a fail-closed recoverability
gate.

- **Use it when** you want a passkey-derived, cross-device-reproducible secret
  and can target iOS 18+ / Android API 28+.
- **Look elsewhere when** you need passkey auth flows, device-bound (non-synced)
  hardware keys, or support for older OS versions.

## What it does

- **`create`** a platform passkey with the **PRF extension enabled at creation**
  (PRF can't be retrofitted onto a credential made without it).
- **`assertWithPrf`** — get an assertion *and* evaluate PRF with a caller-chosen
  32-byte salt, returning the **32-byte PRF output**, the credential's backup
  flags, and the **`credentialId` / `userHandle` the platform actually used** —
  so a *discoverable* assertion can learn which passkey the user picked and bind
  later recovery to it (since `0.1.0-dev.3`).
- **`probePrf`** — a capability check (is PRF available, is the credential
  backup-eligible and synced?).

The 32-byte output is uniform key material — feed it into your own KDF (HKDF,
etc.) to derive whatever keys you need. The same `(credential, salt)` yields the
same output, which is what makes the derived key reproducible on a synced device.

## API

| Method | Returns | Errors / null |
|---|---|---|
| `probePrf({relyingPartyId})` | `PrfCapability` — `prfSupported`, `backupEligible`, `backupState`, `recoverable` | never throws; fails closed to `unavailable` |
| `create({relyingPartyId, relyingPartyName, userName, userId, challenge})` | `PasskeyCreation` — `credentialId`, `attestationObject`, `capability` | throws `MaktubPasskeyException` |
| `assertWithPrf({relyingPartyId, challenge, prfSalt, credentialId?})` | `PasskeyAssertion` — `prfOutput`, `signature`, `credentialId`, `userHandle`, `backupEligible`, `backupState` | throws `MaktubPasskeyException`; `prfOutput` is `null` if PRF is unavailable |

All byte params are `Uint8List`; ids and handles are base64url `String`. `prfSalt`
is your fixed 32-byte salt — the same `(credential, salt)` always yields the same
32-byte `prfOutput`. Omit `credentialId` for a **discoverable** assertion (the
platform lists every RP passkey and the user picks); pass it for a **targeted**
one. Always gate on `PrfCapability.recoverable` before relying on a secret.

## Platform support

| Platform | Min version | Backing API |
|---|---|---|
| iOS | 18.0+ | `AuthenticationServices` (`ASAuthorizationPublicKeyCredentialPRF*`) |
| Android | API 28+ (Credential Manager) | `androidx.credentials` `prf` extension |

Below those versions, or on the simulator/emulator (no real authenticator), PRF
is reported unavailable and the plugin fails closed.

## Install

```yaml
dependencies:
  maktub_passkey: 0.1.0-dev.3   # pre-release: pin explicitly (no caret — won't auto-adopt)
```

## Platform setup (required)

Passkeys are bound to a **domain**: the platform refuses to create or assert one
unless your app is verifiably associated with the `relyingPartyId` you pass.
Skip this and calls fail (or the system sheet never appears) — it is not
optional. The `relyingPartyId` must be a registrable HTTPS domain
(e.g. `example.com` — no scheme, no port) and must match the files below.

### iOS — Associated Domains

1. Add the **Associated Domains** capability in Xcode and list your RP id:

   ```xml
   <!-- Runner.entitlements -->
   <key>com.apple.developer.associated-domains</key>
   <array>
     <string>webcredentials:example.com</string>
   </array>
   ```

2. Host an **Apple App Site Association** file at
   `https://example.com/.well-known/apple-app-site-association`, served as
   `application/json` with no redirect:

   ```json
   { "webcredentials": { "apps": ["ABCDE12345.com.example.app"] } }
   ```

   `ABCDE12345` is your Team ID, `com.example.app` your bundle id.

### Android — Digital Asset Links

Host an **assetlinks.json** at
`https://example.com/.well-known/assetlinks.json` declaring your app and the
certificate(s) it is signed with:

```json
[
  {
    "relation": ["delegate_permission/common.get_login_creds"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.app",
      "sha256_cert_fingerprints": ["AB:CD:EF:..."]
    }
  }
]
```

List the SHA-256 fingerprint of **every** signing key your users receive — your
upload key **and** the Play App Signing key (Google re-signs the app on upload),
or verification fails in production.

## Usage

```dart
import 'package:maktub_passkey/maktub_passkey.dart';

final pk = MaktubPasskey();
const rpId = 'example.com'; // your associated domain

// 1. Capability check — is PRF usable AND is the credential synced?
final cap = await pk.probePrf(relyingPartyId: rpId);
if (!cap.recoverable) {
  // Fall back: no PRF, or the credential is device-bound / not backed up.
}

// 2. Create a credential WITH PRF enabled.
final created = await pk.create(
  relyingPartyId: rpId,
  relyingPartyName: 'Example',
  userName: 'you@example.com',
  userId: userIdBytes,        // Uint8List
  challenge: challengeBytes,  // Uint8List
);

// 3. Sign AND evaluate PRF with a fixed salt → 32-byte output.
final a = await pk.assertWithPrf(
  relyingPartyId: rpId,
  challenge: challengeBytes,
  prfSalt: saltBytes,         // your fixed 32-byte salt
  credentialId: created.credentialId, // omit (null) for a discoverable assertion
);
final Uint8List? secret = a.prfOutput; // 32 bytes of key material (or null)

// For a **discoverable** assertion (credentialId: null — the platform sheet
// lists every RP passkey and the user picks one), the chosen credential is
// reported back so you can bind later recovery to it:
final String? chosenId = a.credentialId; // base64url id the platform used
final String? userHandle = a.userHandle; // base64url user handle, or null
// `userHandle` is null when the platform returns none (common for a targeted
// assertion); `credentialId` echoes the requested id for a targeted assertion.
```

## Recipe: re-derive an encryption key on a new device

The whole point — the *same* key comes back on a second synced device, with no
server escrow. On **both** devices, run the same salt against the user's passkey:

```dart
// Same fixed, app-wide salt on every device (store it in your app, not secret).
final salt = utf8.encode('my-app/e2ee-key/v1').sublist(0, 32); // 32 bytes

Future<Uint8List?> deriveKey(MaktubPasskey pk, String rpId) async {
  final cap = await pk.probePrf(relyingPartyId: rpId);
  if (!cap.recoverable) return null; // fail closed — don't derive an unrecoverable key

  final a = await pk.assertWithPrf(
    relyingPartyId: rpId,
    challenge: freshChallenge(), // 32 random bytes from your server/app
    prfSalt: salt,
    // credentialId omitted → discoverable: the user picks their synced passkey
  );
  final prf = a.prfOutput;
  if (prf == null) return null;

  // `prf` is uniform 32-byte key material; run it through HKDF for your context.
  return hkdfSha256(ikm: prf, info: utf8.encode('aes-gcm-key'), length: 32);
}
```

Device A enrolls (`create` once), both A and B call `deriveKey` → identical
output, because the passkey synced via iCloud Keychain / Google Password Manager.

## Recoverability rule (and why it's fail-closed)

A derived secret only reproduces on a new device if the **credential itself
syncs** there. So `PrfCapability.recoverable` requires **all** of:

- PRF supported, **and**
- `backupEligible` (BE) — the credential can sync off-device, **and**
- `backupState` (BS) — it is currently backed up / synced.

A device-bound credential (`BE = 0`) "works" locally but would strand the user
on a new device — so the plugin treats it as **not** recoverable. It never
returns a secret it can't promise to reproduce.

## Testing

The package ships a deterministic, **test-only** fake so you can exercise your
logic without a device:

```dart
import 'package:maktub_passkey/testing.dart';

// Inject a deterministic PRF keyed by a `syncedSeed`; two fakes with the same
// seed model two synced devices. (Asserts !kReleaseMode; never use in app code.)
MaktubPasskeyPlatform.instance = FakeMaktubPasskey(syncedSeed: seed);
```

> The fake **demonstrates your logic**; it cannot *prove* the platform property
> that real hardware returns a stable PRF across synced devices. That still
> requires a real two-device run.

## Layout

```
lib/maktub_passkey.dart   Dart facade (delegates to the platform)
lib/src/platform.dart     MaktubPasskeyPlatform + MethodChannel impl
lib/src/types.dart        PrfCapability / PasskeyCreation / PasskeyAssertion
lib/testing.dart          FakeMaktubPasskey (TEST-ONLY, release-excluded)
ios/                      podspec + Swift plugin (AuthenticationServices)
android/                  build.gradle + Kotlin plugin (Credential Manager)
```

## Development

After cloning, enable the secret-scanning pre-commit hook (one-time; git never
auto-installs hooks):

```sh
git config core.hooksPath .githooks   # runs `gitleaks protect --staged` on commit
brew install gitleaks                 # if not already installed
```

## About

Maintained by **[BytesBrains](https://pub.dev/publishers/bytesbrains.com/packages)**
as part of the **[Maktub](https://maktub.it)** ecosystem — a protocol for
delivering end-to-end-encrypted messages on a timer, to the people they're
written for. This plugin is the passkey/PRF building block that lets a Maktub
account re-derive its encryption key from a synced passkey; it's published
standalone because the capability is useful to any Flutter app that wants
passkey-derived secrets.

License: **MIT**.
