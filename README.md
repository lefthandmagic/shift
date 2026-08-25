# Shift

iPhone jet-lag coach for timezone jumps. MVP is preloaded with Praveen’s **US trip 29 Aug–11 Sep 2026** (AMS → Miami → Atlanta → LA → SF → AMS).

Same TestFlight path as [Fitbit Health Sync](https://github.com/lefthandmagic/fitbit-health-sync): `xcodegen` + GitHub Action `iOS Release Upload` → App Store Connect.

**Not medical advice.** Light, sleep timing, and caffeine only. No melatonin protocol.

## What the MVP does

- **Today:** local time vs body clock, next action, sleep window, light seek/avoid, caffeine cutoff
- **Plan:** day-by-day shift (westbound delay, eastbound advance, flight days)
- **Notifications:** next 3 days of timed reminders (once you allow them)
- **Home sleep:** default 23:00–07:00 Amsterdam, editable
- **KATSEYE 11 Sep 20:00** is baked in so landing-day bedtime sits after the show

## Generate Xcode project

```bash
brew install xcodegen
xcodegen generate
open Shift.xcodeproj
```

Signing: team `DNQVHANQBU`, bundle `com.praveenmurugesan.Shift`.

## TestFlight

GitHub → Actions → **iOS Release Upload** → Run workflow (`upload_to_testflight = true`).

First run also creates the App Store Connect app + distribution profile via the App Store Connect API (same secrets as Fitbit Health Sync).

Copy these repository secrets from `lefthandmagic/fitbit-health-sync` (or set them once at account level):

- `APPSTORE_KEY_ID`
- `APPSTORE_ISSUER_ID`
- `APPSTORE_PRIVATE_KEY`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`

No `BUILD_PROVISION_PROFILE_BASE64` — this workflow generates the Shift profile with `sigh`.
