# TV Home

An ad-free home screen for an Android TV: clock, date, weather, and big tiles
for a fixed list of apps, plus **All apps** and **Settings**. Plain Java, no
libraries, no tracking. Weather comes from [Open-Meteo](https://open-meteo.com)
(free, no account).

Each push to `main` builds the APK with GitHub Actions and publishes it under
[Releases](../../releases).

## Install (from any shell with adb, e.g. iSH)

```sh
curl -s https://api.github.com/repos/HipsterBwP/tv-home/releases/latest | grep -E '"(name|digest|browser_download_url)"'
curl -fLO <the .apk browser_download_url>
sha256sum tv-home-*.apk          # must equal the digest above
adb install -r tv-home-*.apk
```

## Make it the HOME button

```sh
adb shell cmd package set-home-activity io.github.hipsterbwp.tvhome/.MainActivity
adb shell input keyevent KEYCODE_HOME
```

If HOME still opens Google's screen, disable the stock launcher (reversible):

```sh
adb shell pm disable-user --user 0 com.google.android.tvlauncher
```

## Weather location

```sh
adb shell am start -n io.github.hipsterbwp.tvhome/.MainActivity --es place 74103   # ZIP or town
adb shell am start -n io.github.hipsterbwp.tvhome/.MainActivity --es units c       # Celsius
```

## Undo

```sh
adb shell pm enable com.google.android.tvlauncher
adb uninstall io.github.hipsterbwp.tvhome
```

The app list lives in `FAVORITES` in `MainActivity.java`.
