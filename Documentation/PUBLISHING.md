# Publishing checklist

What is ready for release, and what each store still needs. Items marked **you** cannot be done by a script (accounts, money, identity, a physical device or a Mac). Store rules change: check the current store documentation before paying or submitting.

## Ready now

- Application ID and bundle ID `com.flightsimaide.app`; display name "FlightSim Aide" on Android, iOS and Windows.
- Version `0.1.0+1` (`versionName` 0.1.0, `versionCode` 1). Raise the build number (`+n`) for every upload; a store never accepts the same one twice.
- Launcher icons for Android (adaptive, navy background), iOS (no alpha), Windows and macOS, from `assets/branding/`.
- Android: `INTERNET` permission; release signing reads `android/key.properties` (not in git), and a release build without it is signed with the debug key and is not uploadable.
- iOS: `ITSAppUsesNonExemptEncryption` = false (the app uses no encryption of its own).

## Before the first Android release

1. **You:** create the upload keystore once, outside the project, and back it up (a lost key means no updates with it). The command is in `android/key.properties.example`. Copy that file to `android/key.properties` and fill it in.
2. `flutter build appbundle --release` gives `build/app/outputs/bundle/release/app-release.aab`. `flutter build apk --release` gives an APK for a device test.
3. Check the signing: `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab` must NOT show "Android Debug".

## Google Play (Android)

- **You:** developer account (one-time fee, identity verification). New personal accounts may have to run a closed test with a minimum number of testers for a minimum number of days before they can publish: check the current rule first.
- Use Play App Signing: Google keeps the app signing key, you keep the upload key.
- Listing: title, short and full description, icon 512 x 512, feature graphic 1024 x 500, at least two phone screenshots (tablet screenshots too if listed for tablets).
- A **privacy policy URL** (a short static page, for example at `https://flightsimaide.com/privacy`), the **Data safety** form, the content-rating questionnaire, and a target audience. Current plan: the app collects no personal data and sends nothing to us.
- The app is only useful with a simulator and a companion plugin. In the review notes say so, and give the reviewer a way to see the app working (a short video, or a demo mode). An app that cannot be exercised by a reviewer can be rejected.
- Permissions are declared by the manifest: `INTERNET`, plus `ACCESS_WIFI_STATE` and `CHANGE_WIFI_MULTICAST_STATE` for finding a simulator on the Wi-Fi (the multicast beacon); list them in the review notes.

## Apple App Store (iOS) and macOS

Deferred: these builds need the MacBook (Xcode). What can be prepared on the PC is already set (bundle ID, display name, icons, encryption flag).

- **You:** Apple Developer Program (yearly fee). Register the bundle ID `com.flightsimaide.app`, then create the app record in App Store Connect (this also reserves the app name).
- When the networking code arrives: `NSLocalNetworkUsageDescription` (and the Bonjour service list if used) in `Info.plist`, with a clear sentence about why the app looks for the simulator on the local network.
- A privacy manifest (`PrivacyInfo.xcprivacy`) and the App Privacy answers (no data collected, same as above).
- Screenshots for the required device sizes, the 1024 x 1024 icon (already generated, no alpha), the privacy policy URL, support URL, age rating.
- Review notes as for Google Play: the reviewer has no simulator. Provide a demo video, or a demo mode, and explain the companion plugin.

## Windows (optional, outside the stores)

`flutter build windows --release` gives a folder under `build/windows/x64/runner/Release/`. A GitHub release zip is enough for the sim community. The Microsoft Store (MSIX) is a separate, optional step.

## Still to decide

- Privacy policy text and where it is hosted.
- Real screenshots, which wait for the app itself.
