# Paladin Guard RolePlay — Android Launcher 0.1.0

Native Android companion launcher (Java, no third-party UI libraries). Works on Android 8+ (API 26+).

## Implemented
- Dedicated PGRP dark-navy / gold / cyan UI and shield app icon
- Live **read-only** UDP SA-MP/open.mp info query for `46.38.138.33:7777`
- Accurate player count/max players and UDP RTT only when server replies
- Refresh every 30 seconds or on tap
- Locally saved player nickname
- Copy server address and optional `samp://46.38.138.33:7777` deep-link integration
- Installation/help dialog and website shortcut
- JUnit tests for server info protocol, bounds and malformed response
- Dedicated GitHub Actions Android APK build, independent from stable PC release

## What is deliberately NOT included
- GTA San Andreas copyrighted assets or a native Android GTA engine
- A proprietary/unlicensed SA-MP mobile game client or stolen code
- Unverified direct-launch integration with individual third-party mobile clients
- Backend registration, account passwords, native mobile voice, or gameplay
- False "offline" indication when UDP query is disabled

## Build
1. Install Android Studio and Android SDK platform 35, JDK 17.
2. Open `android-launcher` as a Gradle project, then sync.
3. Execute `gradle testDebugUnitTest assembleDebug` in this directory.
4. Install `app/build/outputs/apk/debug/app-debug.apk` on Android 8+.
5. Release builds require a proper Android signing keystore and secure CI secrets; never commit signing secrets.

## Run
1. Get the APK from the GitHub release.
2. Enable installation from the chosen trusted browser/files app once, then install APK.
3. Open PGRP, enter a Latin nickname, and tap connect.
4. If no Android SA-MP client handles the `samp://` URI, IP is copied. In a separately installed reputable mobile client, add `46.38.138.33` port `7777` to favorites.
5. The PGRP game server must **actually accept and implement mobile clients** for gameplay to work. Open.mp/Windows clients do not become Android-compatible merely by building an Android launcher.

## Next development steps
- Test a particular legally obtained Android SA-MP client and its documented deep-link integration.
- Validate server game mode's login/dialogs/HUD against touch controls and mobile protocol versions.
- Build a server-hosted, signed manifest for safe news and update notices.
- QA on actual Android 8/10/13/15 devices; add Android app signing for distribution.
