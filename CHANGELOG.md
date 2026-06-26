# Changelog

## 0.1.0-dev.3

- `PasskeyAssertion` now surfaces `credentialId` and `userHandle` (base64url) —
  the credential the platform actually used. For a discoverable assertion
  (`credentialId: null`) this is the only way to learn which credential the user
  picked, unblocking credential-bound PRF recovery (#2). Both native sides report
  it (iOS `credentialID`/`userID`; Android assertion `id`/`response.userHandle`).
  `userHandle` is nullable — it is omitted when the platform returns no user
  handle (e.g. a targeted assertion). Additive: existing callers are unaffected.

## 0.1.0-dev.2

- Documentation: public-ready README (self-contained, no internal references);
  reframed as a general WebAuthn-PRF plugin for Flutter. No API changes.

## 0.1.0-dev.1

- First public **pre-release**. WebAuthn passkey create/assert plus the PRF
  (`hmac-secret`) extension, over a swappable `MaktubPasskeyPlatform`:
  - **iOS** (`AuthenticationServices`, iOS 18+) — PRF enabled at creation; PRF
    output read from the assertion. Fail-closed below iOS 18.
  - **Android** (`androidx.credentials`, API 28+) — `prf` extension via the
    Credential Manager request JSON. Fail-closed below API 28.
  - `PrfCapability` / `PasskeyCreation` / `PasskeyAssertion` result types; BE/BS
    backup flags drive a fail-closed recoverability check.
- `FakeMaktubPasskey` (`package:maktub_passkey/testing.dart`) — deterministic,
  release-excluded test double for unit/widget tests.
- **Experimental:** PRF cross-device stability is unverified on real hardware;
  the plugin is fail-closed where PRF is absent / device-bound / not synced.
  `^` constraints will not auto-adopt a pre-release.
