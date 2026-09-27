# Firebase Setup — Cross-Device Sync

Firestore provides cross-device sync for team records and real-time team
chat. Notebook entries, inventory, and match-scouting observations are
stored locally first and pushed to Firestore when the app is configured.
Everything below is done in a browser — no Mac needed for this part.

## 1. Create a Firebase project

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and sign in with any Google account.
2. Click **Add project**, name it something like `ftcteamhub-24211`, and finish the wizard (Google Analytics is optional — you can skip it).

## 2. Register your iOS app

1. In the project, click the iOS icon ("Add app").
2. For **iOS bundle ID**, enter exactly: `com.ftcteamhub.app` — this must match the `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
3. Skip the App Store ID field.
4. Click **Register app**.

## 3. Download the config file

1. Firebase will offer to download `GoogleService-Info.plist`. Download it.
2. Upload it to your GitHub repo at exactly: `FTCTeamHub/GoogleService-Info.plist` (same folder as your other source files).

## 4. Enable Firestore

1. In the Firebase console left sidebar, click **Build → Firestore Database**.
2. Click **Create database**.
3. Choose **Start in test mode** only for initial setup verification. Test-mode rules allow unauthenticated access and expire; do not use real team data or distribute the app while access is open.
4. Pick any region close to you and click **Enable**.

## 5. Confirm your repo has everything

Your repo should now include:
- `project.yml` (updated — already declares the Firebase Swift Package dependency)
- `FTCTeamHub/GoogleService-Info.plist` (the file you just downloaded)
- `FTCTeamHub/Services/FirebaseSyncService.swift`
- Updated `FTCTeamHub/App/FTCTeamHubApp.swift`

## 6. Re-run the build

Go to **Actions → Build Unsigned IPA → Run workflow**. The first build after adding a Swift Package dependency takes noticeably longer (5–10 min instead of 2–3) since GitHub Actions has to resolve and compile the entire Firebase SDK — this is normal, not a stall.

## Security note

The app's current email/password account system is local to the app and is
not Firebase Authentication. Firestore rules requiring `request.auth` will
reject this app's requests until Firebase Authentication is integrated.
Conversely, open test-mode rules allow unauthenticated reads and writes.
Do not use them with real team data or distribute the app until access is
protected by an authenticated backend and restrictive Firestore rules.
Keep `GoogleService-Info.plist` out of public repositories; its API key is
not a substitute for database access control.

## Current sync coverage

The app starts `FirebaseSyncService` automatically and syncs roster profiles,
tasks, activity, notebook entries, ideas, practice runs, batteries, checklists,
inventory, match-scouting reports, team settings, sponsors, and expenses.
Notebook and scouting deletions are propagated to Firestore. Team chat uses a
separate real-time listener backed by the `chat` collection. Scouting reports
are based on observations entered by the team; the app does not claim that
FTCScout provides live match scores or a published match schedule.

Firestore availability depends on a valid `GoogleService-Info.plist`, enabled
Firestore, network access, and rules that permit the app's current
unauthenticated Firestore requests. The app's local login does not grant
Firestore identity or team membership. Local SwiftData records remain
available on-device when Firestore is unavailable. Firestore may queue chat
writes in its local cache while offline; the app marks cached messages as
waiting to sync and keeps the draft until Firestore confirms or rejects the
send.
