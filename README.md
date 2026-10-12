# Light Minute

A focus timer for iOS. Pomodoro when you want structure, flow state when you don't —
and when you overrun, the rest you've earned scales with the work you did.

Built in SwiftUI, rendered in a monochrome pixel style, with a timer large enough to
read from across the room.

---

## What it does

**Flowmodoro.** The focus timer doesn't stop at 25 minutes. If you're in it, keep
going — the clock keeps counting and nothing interrupts you.

**Proportional rest.** Rest is earned, not fixed. Overrun your focus target and the
break grows with it: short breaks accrue at 5:1, long breaks at 25:20. Work 30 minutes
against a 25-minute target and you get 6 minutes, not 5.

**Daily target.** Set how many focus sessions the day owes you. The count tracks
against it and resets itself at midnight — yesterday's effort doesn't carry forward,
and neither does yesterday's shortfall.

**Flip focus.** Put the phone face down and the timer starts. Turn it back over to
look at it and the timer stops — and MIKE has something to say about that.

**Live Activity.** Rest periods shrink into the Dynamic Island and keep running while
the app is backgrounded or killed. Timekeeping is anchored to wall-clock time, so
suspension, backgrounding and termination can't make the clock drift.

**Stays awake.** The screen won't lock while a timer is running.

**App blocking.** A Screen Time shield over apps you choose, held until the day's
target is met. **Present in the code but not functional in this build** — see
[Screen Time](#screen-time-blocking-not-currently-functional) below.

---

## Design

The interface follows **Diurnal UI**, which is not a light/dark theme in the usual
sense.

It's monochrome. There is no accent colour and nothing is colour-coded, so emphasis
has to come from contrast and elevation instead — a warning doesn't turn red, it
comes forward in ink.

The light is literal. Light mode is lit by the sun; dark mode by the full moon, which
sits at the sun's antipode — rising at sunset, peaking at midnight, setting at dawn.
The interface is treated as a flat surface seen from above, north up. Solar position
is computed from the NOAA low-precision algorithm, the light is placed at its real
compass bearing, and every shadow falls away from it: a low light casts long shadows,
a high one short.

One light state is computed per instant and broadcast through a SwiftUI
`EnvironmentKey`, so every shadow on screen agrees about where the light is.

Dark mode is the default.

Typography is **Press Start 2P**, registered at runtime via
`CTFontManagerRegisterFontsForURL`.

> **Known deviation:** Diurnal UI specifies Libre Baskerville and IBM Plex Mono.
> This app deliberately uses Press Start 2P instead, to match the original Figma
> design. The light model and monochrome rules are followed; the typography is not.

---

## Layout

```
LightMinute/
├── LightMinute/
│   ├── LightMinuteApp.swift          App entry; registers the pixel font
│   ├── ContentView.swift             Root; injects the sky, owns scene phase
│   ├── Design/
│   │   ├── DiurnalLight.swift        Solar position → shadow geometry
│   │   ├── DiurnalElevation.swift    Shadow ViewModifier, generic over InsettableShape
│   │   └── Theme.swift               Adaptive colours via UIColor(dynamicProvider:)
│   ├── Models/
│   │   ├── TimerState.swift          Settings + DailyProgress (midnight rollover)
│   │   └── RestActivityAttributes.swift
│   ├── Services/
│   │   ├── RestLiveActivity.swift    ActivityKit wrapper
│   │   └── AppBlocker.swift          FamilyControls + ManagedSettings shield
│   ├── ViewModels/
│   │   └── TimerViewModel.swift      Wall-clock anchored timekeeping
│   ├── Views/                        MikeHeader, PixelButton, PixelTimer,
│   │                                 SessionDots, Settings
│   └── Resources/
│       └── PressStart2P-Regular.ttf  The only bundled resource
└── LightMinuteWidget/
    ├── LightMinuteWidgetBundle.swift
    └── RestLiveActivityWidget.swift  Live Activity only — no home-screen widget
```

`Figma/` holds the original design exports.

---

## Building

**Requires** Xcode 26.2, iOS 17.0+, Swift 5 language mode.

1. Open `LightMinute/LightMinute.xcodeproj`.
2. Set your own team under Signing & Capabilities, and change the bundle identifier
   from `com.lightminute.app` — it's already taken.
3. Select the **`LightMinute`** scheme and run.

> **Pick the right scheme.** Running the `LightMinuteWidget` scheme fails with
> `Failed to show Widget … RequestDenied`. That's not a bug: the extension vends an
> `ActivityConfiguration` (a Live Activity) and no `StaticConfiguration`, so there is
> no home-screen widget for SpringBoard to place. The extension is embedded in the app
> automatically — never run it directly.

### On a free Apple ID

Workable, with two frictions:

- The app won't launch until you trust the certificate on the device:
  **Settings › General › VPN & Device Management**.
- Provisioning profiles last **7 days**, not a year. After that the app refuses to
  open until it's rebuilt and reinstalled.

---

## Screen Time blocking (not currently functional)

`Services/AppBlocker.swift` implements an app shield with FamilyControls and
ManagedSettings: the user picks apps through Apple's `FamilyActivityPicker`, and a
`ManagedSettingsStore` shield stays up until the day's target is met. The shield lives
in the system rather than the process, so it survives the app being backgrounded,
suspended or killed.

**It does not work on a free Apple Developer Personal Team**, and the failure mode is
confusing enough to be worth documenting.

### The symptom

The picker opens and lists categories — Social, Games, Entertainment — and expanding
any of them shows **zero apps**. No error, no prompt, no explanation.

That's what an unauthorized picker looks like. `FamilyActivityPicker` is a system view
rendered out-of-process, so it presents for anyone who asks; but enumerating installed
apps is privacy-sensitive and iOS will only do it for an app holding Screen Time
authorization. **An empty accordion is the tell. A picker that opens is not evidence
that Family Controls works.**

### The cause

Family Controls requires the `com.apple.developer.family-controls` entitlement, and a
free Personal Team cannot enable that capability. Adding it to `CODE_SIGN_ENTITLEMENTS`
doesn't fail at runtime — it fails the **build**, and takes the whole app down with it:

```
error: Provisioning profile "iOS Team Provisioning Profile: com.lightminute.app"
       doesn't include the Family Controls (Development) capability.
```

Note that the constraint is the *account tier*, not the fact that it's a development
build. Development builds use Family Controls routinely; paid accounts get the
development entitlement automatically through Xcode, with no review. Apple's approval
is only needed to ship it to other people.

`LightMinute.entitlements` is kept in the repo but deliberately **not** referenced by
any build configuration.

### Re-enabling it

With a paid Apple Developer Program membership:

1. Enable **Family Controls** on the App ID in the developer portal (or add the
   capability in Xcode's Signing & Capabilities, which does it for you).
2. Add this line back to both app build configurations in `project.pbxproj`:
   ```
   CODE_SIGN_ENTITLEMENTS = LightMinute/LightMinute.entitlements;
   ```
3. Rebuild. `AppBlocker` detects the entitlement at launch and the UI enables itself.

### How to verify it on hardware

The app reads its own `embedded.mobileprovision` at launch and writes the result to
its Documents directory, which can be pulled off a development-signed device without
any taps:

```bash
xcrun devicectl device copy from --device <device-uuid> \
  --domain-type appDataContainer --domain-identifier com.lightminute.app \
  --source Documents/screentime-diagnosis.txt --destination ./diag.txt
```

A build without the entitlement reports:

```
launch | status=notDetermined | entitlementInBinary=false
```

> This instrumentation (`Diagnostics` in `AppBlocker.swift`) is temporary and should
> be removed once the entitlement question is settled for good.

---

## Degraded and unbuilt

Honest list of what isn't finished.

| | |
|---|---|
| **App blocking** | Code complete, inert without the entitlement. The UI reports `NOT ENFORCED` rather than pretending. |
| **Midnight re-arm** | The shield lifts when the target is met but won't re-arm at midnight on its own — that needs a `DeviceActivityMonitor` extension. |
| **Shield screen** | Blocked apps show Apple's stock shield, not a Diurnal-styled one. Needs a `ShieldConfiguration` extension. |
| **Toggle bypass** | BLOCK APPS is a one-tap escape hatch. A real commitment device would resist being switched off. |
| **Weather** | Diurnal softens shadows under cloud. Not implemented — needs real weather data. |
| **Location** | Longitude is approximated from the device's UTC offset and latitude is fixed at 20°, so shadow bearings are roughly right and precisely wrong. |
| **Typography** | Press Start 2P instead of the system's Libre Baskerville / IBM Plex Mono — deliberate, see above. |

---

## Credits

Design derived from the Light Minute Figma file. Typeface:
[Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) by CodeMan38,
SIL Open Font License.
