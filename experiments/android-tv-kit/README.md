# Android TV kit (`tv.sh`)

A single bash script that cleans up and controls an Android TV, Google TV or Fire TV from your computer over ADB. You run it on a computer on the same home network as the TV. Every change it makes is reversible.

It was written for a **Sony BRAVIA running Android TV OS 10** (platform "BRAVIA 4K UR2", US/Canada firmware `BRAVIA_UR2_4K_UC`, build QTG3.200305.006). It works on macOS (including the built-in bash 3.2) and on Linux. On Windows, run it from WSL.

State, backups, screenshots and the command log live in `~/.tv-kit/`.

## 1. On the TV (remote control)

1. Press **HOME**, highlight the **gear (Settings)** icon at the top right and press the **center/OK** button.
2. Open **Device Preferences → About**.
3. Scroll down to **Android TV OS build** and press **OK 7 times**. A message appears: "You are now a developer".
4. Press **BACK**. In **Device Preferences** there is now **Developer options** near the bottom. Open it.
5. Turn **USB debugging** **On** and confirm. On Android 10, this setting also enables network ADB on port 5555.
6. Find the IP address: go to **Settings → Network & Internet** and select your connected Wi‑Fi or Ethernet. The address is shown as **IP address**. You can also find it under **Device Preferences → About → Status**.

The **Wireless debugging** menu and pairing codes only exist on Android 11 and later. Your TV runs Android 10, so it uses plain `connect`.

## 2. On the computer

```bash
cd experiments/android-tv-kit
./tv.sh install-adb            # only if adb is missing: Google's official platform-tools, unpacked into ~/.tv-kit
./tv.sh connect 192.168.1.50   # your TV's IP
```

When the TV shows **"Allow USB debugging?"**, tick **Always allow from this computer** and press **OK**.

- **Connection refused:** check that USB debugging is still on and that the IP is correct. On an Android 11+ device, use `./tv.sh pair IP:PORT` with the code shown under Wireless debugging.
- **macOS "No route to host":** go to System Settings → Privacy & Security → **Local Network** and turn on your terminal app, then retry.

## 3. Clean up (asks before changing anything)

```bash
./tv.sh plan    # read-only: writes ~/.tv-kit/plan.txt and prints it
./tv.sh apply   # takes a backup, then asks you to type YES
```

`apply` does the following:

- Runs `pm disable-user` on the apps in the plan. Nothing is uninstalled.
  - Selected by default are only identified ad, recommendation, feedback and demo packages: Android TV recommendations, Google Feedback, Retail demo and Sony Select.
  - Uncertain Sony packages, Play Music, Play Games and every other tile on your Apps screen (Freeplay, Fandango, ...) are listed **commented out**. Remove the `#` from a line only if you recognise the app.
  - Protected packages are refused even if you uncomment them: the launcher, Play Services and Play Store, keyboards and input, the remote, voice and Assistant, live TV, tuners, providers, setup, HDMI/CEC, networking, WebView, YouTube, and pay-TV provider apps such as Sling.
- Sets the window, transition and animator animation scales to **0.5**.
- Sets **Private DNS** to `dns.adguard-dns.com`. This blocks ad and tracker domains. If an ad-supported app stops working, run `undo`.

Before every change, the kit saves the full package lists, all settings, `getprop` and an `undo.sh` to `~/.tv-kit/backups/<time>/`.

## 4. Install an open-source app (official GitHub releases only)

```bash
./tv.sh install-tvbro                          # TV Bro browser, truefedex/tv-bro
./tv.sh install-github owner/repo              # any app that publishes .apk files on GitHub Releases
./tv.sh install-github owner/repo 'exact-asset-name.apk'   # when several APKs match
```

- The kit only downloads `https://github.com/<owner>/<repo>/releases/download/...` assets from the latest release.
- It picks the APK that matches the TV's CPU.
- It checks the file's SHA-256 against the digest GitHub publishes, when GitHub has one.
- After installing, it opens the app on the TV.
- `undo` uninstalls only apps that this kit newly installed.

## 5. Play a YouTube video

```bash
./tv.sh youtube --id https://youtu.be/VIDEO_ID   # exact video (most reliable)
./tv.sh youtube "lofi hip hop radio"             # search, check screen, press OK
```

The script sends real key presses (WAKEUP, HOME, OK) and opens YouTube. Then:

- **"Who's watching?" screen:** it selects the highlighted profile. It never signs in. If YouTube asks you to sign in, the script stops and you sign in yourself.
- **Search:** the script checks the screen before it presses OK. It first reads on-screen text from `uiautomator`. YouTube draws its UI as a web page, so that text is often empty. In that case it tries OCR if `tesseract` is installed. Otherwise it saves a screenshot and asks you to confirm with `y`.
- **Confirming playback:** it reads YouTube's media session (`state=3` means playing). It doesn't use screenshots for this because screenshots of a playing video are black (DRM).
- `--yes` skips the confirmation prompts.

## Live monitor

The terminal shows every command with a timestamp. While a TV-changing command runs, the TV's logcat streams underneath it, indented with `|` (warnings, plus activity and package events). Logcat stops when the command finishes. Everything is also appended to `~/.tv-kit/commands.log`.

To follow the log from a second window, run `./tv.sh monitor`. Set `TV_LOGCAT=0` to hide logcat.

## Cheat sheet

| Command | What it does |
|---|---|
| `./tv.sh connect IP` | connect (reconnects automatically later) |
| `./tv.sh status` | model, disabled apps, touched settings, memory, foreground app |
| `./tv.sh plan` / `apply` | propose / apply the cleanup |
| `./tv.sh backup` | snapshot only |
| `./tv.sh key HOME` | remote keys: `HOME BACK DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT DPAD_CENTER MEDIA_PLAY_PAUSE VOLUME_UP VOLUME_DOWN WAKEUP SLEEP` |
| `./tv.sh shot` | screenshot to `~/.tv-kit/shots/` |
| `./tv.sh youtube "words"` | search and play |
| `./tv.sh youtube --id URL` | play exact video |
| `./tv.sh install-tvbro` | install TV Bro |
| `./tv.sh monitor` | follow the command log |
| `./tv.sh undo` | revert everything |

## Undo

```bash
./tv.sh undo
```

This shows every recorded undo command and runs them newest-first after you type YES, which restores the original values. Each command is one of these:

- `pm enable <pkg>` for each disabled app
- `settings put global <key> <original>` (or `settings delete global <key>` if the setting didn't exist before) for each changed setting
- `uninstall <pkg>` for apps the kit installed

Each backup's `undo.sh` also runs on its own: `TV_SERIAL=IP:5555 bash ~/.tv-kit/backups/<time>/undo.sh`.

The same undo, by hand:

```bash
adb shell pm enable com.google.android.tvrecommendations   # per disabled app
adb shell settings put global window_animation_scale 1.0     # or the value in touched-settings.txt
adb shell settings put global transition_animation_scale 1.0
adb shell settings put global animator_duration_scale 1.0
adb shell settings put global private_dns_mode opportunistic # Android's default "Automatic"
```

On the TV itself, a disabled app can also be turned back on under Settings → Apps → *app* → Enable. Turning off USB debugging in Developer options stops all ADB access.

## Limits

- The script was tested only against a simulated `adb`, not against a real TV.
- Package names marked "guess" in the plan haven't been confirmed against a real Sony device, so they start commented out.
- The YouTube search path depends on how YouTube's app handles search links and where focus lands. The `--id` path is the dependable one.
