# Shift

iPhone jet-lag coach for timezone jumps. MVP is preloaded with Praveen’s **US trip 29 Aug–11 Sep 2026** (AMS → Miami → Atlanta → LA → SF → AMS).

Same TestFlight path as [Fitbit Health Sync](https://github.com/lefthandmagic/fitbit-health-sync): `xcodegen` + GitHub Action `iOS Release Upload` → App Store Connect.

**Not medical advice.** Light, sleep timing, and caffeine only. No melatonin protocol.

## What the MVP does

- **Today:** local vs body clock, next action, sleep window with weekday + time
- **Plan:** day-by-day schedule; tap a day for a full timeline
- **Trips:** multiple trips, duplicate/new, generate a schedule from the itinerary
- **Practical flight mornings:** wake is clamped so you can’t sleep in through a 10:30 departure
- **Notifications:** next 3 days of timed reminders
- **Home sleep:** default 23:00–07:00 Amsterdam; airport lead time editable
- **Itinerary:** edit stops, times, timezones, flights, and events. ATL → LAX is still a placeholder.

## Generate Xcode project

```bash
brew install xcodegen
xcodegen generate
open Shift.xcodeproj
```

Signing: team `DNQVHANQBU`, bundle `com.praveenmurugesan.Shift`.

## TestFlight

Internal only (Praveen). Do not add testers, groups, or a Public Link.

GitHub → Actions → **iOS Release Upload** → Run workflow (`upload_to_testflight = true`).

Create the App Store Connect **app record once** in the web UI (API keys cannot CREATE apps):

- https://appstoreconnect.apple.com → My Apps → **+** → iOS
- Name: **Shift Jet Lag** (`Shift` is taken on the App Store; the phone icon can still say Shift)
- Bundle ID: `com.praveenmurugesan.Shift`
- SKU: `shift-jetlag-001`

Then CI can fetch the profile and upload. Same secrets as Fitbit Health Sync.

Copy these repository secrets from `lefthandmagic/fitbit-health-sync` (or set them once at account level):

- `APPSTORE_KEY_ID`
- `APPSTORE_ISSUER_ID`
- `APPSTORE_PRIVATE_KEY`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`

No `BUILD_PROVISION_PROFILE_BASE64` — this workflow generates the Shift profile with `sigh`.
