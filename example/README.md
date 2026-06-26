# maktub_passkey example

A minimal app exercising the three calls — `probePrf`, `create`, and
`assertWithPrf` — in [`lib/main.dart`](lib/main.dart).

Passkeys require a domain-associated app, so the buttons only do something
useful on a real **iOS 18+ / Android API 28+** device whose app is set up per
the package [README](../README.md) (Associated Domains / `assetlinks.json`),
with `_rpId` changed to your domain.

This folder ships without platform runners to stay small. To run it:

```sh
cd example
flutter create .   # regenerate the ios/ and android/ runners
flutter run
```
