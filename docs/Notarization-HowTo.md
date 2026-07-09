# macOS Notarization — How To (Developer ID / Jamf / Direct Distribution)

Audience: Developers/packagers shipping a signed `.pkg` (e.g. via Jamf) or a signed `.app` outside the Mac App Store.

Repository release model:
- This repo stores release artifacts in `dist/` (`.app` and `.pkg`) together with source.
- After notarization/stapling validation, commit the final distributable binaries to `dist/`.

## What “notarize” means (quickly)

- **Notarization** is for apps you distribute **outside** the Mac App Store (Developer ID distribution). It lets Gatekeeper verify Apple has scanned the app/package.
- **Stapling** embeds the notarization “ticket” into your `.pkg`/`.app` so installs work even when the Mac can’t reach Apple services (recommended for Jamf).

For Jamf, you usually notarize + staple the **final signed `.pkg`** you upload to Jamf.

## Before you start (prereqs)

1. Xcode Command Line Tools installed (for `xcrun`, `notarytool`, `stapler`).
2. Your signing certs (with private keys) available in Keychain:
   - **Developer ID Application** (signs the `.app`)
   - **Developer ID Installer** (signs the `.pkg`)
3. Access to **App Store Connect** (website) with permission to create API keys (or ask your team Admin/Account Holder).
4. Avoid building/signing out of cloud-synced folders (OneDrive/Dropbox) if you’ve hit “signature modified” issues; prefer a local working directory (e.g. under your home folder) while signing/notarizing.

## Fast path with this repo script (recommended)

Once signing identities and notary credentials are set up, use:

```bash
bash script/build_and_run.sh package --notarize
```

What this does:
- Builds the app bundle
- Signs the app and pkg (when signing identities are configured)
- Submits the pkg with `notarytool --wait`
- Staples and validates the pkg
- Optionally staples/validates the app too when `--staple-app` is passed

Required environment values (for `--notarize`):
- `NOTARY_KEYCHAIN_PROFILE` (created via `xcrun notarytool store-credentials ...`)
- Optional `NOTARY_KEYCHAIN_PATH` (defaults to `~/Library/Keychains/login.keychain-db`)

## 1) Create an App Store Connect API key (`AuthKey_*.p8`)

App Store Connect is a **website**.

1. Open App Store Connect in a browser and sign in with your Apple Developer team account.
2. Go to **Users and Access** → **Keys**.
3. Click **+** to create a new key.
4. Give it a name and choose an access role (commonly **Developer** is sufficient for notarization).
5. Create the key, then **Download API Key**.
   - This downloads a file like `AuthKey_ABC123DEFG.p8`.
   - You typically only get one chance to download it—store it safely.
6. On the same Keys page, copy:
   - **Key ID** (looks like `ABC123DEFG`)
   - **Issuer ID** (UUID, looks like `01234567-89AB-CDEF-0123-456789ABCDEF`)

Security notes:
- Treat the `.p8` like a password (do not email it, do not commit it to git).
- Prefer storing it in a restricted location and backing it up securely.

## 2) Ensure your app and pkg are signed correctly

### A) Sign the `.app` (Developer ID Application)

Typical command:

```bash
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: Team Name (TEAMID)" \
  "/path/to/YourApp.app"
```

Verify:

```bash
codesign --verify --deep --strict --verbose=2 "/path/to/YourApp.app"
codesign -dv --verbose=4 "/path/to/YourApp.app" 2>&1 | sed -n '1,25p'
```

### B) Build/sign the `.pkg` (Developer ID Installer)

If your `.pkg` installs an app into `/Applications`:

```bash
productbuild --component "/path/to/YourApp.app" "/Applications" \
  --sign "Developer ID Installer: Team Name (TEAMID)" \
  "/path/to/YourInstaller.pkg"
```

Verify the pkg signature:

```bash
pkgutil --check-signature "/path/to/YourInstaller.pkg"
```

## 3) Store notary credentials (API key) in Keychain (one-time)

This saves a reusable credential profile (example name: `AC_NOTARY`) into your login keychain.

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --key "/path/to/AuthKey_ABC123DEFG.p8" \
  --key-id "ABC123DEFG" \
  --issuer "01234567-89AB-CDEF-0123-456789ABCDEF" \
  --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --validate
```

Notes:
- If the keychain is locked, macOS will prompt you to unlock it.
- Keep the profile name stable (`AC_NOTARY`) so automation/scripts can reuse it.

## 4) Submit to Apple for notarization (manual path)

For Jamf: submit the **signed `.pkg`** you intend to upload.

```bash
xcrun notarytool submit "/path/to/YourInstaller.pkg" \
  --keychain-profile "AC_NOTARY" \
  --keychain "$HOME/Library/Keychains/login.keychain-db" \
  --wait
```

What you should see:
- An upload completes
- A submission `id` is returned
- Final status becomes **Accepted**

If you didn’t use `--wait`, you can check later:

```bash
xcrun notarytool info <submission-id> \
  --keychain-profile "AC_NOTARY" \
  --keychain "$HOME/Library/Keychains/login.keychain-db"
```

To fetch a detailed log for a completed submission:

```bash
xcrun notarytool log <submission-id> \
  --keychain-profile "AC_NOTARY" \
  --keychain "$HOME/Library/Keychains/login.keychain-db"
```

## 5) Staple the ticket (recommended) + validate

Staple onto the **same artifact you will distribute** (for Jamf, the `.pkg`):

```bash
xcrun stapler staple "/path/to/YourInstaller.pkg"
xcrun stapler validate "/path/to/YourInstaller.pkg"
```

Gatekeeper sanity check:

```bash
spctl -a -vv --type install "/path/to/YourInstaller.pkg"
```

Expected output includes `source=Notarized Developer ID`.

## 6) Upload to Jamf Self Service

Upload the **stapled** pkg to Jamf, not the pre-staple copy.

After upload, instruct end users to install/update from Self Service:
1. Open **Self Service**.
2. Search for **Jamf Preload Manager**.
3. Install the latest listed version.

## Common issues / troubleshooting

- **`No Keychain password item found for profile: AC_NOTARY`**
  - You haven’t run `store-credentials` successfully, or you used a different profile name.

- **`Error: HTTP status code: 401. Invalid credentials`**
  - This is an authentication failure. With the API-key method, re-check `--key-id`, `--issuer`, and that the `.p8` file path is correct and readable.
  - Ensure the API key is created under the correct team in App Store Connect.

- **`codesign: ... no identity found` / `productbuild: ... could not find`**
  - The certificate/private key isn’t available to the current user, the keychain is locked, or the private key is missing.
  - Check available identities:
    - `security find-identity -v -p codesigning`
    - `security find-identity -v -p basic`

- **`invalid signature (code or signature have been modified)`**
  - Something changed in the app bundle after signing (common causes: post-processing, editing Info.plist, or cloud-sync tools mutating metadata).
  - Re-sign after all modifications are complete; consider moving the app to a local folder before signing.

- **Notarization accepted but installs still warn**
  - Make sure you stapled the **exact** file you distribute and that Jamf is uploading that stapled file (not an older copy).
