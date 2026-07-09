# Changelog

All notable changes to Jamf Preload Manager are documented here. Versions ending in `p` denote
public builds.

## 0.8p — 2026-07-09

### Added
- **Computer & Mobile Device support.** Device Type is now a first-class **Computer / Mobile
  Device** choice throughout the app (previously every record was created as `Computer`):
  - A Device Type toggle on the **Add** and **Modify** screens.
  - **Bulk → Serials-only CSV:** a Device Type picker applied to every serial in the run.
  - **Bulk → Completed CSV:** generate a **Mac** or **Mobile** template. The template now has a
    `Device Type` column, and its example first row is pre-filled with the chosen type.
  - Filled-CSV import reads the `Device Type` column per row (blank defaults to `Computer`).
  - Record summaries (Find / Modify / Delete) always show Device Type.
  - iPhone, iPad, Apple TV, Apple Watch, and Apple Vision Pro all use the `Mobile Device` type.

### Changed
- Device Type is no longer a configurable field in **Settings → Fields** (it is always collected).
- Documentation updated for the Computer/Mobile Device workflow.

## 0.7p — 2026-07-09

### Added
- Initial public release.
- Manage Jamf Pro **Inventory Preload records**: Find, Add, Modify, Delete, and CSV-based bulk
  create/update/delete, plus CSV export.
- **Configurable fields:** enable standard Jamf fields or add extension attributes; each field is
  free-text or a pick list (with optional custom entry). Drives the GUI and CSV templates.
- **Managed configuration profiles:** deploy and lock the field configuration via an MDM profile;
  optional non-locking seeds for the server URL and Client ID.
- **Activity log** at `~/Library/Logs/Jamf Preload Manager/PreloadActivity.log` recording every
  add/modify/delete with the record's previous values for recovery.
- Multi-server support; credentials stored per host in the login Keychain; TLS public-key pinning.
- Signed, notarized installer package and a source build script (`script/build_pkg.sh`).
