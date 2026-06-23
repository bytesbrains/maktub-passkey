# maktub_passkey

Passkey (WebAuthn / P-256) **create + assert**, plus the WebAuthn **PRF
(`hmac-secret`) extension** — the native shim that lets a Maktub `smartWallet`
**reproduce its ECIES reading key from the passkey**, so a new phone can read
already-received letters.

> **Status: native impl landed (#306), unverified on-device.** The Dart API, a
> swappable `MaktubPasskeyPlatform`, and the native iOS (`AuthenticationServices`,
> iOS 18+) / Android (`androidx.credentials`) PRF implementations are all in
> place. They are **fail-closed where PRF is absent** (older OS, simulator,
> device-bound credential). Until a **real-device cross-device QA run** passes
> (the CISO GA blocker), the app keeps passkey account creation gated off — no
> false "recoverable" claim. A test-only `FakeMaktubPasskey`
> (`package:maktub_passkey/testing.dart`) drives the app logic in CI; it is
> compile-excluded from release.

## Why this exists

Maktub's recovery model is **one secret per account** (see the reading-key spec,
**maktub#304**). A `localKey` account reproduces its reading key from the seed
or the private key. A passkey (`smartWallet`) account has neither — its
reproducible secret is the **WebAuthn PRF output**. The `passkeys` plugin we use
for create/sign exposes **no PRF API**, so this package owns the passkey flow
*including* PRF.

It must own the **whole** flow, not be a PRF-only add-on: PRF has to be
requested inside the same `makeCredential` (creation) and `getAssertion` (eval)
calls, so a side-package can't guarantee creation-time `hmac-secret`
enablement.

## What it returns (the seam contract)

The app side (`probePasskeyPrf()` in the mobile app) only needs:

```
{ prfOutput: 32 bytes, backupEligible: bool, backupState: bool }
```

The 32-byte PRF output feeds `deriveReadingKeyFromPrfOutput` (already built +
tested in the app/SDK); the BE/BS flags drive the **fail-closed creation gate**
(refuse device-bound credentials — they'd strand the user on a new device).

## API

```dart
final pk = MaktubPasskey();

// Capability only — does PRF work AND is the credential synced?
final cap = await pk.probePrf(relyingPartyId: 'maktub.it');
if (!cap.recoverable) { /* fall back to a recovery-phrase account */ }

// Create a credential WITH PRF enabled.
final created = await pk.create(
  relyingPartyId: 'maktub.it', relyingPartyName: 'Maktub',
  userName: email, userId: userId, challenge: challenge);

// Sign AND evaluate PRF → 32-byte output.
final a = await pk.assertWithPrf(
  relyingPartyId: 'maktub.it', challenge: challenge, prfSalt: prfSalt);
final reading = deriveReadingKeyFromPrfOutput(a.prfOutput!); // app/SDK side
```

## Native implementation (the #301 work)

- **iOS 18+** — `AuthenticationServices`:
  `ASAuthorizationPublicKeyCredentialPRFRegistrationInputs` at create,
  `…PRFAssertionInputs(inputValues: .init(saltInput1: prfSalt))` at assert →
  `result.prf.first`.
- **Android** — `androidx.credentials` (Credential Manager) with the `prf`
  extension in the request JSON → `clientExtensionResults.prf.results.first`.
- Both report PRF support + the **BE/BS** backup flags for the gate.

## Hard constraints (don't skip)

- **Native code on both platforms → unverifiable in the simulator e2e harness.**
  Requires a **real-device cross-device PRF QA run** (iOS↔iOS and Android)
  before the app flips `kPasskeyAccountsEnabled` on. This is the CISO GA blocker.
- **Fail-closed:** if PRF isn't enabled, or the credential is device-bound
  (`BE=0`), report unavailable — never derive a key that can't be reproduced.
- PRF output stability across synced devices is spec-intended; the QA run
  proves it.

## Layout

```
maktub_passkey/
├── lib/maktub_passkey.dart      # Dart facade (delegates to the platform)
├── lib/src/platform.dart        # MaktubPasskeyPlatform + MethodChannel impl
├── lib/src/types.dart           # PrfCapability / PasskeyCreation / PasskeyAssertion
├── lib/testing.dart             # FakeMaktubPasskey (TEST-ONLY, release-excluded)
├── ios/                         # podspec + Swift plugin (AuthenticationServices)
└── android/                     # build.gradle + Kotlin plugin (Credential Manager)
```

Consumed by `mobile/` as a path dependency (#307). License: MIT.

## See also

- **maktub#304** — reading-key derivation & recovery spec (canonical).
- **#306** — this package's PRD / build spec (native PRF impl + integration + QA gate).
- **#301** — umbrella issue (native PRF / re-enable passkey accounts).
