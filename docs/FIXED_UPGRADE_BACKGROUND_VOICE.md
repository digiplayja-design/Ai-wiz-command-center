# Fixed plans action and Rici background voice

Requested by Ricardo on October 18, 2026, after successful build 134.

The signed-in home reserves space above its scrolling content for account,
sound, welcome, sign-out and the plans action. Basic/Pro show Upgrade;
Ultra/Enterprise/developer accounts show My Plan; unknown tiers show View Plans.
The existing native store or web billing screen owns pricing and purchases.
The welcome screen has a public plans overview and a free-registration action.
The Basic ad banner now reserves bottom space instead of covering content.

Live Convo acquires the existing native foreground audio lease after the user
starts voice and grants microphone permission. Android uses the existing
microphone/mediaPlayback service, with a Rici notification, MediaSession and
Stop control. iOS already declares the audio background mode and WebRTC owns
its play-and-record session; the Rici lease adds Control Center/lock-screen
stop controls without reconfiguring or deactivating another tool's audio.

Active voice, including an unmuted microphone, can continue under device lock.
The screen explains this before Start. Mute remains muted; Pause, Stop, account
change, failed connection and disposal release the lease. A denied/failed
native lease falls back to foreground voice and closes the session when hidden.
Unlocking never reconnects a stopped session automatically. The app's visual
smoke screensaver keeps the existing media and session mounted. Browser device
lock behavior remains dependent on the browser/OS and is not guaranteed.

This change applies to LIVE CONVO/Rici voice sessions. The short, optional
welcome recording retains its existing stop-on-navigation/background behavior.
Neither this source update nor a successful build establishes store publication.

## Release validation

- Automated: fixed toolbar at 320 px and 200% text, scrolling/tier/busy states,
  public plans, onboarding/billing regressions, production Live Convo device
  lock/Stop/mute/fallback paths, visual smoke screensaver, cancelled native
  startup, existing account-change and device cleanup regressions.
- Android device: start an audible reply, lock for at least two minutes, verify
  uninterrupted speech and an accurate notification. Check Bluetooth, Mute,
  Stop from notification/lock screen, denied notifications, incoming phone call,
  network loss, account change and swipe-away cleanup. No spontaneous restart.
- iOS device: repeat on the signed build with screen lock, Control Center Stop,
  Bluetooth and phone interruption. Existing background-mode declarations alone
  do not establish on-device success.
- Store checks: current plan/price, upgrade confirmation, restore purchase,
  Ultra/developer My Plan, narrow layout and large accessibility text.

Build from the exact reviewed commit using the existing signed Codespace and
saved public client config. Check all Play tracks/drafts for the next unused
version code. Preserve the browser-download method: serve only the completed
AAB from a private forwarded port with Content-Disposition attachment, then
save it to the iPad Files app. Do not serve the repository or signing files.

## Save the completed bundle from the browser

After the signed build succeeds, use the printed Build folder as `SOURCE` and
its actual build number as `BUILD`. These commands run in the Codespace terminal:

```bash
SOURCE=/tmp/korlix-play-billing-BUILD.ACTUAL_SUFFIX/source
BUILD=135 # replace with the number confirmed in your successful build output
python3 "$SOURCE/scripts/download-android-aab.py" \
  "$SOURCE/build/app/outputs/bundle/release/app-release.aab" \
  --build-number "$BUILD" --port 8789
```

Keep the terminal running. In **Ports**, forward **8789**, leave it **Private**,
and select **Open in Browser**. Tap **Download KORLIX-…aab** and choose
**Save to Files → Downloads → Save**. If Chrome shows a preview, use its Share
menu and **Save to Files**. After the save completes, stop the server with Ctrl+C.
The server exposes only the selected AAB and its download page. It never
provides a repository directory listing. Use another private port if 8789 is busy.
