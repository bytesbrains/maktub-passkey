# Changelog

## 0.0.1 (unreleased)

- Scaffold: Dart facade (`MaktubPasskey` — `probePrf` / `create` / `assertWithPrf`)
  + `MethodChannel('it.maktub.passkey')`, result types (`PrfCapability`,
  `PasskeyCreation`, `PasskeyAssertion`).
- iOS (Swift) + Android (Kotlin) plugin stubs — **fail-closed**: PRF reported
  unavailable, `create`/`assertWithPrf` return `not-implemented`.
- Native WebAuthn PRF implementation is tracked in #301 (gated on real-device
  cross-device QA before the app enables passkey accounts).
