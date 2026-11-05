# Releasing ownit2buildit on Google Play

Step by step, in the order to do it. Tick each box as you go. Things marked **(you)** only you can
do; the rest is already done in this repository.

Last checked: 2026-11-03. Google changes the Play Console and its rules often, so where a step says
"check", read what the Console shows you now.

## What is already prepared in the repository

| Done | Where |
|---|---|
| Release signing wired to an upload key kept outside the repo; a bundle build **refuses** to run without one, so a debug-signed bundle can never be made by accident | `android/app/build.gradle.kts` |
| Target SDK 36 / compile SDK 36 / minimum Android 7.0 (API 24), set by Flutter, meet Google's current target-API rule | Flutter SDK defaults |
| R8 code shrinking and resource shrinking are on for release (Flutter's default) | Flutter Gradle plugin |
| `INTERNET` permission declared in the main manifest (a release build has none otherwise) | `AndroidManifest.xml` |
| Android auto-backup turned off, so a restored backup cannot break sign-in (secure storage keys do not travel with backups) | `AndroidManifest.xml` |
| Production API is the default: `https://api.ownit2buildit.com/api/v1` (HTTPS only) | `lib/core/config/app_config.dart` |
| Launcher icons (adaptive + themed) from the logo | `tool/make_app_icons.py` |
| Play Store icon (512 px) and feature graphic (1024 x 500) | `store/google-play/`, `tool/make_store_graphics.py` |
| Listing text, limits checked | `store/google-play/listing.md`, `tool/check_listing.py` |
| Privacy policy page, with a deletion section | web app `/privacy-policy` and `/privacy-policy#delete-your-data` |
| The "subscription expired" screen no longer tells people where to pay (Google's payments policy dislikes pointing away from Play to buy) | `status_screens.dart` |

## Step 0. Decisions that cannot be changed later

- [ ] **Application ID.** It is `com.ownit2buildit.builder_pro_mobile`. After the first upload it is
  permanent. It works, but `builder_pro_mobile` is a template leftover. If you want something
  cleaner (for example `com.ownit2buildit.app`), decide **now**: change `applicationId` in
  `android/app/build.gradle.kts`, register the new package in the Firebase console, run
  `flutterfire configure` again (it rewrites `google-services.json` and `lib/firebase_options.dart`),
  and tell me so I can check it. Keeping the current one is fine and needs nothing.
- [ ] **App name.** "ownit2buildit" (max 30 characters). It can be changed later.
- [ ] **Free app.** A free app can never be changed to a paid one. This app is free to download;
  companies pay for the service on the web (the app sells nothing, so it does not need Google Play
  Billing).
- [ ] **Account type (you).** *Personal* or *Organization*. Organization needs a D-U-N-S number
  (free, can take a few weeks). Personal accounts created recently must run a **closed test with
  at least 12 testers for 14 days in a row** before they can publish. Organization accounts skip
  that. Check the Console for the current rule.

## Step 1. Make the server side ready

The app is only as good as the server it talks to. Do this before testers install it.

- [ ] Deploy the backend changes B1 to B12 from `builder-pro-back` (uncommitted today; you decide
  when). Without them several screens say "Not available on your server yet" (money detail pages,
  chat uploads and voice, notification switches).
- [ ] Run the SQL files: `add-device-tokens.sql` (push), `add-message-extras.sql` (replies and
  mentions), `add-notification-preferences.sql` (alert switches).
- [ ] Set `FIREBASE_SERVICE_ACCOUNT` on the server. **Revoke and regenerate** the Firebase key that
  was pasted into a chat earlier, and delete the old JSON file from the repository folder.
- [ ] Run the server on a persistent host (PM2) so sockets and the alert jobs run.
- [ ] Open `https://api.ownit2buildit.com/api/v1` in a browser or with curl and confirm it answers
  over HTTPS with a valid certificate. A release app refuses plain HTTP.
- [ ] Deploy the web app so the **privacy policy is live** at your public address +
  `/privacy-policy`. Open it in a private window. Google checks the link.
- [ ] Create a **review account** for Google's reviewers: a user in a demo company with sample
  data, a broad role (owner or project manager) so every screen can be seen, and an **active
  subscription that will not expire**. Otherwise they land on the "subscription" screen and reject
  the app. It must not need a code sent to a phone or email you cannot receive.

## Step 2. Create your upload key (you, once)

The upload key proves that uploads come from you. Google keeps the real app-signing key
(**Play App Signing**, on by default), so losing the upload key is recoverable, but slow.

In PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\keys"
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v `
  -keystore "$env:USERPROFILE\keys\ownit2buildit-upload.jks" `
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks for a password (twice), then your name and organisation (any sensible values). Remember
both passwords.

- [ ] **Back up** the `.jks` file **and** both passwords in two places (a password manager and an
  offline drive). Never put them in the repository, an email or a chat.
- [ ] Create `builder-pro-mobile\android\key.properties` (it is git-ignored; use forward slashes in
  the path):

```properties
storeFile=C:/Users/bless/keys/ownit2buildit-upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
```

## Step 3. Set the version, build, and test the release build

- [ ] Version lives in `pubspec.yaml`: `version: 1.0.0+1` means name `1.0.0` (shown to people) and
  build number `1` (what Google compares). **Every upload needs a higher build number.** First
  upload: leave it as `1.0.0+1`. Later: `1.0.1+2`, `1.0.2+3`, and so on.
- [ ] **Install the Android SDK command-line tools (you).** `flutter doctor` currently reports
  "cmdline-tools component is missing" and "Android license status unknown". Without them
  `flutter build appbundle` still writes the `.aab` but ends with the error "Release app bundle
  failed to strip debug symbols" and exit code 1, because Flutter cannot run its check. Fix:
  Android Studio > Settings > Languages & Frameworks > Android SDK > *SDK Tools* tab > tick
  **Android SDK Command-line Tools (latest)** > Apply. Then run `flutter doctor --android-licenses`
  and accept everything. Run `flutter doctor` again until the Android line is clear.
- [ ] Free about 10 GB on C: first (this machine is nearly full: the test build below took it from
  15 GB free to 5.8 GB, mostly Gradle's cache) and close other heavy programs. The Gradle settings
  are sized for 8 GB of RAM. The first build took about 11 minutes.
- [ ] Build the bundle:

```powershell
cd C:\Users\bless\Documents\me\BuilderPro\builder-pro-mobile
flutter build appbundle --release
```

  Result: `build\app\outputs\bundle\release\app-release.aab`. If it stops with "No upload key",
  `key.properties` is missing or incomplete.
- [ ] **Test the release build on your phone before uploading.** The release build is shrunk by R8, so
  it can behave differently from the debug app you have been running:

```bash
flutter build apk --release
adb uninstall com.ownit2buildit.builder_pro_mobile
adb install build/app/outputs/flutter-apk/app-release.apk
```

  (Use forward slashes: they work in both PowerShell and Git Bash, whereas Git Bash swallows
  backslashes and `adb` then reports a file name with the slashes missing.)

  (The uninstall is needed because the release key differs from the debug key; it clears the
  app's local data.) Then check: sign in, close and reopen (still signed in), a push alert
  arrives, photo from camera and from gallery, a file upload, a voice message, clock in with
  location on and off, Gantt chart, light and dark mode, sign out. Anything that works in debug but
  not here is an R8 problem. To capture it, run `adb logcat -c`, repeat the action that fails,
  then `adb logcat -d -s AndroidRuntime:E flutter:V > logcat.txt` and send me that file; I will
  add keep rules.
- [ ] Optional: `--obfuscate --split-debug-info=build\symbols` makes the app harder to read. If you
  use it, keep the `build\symbols` folder for every release; without it crash traces cannot be
  decoded. Skip it for the first release.

## Step 4. Create the Play Console account and the app (you)

- [ ] Go to <https://play.google.com/console>, sign in with the Google account that will own the
  app long-term (use a company account, not a personal one that might be closed), and pay the
  one-time registration fee (about US$25).
- [ ] Verify your identity (government ID; for an organization, the D-U-N-S details). Verification
  can take days.
- [ ] **Create app**: name `ownit2buildit`, default language English, type *App*, *Free*, tick the
  declarations.

## Step 5. App content declarations (Console: Policy > App content)

Every item must be finished before you can publish.

- [ ] **Privacy policy**: your public web address + `/privacy-policy`.
- [ ] **App access**: "All or some functionality is restricted". Add the review account from Step 1
  (email, password, and a line: "Sign in with these details. The account has the Owner role.").
- [ ] **Ads**: the app contains no ads.
- [ ] **Content rating**: answer the questionnaire honestly. Category: *Utility, productivity,
  communication or other*. Users can talk to each other (chat) and a manager can see where a
  worker clocked in, so tick the user-interaction and location items where they apply.
- [ ] **Target audience**: 18 and over only. Not designed for children.
- [ ] **News app**: no. **Government app**: no. **Health**: no.
- [ ] **Financial features**: the app tracks a company's own budgets, costs, quotes and invoices; it
  does not lend, hold money or process payments. Choose that no financial features are offered,
  unless the Console's current wording says otherwise.
- [ ] **Advertising ID**: the app does not use it (answer No). The release build does not request
  the ad-ID permission (see Verified build results).
- [ ] **Data safety**: see the table below.
- [ ] **Account deletion**: the app has no sign-up inside it (accounts come by invitation), but give
  the web address `.../privacy-policy#delete-your-data` wherever the Console asks for a
  deletion page. Note that this currently means "email us" (backend gap G86).

### Data safety answers (a draft: check each line against the form)

All data is encrypted in transit (HTTPS). Users can ask for their data to be deleted. Nothing is
sold. Passing data to our own service providers to run the app (Google Firebase for alerts, our
server hosting and email) is "processing on our behalf", not "sharing", under Google's definition.

| Data type | Collected | Shared | Required? | Why |
|---|---|---|---|---|
| Name | Yes | No | Required | App functionality, account management |
| Email address | Yes | No | Required | App functionality, account management |
| Phone number | Yes | No | Optional | Account management, contacting team members |
| Precise and approximate location | Yes | No | **Optional** | App functionality (where you clocked in or out) |
| Photos | Yes | No | Optional | App functionality (attach to tasks, documents, chats) |
| Voice or sound recordings | Yes | No | Optional | App functionality (voice messages) |
| Files and docs | Yes | No | Optional | App functionality |
| In-app messages | Yes | No | Required to chat | App functionality |
| Other financial info (budgets, costs, invoices, payment records the company enters) | Yes | No | Required to use finance features | App functionality |
| Other user-generated content (tasks, comments, notes) | Yes | No | Required | App functionality |
| Device or other IDs (the alert token) | Yes | No | Optional | App functionality (push alerts) |

Not collected: contacts, calendar, web browsing, health, advertising data, crash or diagnostics
data (the app has no crash-reporting tool).

## Step 6. Store listing (Console: Grow > Store presence > Main store listing)

- [ ] **App name, short description, full description**: paste from `store/google-play/listing.md`.
  Run `python tool/check_listing.py` after editing it.
- [ ] **App icon**: `store/google-play/icon-512.png`.
- [ ] **Feature graphic**: `store/google-play/feature-graphic-1024x500.png`.
- [ ] **Phone screenshots (you)**: at least 2, up to 8. Suggested: Today, My tasks (Gantt), a
  project, Clock, Finance, a chat. **Use the demo company, never real clients' names or figures.**
  Take them on your phone (power + volume down). If the Console rejects the shape (the long side
  may be at most twice the short side; your Pixel's screen is slightly longer), crop a little off
  the top and bottom.
- [ ] Tablet screenshots are optional.
- [ ] **Category**: Business. **Contact email**: a monitored address (shown publicly). **Website**:
  your public web address.

## Step 7. Test, then publish (Console: Testing and release)

1. [ ] **Internal testing**: *Create new release*, upload `app-release.aab`, accept Play App
   Signing, add release notes, *Save*, *Review release*, *Start rollout*. Add testers (email
   list), copy the opt-in link, and install the app from Play on a real phone. This is the first
   time the exact file Google will serve is tested, and it is available within minutes.
2. [ ] Fix anything found. Each new upload needs a higher build number (Step 3).
3. [ ] **Closed testing** (required first if your account type needs it): at least 12 testers opted in
   for 14 days in a row, then *Apply for production* on the dashboard.
4. [ ] Read the **Pre-launch report** the Console makes for each upload: crashes on Google's test
   devices, accessibility notes.
5. [ ] **Production**: *Create new release* (promote the tested build), choose countries, release
   notes, and start with a **staged rollout** (for example 20%) so a problem reaches few people.
6. [ ] Wait for review (a few hours to several days for a new account). Fix anything the review
   asks for and resubmit.

## After release

- Every update: raise the build number, build, test, upload to internal testing, then promote.
- Old app versions stay on phones for a long time. Keep the API compatible with them (the app
  already copes with an older server by hiding or explaining what it cannot do).
- Watch **Android vitals** (crashes, slow starts) and the **Reviews** page.
- iOS is separate: it needs a Mac, an Apple developer account (US$99 a year), the APNs key
  uploaded in Firebase and the Push capability. Nothing here covers it.

## Known risks and loose ends

- **Never run on a device or against the live server** until you do Step 3. Several features
  (money detail pages, chat uploads, voice, notifications, the Gantt layout) were built and
  analysed but not exercised end to end.
- The statements in the privacy policy about alerts and chat privacy need backend B12 and B11
  deployed.
- The privacy policy and the Terms promise deletion 90 days after an account closes; nothing
  performs that automatically (backend gap G86).
- Flutter warns that the `firebase_core` plugin still uses the old Kotlin plugin; a future Flutter
  will refuse such plugins. Upgrade the Firebase packages when a compatible version is out.
- Contact addresses, the 30-day reply promise and the regulator named in the privacy policy have
  not been confirmed by you.

## Verified build results

On 2026-11-03 a release bundle was built with a **throwaway** key (since deleted, along with
that bundle, so it can never be uploaded by mistake). What it showed:

- **The Gradle build succeeds** (about 11 minutes) with R8 code shrinking and resource shrinking
  on. The bundle is 69.9 MB with all three ABIs; Google delivers a smaller, per-phone download.
- **Signing works**: the bundle was signed with the key named in `android/key.properties`, and a
  bundle build without that file is refused with a clear message.
- **16 KB pages**: every 64-bit native library (arm64-v8a, x86_64) is aligned for 16 KB pages, as
  Google now requires. Check any bundle with `python tool/check_bundle.py`.
- **Permissions in the release manifest**: internet, network state, wake lock, fine and coarse
  location (while in use only: no background location), notifications, microphone, and the
  Firebase receive permission. No storage, contacts, phone, SMS or advertising-ID permissions, so
  no permission declaration form should be needed and "Advertising ID: No" is correct.
- **Debug symbols** were stripped and filed in the bundle's metadata for Google Play, so crash
  reports from Play can be decoded without extra work.
- **Flutter exited with an error** only because the SDK command-line tools are missing (Step 3).
  The bundle itself was complete.
- **Not verified**: that the release build *runs* correctly on a phone. That is the test in
  Step 3 and nothing here replaces it.
