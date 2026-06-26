# Security Policy

## Reporting a vulnerability

Report security vulnerabilities **privately** — please do **not** open a public
issue, pull request, or discussion for anything security-sensitive.

Use GitHub private vulnerability reporting:
**[Report a vulnerability](https://github.com/bytesbrains/maktub-passkey/security/advisories/new)**
(repository → **Security** → **Report a vulnerability**). This opens an advisory
visible only to you and the maintainers.

Please include:

- affected version(s) and platform (iOS / Android + OS version),
- a description of the issue and its impact, and
- reproduction steps or a proof of concept, if you have one.

## What's in scope

This package derives key material from a passkey via the WebAuthn PRF
(`hmac-secret`) extension. Reports of particular interest:

- Anything that lets a **device-bound or non-synced** credential be treated as
  recoverable — the fail-closed `backupEligible ∧ backupState` (BE∧BS) gate is a
  core guarantee.
- PRF output being returned when it cannot be reproduced, or leaking through
  logs or error paths.
- Incorrect handling of the native ↔ Dart boundary that could surface the wrong
  `credentialId` / `userHandle`.

Out of scope: issues that require a compromised OS/authenticator, and the known,
documented limitation that cross-device PRF stability is not yet verified on real
hardware (see the README).

## Supported versions

This is a `0.1.x` pre-release; only the **latest** published version receives
security fixes. Pin and upgrade deliberately — pre-releases are not auto-selected
by `^` version constraints.

## Disclosure

We aim to acknowledge a report within a few days, agree a fix and timeline, and
credit reporters who want it once a fix ships.
