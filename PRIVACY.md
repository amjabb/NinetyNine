# Privacy Policy — Ninety-Nine

**Last updated: 29 July 2026**

## The short version

Ninety-Nine collects nothing, sends nothing, and stores nothing about you
anywhere except on your own device.

## What is collected

Nothing.

There is no account, no sign-in, no analytics, no advertising, no crash
reporting SDK, and no third-party services of any kind. The app does not ask for
your name, email, contacts, location, photos, or any other personal information,
because it has no use for them.

## What leaves your device

Nothing.

The app contains **no networking code at all**. It does not make web requests,
and the compiled binary does not even link a networking framework — this is
verifiable in the public source: see `Docs/ARCHITECTURE.md` and the linked
frameworks of any build.

## What is stored on your device

Your settings (sound, haptics, coaching, difficulty, table size) and your game
record (games played, wins, streaks, achievements) are saved locally using
Apple's standard `UserDefaults` storage, inside the app's own private container.

This data:

- never leaves your device
- is not readable by other apps
- is included in an encrypted iCloud/iTunes device backup only if you have
  device backups enabled, under your own Apple account and Apple's control
- is permanently deleted when you delete the app

You can erase it at any time from **Settings → Data → Reset record and
achievements** inside the app.

## Device motion

The app reads the device's motion sensor to add a subtle parallax effect to the
table background. This reading happens entirely on-device, in memory, for the
current frame only. It is never recorded, stored, or transmitted, and it is
disabled automatically when iOS "Reduce Motion" is switched on.

## Children

The app is rated 4+ and is safe for all ages. Because it collects no data
whatsoever, it collects no data from children either, and is compliant with
COPPA and similar regulations by construction.

## Tracking

The app does not track you. It does not use the Advertising Identifier (IDFA),
does not request App Tracking Transparency permission, and shares no data with
data brokers or advertisers. This is declared formally in the app's
`PrivacyInfo.xcprivacy` manifest, which is part of the public source.

## Third parties

There are none. No SDKs, no frameworks beyond Apple's own, no partners, no
processors.

## Changes to this policy

If a future version of the app ever collects or transmits anything, this policy
will be updated before that version ships, and the change will be visible in
this file's public commit history.

## Contact

Questions about privacy: please open an issue on the project's GitHub
repository.
