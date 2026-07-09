# Jamf Preload Manager

A native macOS app for managing **Jamf Pro Inventory Preload records** — look up, create,
modify, bulk-import, export, and delete preload entries against device serial numbers without
working directly in the Jamf Pro web console or writing ad-hoc scripts.

The app is **environment-agnostic**: you choose which fields it collects (standard Jamf
inventory-preload fields *and* your own extension attributes), and a Jamf admin can deploy and
lock that configuration fleet-wide with a configuration profile.

> Community project. Not affiliated with or endorsed by Jamf.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Using the app](#using-the-app)
- [Configurable fields](#configurable-fields)
- [Managed configuration profiles](#managed-configuration-profiles)
- [Example configuration profile](#example-configuration-profile)
- [Activity log](#activity-log)
- [Security](#security)
- [Build from source](#build-from-source)
- [License](#license)

---

## Features

- **Find** – look up a serial number and see its current preload values.
- **Add** – create a single preload record from a guided form with required-field validation.
- **Modify** – load an existing record, edit it, and save changes back to Jamf.
- **Delete** – permanently remove a preload record (with confirmation).
- **Bulk workflows** (processed one record at a time through the standard per-record API, so
  they need no elevated "bulk import" permissions):
  - *Serials-only CSV* – apply the same field values to a list of serials.
  - *Completed CSV* – download a template built from your fields, fill it in, and the app
    does a *find → create or update* per row.
  - *Bulk delete* – *find → delete* for a list of serials.
- **CSV export** – save the current Jamf inventory-preload data to CSV for review/auditing.
- **Configurable fields** – enable any standard Jamf field or add extension attributes; each
  field is free-text or a pick list you define. Drives the GUI *and* the CSV templates.
- **Managed configuration** – deploy and lock the field configuration via a profile.
- **Activity log** – every add/modify/delete is logged with the record's previous values so a
  mistake can be reversed.
- **Multi-server** – save several Jamf tenants; credentials are kept per host.
- **Secure by default** – credentials in the login Keychain, TLS public-key pinning per host,
  ephemeral OAuth tokens never written to disk.

---

## Requirements

- macOS 14 (Sonoma) or later.
- A Jamf Pro **API client** (client ID + secret) created under *Settings → API roles and
  clients* with privileges for Inventory Preload records:
  - Read, Create, Update, Delete **Inventory Preload Records**
  - (CSV export uses the same read privilege.)

Grant least privilege — only the Inventory Preload privileges the workflows you use require.

---

## Install

1. Download **`Jamf Preload Manager.pkg`** from this repository (or the Releases page).
2. Double-click it and follow the installer. The app installs to `/Applications`.
3. Launch **Jamf Preload Manager**.

The installer is signed with a Developer ID Installer certificate. If your Mac shows a
Gatekeeper prompt because a particular build is not notarized, right-click the pkg → **Open**,
or an admin can notarize their own build (see [Build from source](#build-from-source)).

Admins can upload the same `.pkg` to Jamf Pro and distribute it via a policy or Self Service.

---

## Using the app

### 1. Connect to Jamf (Settings → Server & Credentials)

Press **⌘,** to open Settings.

1. Add your Jamf URL (e.g. `https://yourorg.jamfcloud.com`) and click **Add Server**.
2. Enter the **Client ID** and **Client Secret** for your API client.
3. Click **Save & Test** to verify authentication and API access.

Credentials are stored in your **login Keychain**, separately per Jamf host. Switching servers
reloads that host's saved credentials.

### 2. Choose your fields (Settings → Fields)

See [Configurable fields](#configurable-fields). Out of the box the app collects only Serial
Number (always required) and Device Type.

### 3. Work with records

- **Find Entry** – enter a serial, view the current preload record.
- **Add Entry** – fill the serial + your configured fields, **Create Entry**.
- **Modify Entry** – **Load Record** by serial, edit, **Save Changes**.
- **Delete Entry** – load a record, confirm, delete.
- **Bulk Update** – pick a workflow, download a template if needed, import your CSV, run it.
  Results are reported per row so you can fix and re-run safely.

CSV templates always match your configured fields, so a template you download is exactly what
the app expects back on import.

---

## Configurable fields

Open **Settings → Fields**. Serial Number is always included and required; everything else is
up to you.

- **Standard Jamf fields** – toggle any inventory-preload field on/off (Device Type, Username,
  Full Name, Email Address, Department, Building, Room, Asset Tag, PO Number, Warranty
  Expiration, and the rest of Jamf's template columns).
- **Extension attributes** – add your own by name (use the exact attribute name from Jamf Pro).
- **Per-field input type**:
  - **Free text** – a plain text box.
  - **Choose from list** – a pick list you define (one option per line). Optionally also
    **allow a custom typed value**.
- **Required** – mark a field mandatory before a record can be saved.

Changes apply to every screen and to the CSV templates. Use **Export Configuration Profile…**
to turn your current configuration into a deployable `.mobileconfig` (see below).

---

## Managed configuration profiles

A Jamf admin can push the field configuration (and optional connection seeds) as a macOS
**configuration profile**. This lets you standardise every Mac in the fleet.

The app reads a **forced** preference under key **`FieldConfiguration`** in its preference
domain **`io.github.woodmember.JamfPreloadManager`**.

- **When a managed `FieldConfiguration` is present:** the **Fields** settings become read-only
  with a *"Managed by your organization"* banner. Users cannot change the fields.
- **Optional connection seeds** (pre-populated but **not** locked — users can still change them):
  - **`DefaultServerURL`** – seeds the Jamf server URL.
  - **`DefaultClientID`** – seeds the API Client ID.
- **The Client Secret is never carried in a profile.** It always stays in the login Keychain.

Two ways to build a profile:

1. **From the app** – configure fields, optionally fill the *Configuration Profile Defaults*
   (server URL / client ID), then **Settings → Fields → Export Configuration Profile…**.
2. **By hand** – edit the [example](#example-configuration-profile) below.

A ready-to-edit example ships at
[`config/Example-FieldConfiguration.mobileconfig`](config/Example-FieldConfiguration.mobileconfig).
Full reference: [`docs/ManagedConfiguration-HowTo.md`](docs/ManagedConfiguration-HowTo.md).

### Field dictionary keys

Each entry in the `fields` array is a dictionary:

| Key                 | Type    | Meaning                                                              |
|---------------------|---------|---------------------------------------------------------------------|
| `id`                | String  | Stable id: `std:<apiKey>` for standard fields, `ea:<Name>` for EAs  |
| `kind`              | String  | `standard` or `extensionAttribute`                                  |
| `key`               | String  | API key (standard) or exact extension attribute name (EA)           |
| `displayName`       | String  | GUI label and CSV column header                                     |
| `inputType`         | String  | `freeText` or `list`                                                |
| `listOptions`       | Array   | Options shown when `inputType` is `list`                            |
| `allowsCustomEntry` | Boolean | Allow a typed custom value in addition to the list                  |
| `isRequired`        | Boolean | Whether the field must be filled                                    |
| `defaultValue`      | String  | Pre-filled value for new records                                    |

Serial Number is implicit and always required, so it is **not** listed in `fields`. If no
`Device Type` field is configured, records are created as `Computer`.

Standard `key` values are Jamf's camelCase API keys, e.g. `deviceType`, `username`, `fullName`,
`emailAddress`, `phoneNumber`, `position`, `department`, `building`, `room`, `poNumber`,
`poDate`, `warrantyExpiration`, `appleCareId`, `purchasePrice`, `lifeExpectancy`,
`purchasingAccount`, `purchasingContact`, `leaseExpiration`, `barCode1`, `barCode2`,
`assetTag`, `vendor`.

---

## Example configuration profile

A minimal, editable `.mobileconfig`. It defines two standard fields and two extension
attributes, seeds the server URL, and (commented) shows where a client ID would go. Replace the
`PayloadUUID` values with freshly generated UUIDs (`uuidgen`) and the fields with your own.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadType</key><string>Configuration</string>
  <key>PayloadVersion</key><integer>1</integer>
  <key>PayloadIdentifier</key><string>io.github.woodmember.JamfPreloadManager.fieldconfiguration</string>
  <key>PayloadUUID</key><string>REPLACE-WITH-UUID-1</string>
  <key>PayloadDisplayName</key><string>Jamf Preload Manager – Field Configuration</string>
  <key>PayloadScope</key><string>System</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key><string>com.apple.ManagedClient.preferences</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadIdentifier</key><string>io.github.woodmember.JamfPreloadManager.fieldconfiguration.preferences</string>
      <key>PayloadUUID</key><string>REPLACE-WITH-UUID-2</string>
      <key>PayloadContent</key>
      <dict>
        <key>io.github.woodmember.JamfPreloadManager</key>
        <dict>
          <key>Forced</key>
          <array>
            <dict>
              <key>mcx_preference_settings</key>
              <dict>
                <!-- Optional connection seeds (pre-filled, NOT locked). -->
                <key>DefaultServerURL</key><string>https://yourorg.jamfcloud.com</string>
                <!-- <key>DefaultClientID</key><string>your-api-client-id</string> -->

                <!-- The field configuration (locks the Fields settings). -->
                <key>FieldConfiguration</key>
                <dict>
                  <key>fields</key>
                  <array>
                    <dict>
                      <key>id</key><string>std:deviceType</string>
                      <key>kind</key><string>standard</string>
                      <key>key</key><string>deviceType</string>
                      <key>displayName</key><string>Device Type</string>
                      <key>inputType</key><string>list</string>
                      <key>listOptions</key>
                      <array><string>Computer</string><string>Mobile Device</string></array>
                      <key>allowsCustomEntry</key><false/>
                      <key>isRequired</key><false/>
                      <key>defaultValue</key><string>Computer</string>
                    </dict>
                    <dict>
                      <key>id</key><string>std:assetTag</string>
                      <key>kind</key><string>standard</string>
                      <key>key</key><string>assetTag</string>
                      <key>displayName</key><string>Asset Tag</string>
                      <key>inputType</key><string>freeText</string>
                      <key>listOptions</key><array/>
                      <key>allowsCustomEntry</key><false/>
                      <key>isRequired</key><false/>
                      <key>defaultValue</key><string></string>
                    </dict>
                    <dict>
                      <key>id</key><string>ea:Building</string>
                      <key>kind</key><string>extensionAttribute</string>
                      <key>key</key><string>Building</string>
                      <key>displayName</key><string>Building</string>
                      <key>inputType</key><string>list</string>
                      <key>listOptions</key>
                      <array><string>HQ</string><string>Warehouse</string><string>Remote</string></array>
                      <key>allowsCustomEntry</key><true/>
                      <key>isRequired</key><false/>
                      <key>defaultValue</key><string></string>
                    </dict>
                  </array>
                </dict>
              </dict>
            </dict>
          </array>
        </dict>
      </dict>
    </dict>
  </array>
</dict>
</plist>
```

**Install it to test locally:** double-click the `.mobileconfig`, then approve it in
**System Settings → General → Device Management** (requires admin). Relaunch the app; the Fields
tab will show the locked configuration. Remove the profile to unlock. In production, upload the
profile to Jamf Pro (Computers → Configuration Profiles) and scope it.

---

## Activity log

Every add, modify, and delete is appended to:

```
~/Library/Logs/Jamf Preload Manager/PreloadActivity.log
```

Modify and delete entries capture the record's **previous values**, so if you make a mistake you
can read the log and restore the old details. Open it from the app menu:
**Reveal Activity Log in Finder** / **Open Activity Log**.

Example lines:

```
2026-07-09 15:12:04 +1000 | ADD    | serial=C02XX | id=411 | NEW: deviceType=Computer; assetTag=A-1001
2026-07-09 15:14:20 +1000 | MODIFY | serial=C02XX | id=411 | BEFORE: deviceType=Computer; assetTag=A-1001 | AFTER: deviceType=Computer; assetTag=A-2002
2026-07-09 15:20:00 +1000 | DELETE | serial=C02XX | id=411 | WAS: deviceType=Computer; assetTag=A-2002
```

---

## Security

- **Credentials** live in the macOS **login Keychain** (Generic Password items), keyed per Jamf
  host. They are never written to source, CSVs, or plain files, and never embedded in a
  configuration profile.
- **TLS public-key pinning** – the app pins the server's public key per host on first
  connection and rejects mismatches on later requests.
- **OAuth tokens** – obtained on demand via the client-credentials flow and never persisted.
- **Least privilege** – bulk operations use the standard per-record endpoints, so the API role
  only needs the Inventory Preload privileges for the actions you perform.

---

## Build from source

Swift Package Manager project targeting macOS 14+.

```bash
# Debug build / run tests
swift build

# Build a signed installer .pkg (output: "Jamf Preload Manager.pkg" in the repo root)
cp script/signing.env.example script/signing.env   # then edit with your identities
./script/build_pkg.sh

# Build + notarize + staple (recommended for public distribution)
./script/build_pkg.sh --notarize
```

`script/build_pkg.sh`:

1. Builds the release binary.
2. Assembles and **codesigns** the `.app` (Developer ID Application, hardened runtime).
3. Produces a **signed** installer `.pkg` (Developer ID Installer).
4. With `--notarize`, submits to Apple's notary service and staples the ticket.

Set your signing identities in `script/signing.env` (git-ignored) — see
[`script/signing.env.example`](script/signing.env.example). Notarization requires a stored
notary profile; see [`docs/Notarization-HowTo.md`](docs/Notarization-HowTo.md).

> **Note on the committed installer:** the bundled `.pkg` is Developer ID **signed**. If it is
> not **notarized**, Gatekeeper may warn on first open for users who download it from the web.
> For the smoothest experience, build with `--notarize`.

---

## License

[MIT](LICENSE)
