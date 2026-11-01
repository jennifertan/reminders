# Ringlet

A SwiftUI iOS reminders app: a day-by-day checklist of reminders, repeating schedules, a month
calendar, and alarms with snooze, auto-snooze, pre-alarms and critical alerts.

## Getting started

Open `Ringlet.xcodeproj` in Xcode 15.3 or later and run the `Ringlet` scheme. The app targets iOS 17.
To start the simulator with example reminders, add `-seedSamples` under the scheme's
Run > Arguments. In the app you can also load them from Settings or from the empty Days screen.

## What's where

- `Ringlet/Models/Schedule.swift` works out which days a reminder rings on (one-time, daily,
  weekly, monthly, yearly, wake-up alarm, cycle) and describes schedules in words.
- `Ringlet/Models/Planner.swift` turns reminders into the rings shown on each day, applying
  reschedules and done marks.
- `Ringlet/Models/Notifications.swift` queues local notifications, handles the Mark Done and
  Snooze buttons, and shows the full-screen alarm when Ringlet is open.
- `Ringlet/Sounds` holds the alarm sounds, made by `scripts/make-sounds.py`.

## TestFlight

Same setup as replanta: automatic signing with team `2C3UFXPB4P`, and `ExportOptions.plist`
uploads straight to App Store Connect.

Once, before the first upload:

1. In [App Store Connect](https://appstoreconnect.apple.com/apps), add a new iOS app named Ringlet
   with the bundle ID `au.com.ringlet`. If the bundle ID isn't in the list, build the app once in
   Xcode with your team selected and it will be registered automatically.

Each build:

```sh
./scripts/testflight.sh
```

Or in Xcode: Product > Archive, then Distribute App > TestFlight & App Store. The build number
goes up automatically on upload.

## Critical alerts

Reminders marked Critical Alert are sent as Time Sensitive, which gets through Focus modes. To also
ring when the phone is on silent, Apple has to grant the Critical Alerts entitlement
([request it here](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/)).
Once it's granted, add `com.apple.developer.usernotifications.critical-alerts` to
`Ringlet/Ringlet.entitlements` and set `hasCriticalAlertEntitlement` to `true` in
`Notifications.swift`.
