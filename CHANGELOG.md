# Changelog

## 0.1.0-dev.1

- First public **pre-release** to pub.dev. API + native iOS/Android PRF impls as
  below. **Experimental:** PRF cross-device stability is unverified on real
  hardware — the plugin is fail-closed where PRF is absent/device-bound/unsynced.
  `^` constraints will not auto-adopt a pre-release; adoption is deliberate until
  a stable `0.1.0`.

## 0.0.1 (unreleased)

- Dart facade (`MaktubPasskey` — `probePrf` / `create` / `assertWithPrf`) over a
  swappable `MaktubPasskeyPlatform` (`MethodChannelMaktubPasskey` default), with
  result types (`PrfCapability`, `PasskeyCreation`, `PasskeyAssertion`).
- **Native WebAuthn PRF implemented (#306):**
  - iOS (Swift) — `AuthenticationServices`, iOS 18+; `…PRFRegistrationInput` at
    create, `…PRFAssertionInput(saltInput1:)` at assert → `prf.first`; BE/BS read
    from the authenticator-data flags byte. Fail-closed below iOS 18.
  - Android (Kotlin) — `androidx.credentials` Credential Manager with the `prf`
    extension JSON → `clientExtensionResults.prf.results.first`; BE/BS from the
    authenticator-data flags. Fail-closed below API 28.
- `FakeMaktubPasskey` (`package:maktub_passkey/testing.dart`) — deterministic,
  release-excluded (`@visibleForTesting` + `assert(!kReleaseMode)`) test double.
- **Gated:** PRF is unverified on real hardware; the app keeps passkey accounts
  off until the cross-device QA run passes (#306 §10 / #307 C3).
