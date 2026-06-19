# Offline and privacy

What the app does and does not do with respect to the network, data collection, and the player's identity.

## Offline-first

The app works fully offline, forever, with no feature loss. Specifically:

- All puzzles ship bundled as an asset. No download on first run.
- No runtime engine, no cloud eval, no move validation round-trips.
- No telemetry. No crash reporter. No analytics SDK.
- No social features. No accounts. No server.

The only network access the app may make is:

- Optional in-app database updates (a replacement `puzzles.sqlite` via App Store / Play Store app update; not a separate download).

There is no background network activity at any time.

## Privacy

No personal data is collected. No identifiers beyond what the OS provides to every app. No ad SDKs. No third-party SDKs of any kind at launch.

Player rating, review queue, and preferences live in a local SQLite file in the app's sandbox. If the OS provides an encrypted backup mechanism that backs up app sandbox files by default (iCloud on iOS, Google Backup on Android), the player's progress rides along with it — opt-out is via the OS, not the app.

The app's privacy policy text, mandatory for store submission, says exactly this: "This app collects no data."

## Children and COPPA / GDPR-K

Because no data leaves the device, COPPA and GDPR-K have no substantive requirements for this app beyond the privacy policy statement.

## Accounts, sharing, cloud sync

None at launch. A future version may add optional iCloud / Google Drive sync of the local state file, user-initiated, with the same "no server in between" property. Not in scope for MVP.

## Right to delete

Settings contains a **Reset** action that wipes all player state. Because nothing leaves the device, this is a true right-to-delete.
