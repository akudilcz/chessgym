# Chess Gym — Privacy Policy

**Effective date:** 2026-04-23
**Version:** 1.0

Chess Gym ("we", "the app") is developed and distributed as a free offline chess puzzle trainer. This document describes our practices around user data.

## What we collect

**Nothing.**

The app does not collect, transmit, sell, or share any personal information, usage analytics, crash reports, identifiers, or any other data.

- No user accounts, no sign-in, no email address, no name.
- No analytics SDKs, no ad SDKs, no third-party SDKs of any kind.
- No crash reporting services.
- No advertising identifiers (IDFA, GAID, or similar) read or stored.
- No tracking across apps or websites.

## Data stored on your device

The app stores the following information locally on your device, only. It is never uploaded:

- Your current rating and rating history (Glicko-2 rating, uncertainty, volatility).
- Per-theme ratings.
- Puzzle attempt history (which puzzles you've seen, solve/fail outcome, first wrong move).
- Spaced-repetition review schedule (FSRS).
- A small preferences file: sound on/off, haptics on/off, auto-advance timing, onboarding status.

This data is written to the app's private sandbox directory as SQLite database files and a small text preferences file. It is visible to no other app or service.

If your operating system backs up app sandbox files as part of its normal device backup (iCloud on iOS, Google Backup on Android), your Chess Gym progress is included. You control this via your OS backup settings; Chess Gym does not opt you in or out.

## Right to delete

Settings → Reset progress wipes all of your locally-stored progress, immediately, on-device. There is no server-side copy to delete because there is no server.

## Network access

At runtime, the app makes no network requests. Puzzles are bundled with the app as a single SQLite asset (~1.7 MB); they load from disk.

Optional puzzle-database updates ship with new app versions through the App Store or Google Play — there is no in-app download mechanism.

## Children

Chess Gym is suitable for all ages. Because we collect no personal data, the Children's Online Privacy Protection Act (COPPA) and GDPR-K impose no substantive requirements on the app beyond this policy.

## Contact

- Questions: contact the developer through the app store listing.

## Changes

If this policy ever changes, a new version with an updated effective date will be published in the app's Settings → About screen. Because we collect no data, material changes to this policy would require us to collect data, which we have no intention of doing.
