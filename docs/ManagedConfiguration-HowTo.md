# Managed Configuration — How To

Jamf Preload Manager lets each user choose which fields the app collects (Settings →
Fields). A Jamf admin can instead **deploy** that configuration as a macOS configuration
profile so every managed Mac uses the same fields. When a managed configuration is present,
the Fields settings become **read-only** on that Mac and users cannot change them.

## What the app reads

The app reads a **forced** (profile-supplied) preference under the key `FieldConfiguration`
in its own preferences domain, `io.github.woodmember.JamfPreloadManager`. If that key is present and
forced, the app treats the configuration as managed and locks the Fields settings.

The `FieldConfiguration` value is a dictionary with a single `fields` array. Each field is a
dictionary:

| Key                | Type      | Meaning                                                        |
|--------------------|-----------|----------------------------------------------------------------|
| `id`               | String    | Stable id — `std:<apiKey>` for standard fields, `ea:<Name>` for EAs |
| `kind`             | String    | `standard` or `extensionAttribute`                             |
| `key`              | String    | API key (standard) or exact extension attribute name (EA)      |
| `displayName`      | String    | GUI label and CSV column header                                |
| `inputType`        | String    | `freeText` or `list`                                           |
| `listOptions`      | Array     | Options shown when `inputType` is `list`                       |
| `allowsCustomEntry`| Bool      | Allow a typed custom value in addition to the list             |
| `isRequired`       | Bool      | Whether the field must be filled                               |
| `defaultValue`     | String    | Pre-filled value for new records                               |

Serial Number is always implicit and required, so it is not listed in `fields`. If no
`Device Type` field is configured, records are created with `Computer`.

### Optional seeds: server URL and Client ID

The same managed payload may also include two **optional** keys in its domain:

| Key                | Type   | Meaning                                                    |
|--------------------|--------|------------------------------------------------------------|
| `DefaultServerURL` | String | Pre-populates the Jamf server URL                          |
| `DefaultClientID`  | String | Pre-populates the API Client ID                            |

Unlike `FieldConfiguration`, these are **not locked** — they are only a starting point.
The app uses them when nothing is stored yet, and the user can still change and save their
own values. The **Client Secret is never carried in a profile**; it always stays in the
login Keychain. This lets an admin give everyone a consistent starting configuration without
enforcing credentials.

## The easy way: export from the app

1. Configure the fields you want in **Settings → Fields**.
2. Optionally fill in **Configuration Profile Defaults** (server URL, Client ID) to seed
   those for your org. These are pre-filled from your current setup and are not locked.
3. Click **Export Configuration Profile…** and save the `.mobileconfig`.
4. Upload it to Jamf Pro (Computers → Configuration Profiles → Upload) and scope it.

The exported profile uses a managed-preferences (MCX) payload targeting
`io.github.woodmember.JamfPreloadManager`, which is exactly what the app reads.

## Ready-made example profile

`config/Example-FieldConfiguration.mobileconfig` is a ready-to-test profile defining four
fields — a Device Type pick list, an Asset Tag free-text field, a `Building` extension
attribute (pick list with custom entry allowed), and an `Owner` extension attribute — plus a
seeded server URL. Use it to see managed mode in action. Edit the field names/options to match
your own Jamf tenant, or regenerate it from the app with **Export Configuration Profile…**.

## Test it locally

1. Double-click `config/Example-FieldConfiguration.mobileconfig` (or install it via
   **System Settings → General → Device Management / Profiles**). Installing a profile
   requires administrator approval.
2. Launch **Jamf Preload Manager** and open **Settings → Fields**. You should see the
   profile's fields with a **“Managed by your organization”** banner and all controls disabled.
3. Remove the profile from **Profiles** to return to user-editable settings.

> Note: because the app is not sandboxed and reads its own preferences domain, an
> unsigned/self-authored profile installed by hand is sufficient for testing. In production,
> deploy the profile through Jamf Pro.
