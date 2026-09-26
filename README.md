# FivePD Integration for Sonoran CAD

**Unofficial, unsupported, and not maintained.** Provided as-is for communities still using legacy FivePD. Sonoran Software support does not troubleshoot this plugin, and future compatibility updates are not planned.

## Requirements

- A working legacy FivePD 1.5.x installation using FivePD API 1.3.0.
- [SonoranCADFiveM](https://github.com/Sonoran-Software/SonoranCADFiveM/releases/latest) 4.0.119 or newer, configured and connected to your CAD community.
- CAD API access for dispatch calls and custom records. Officers must link their CAD accounts to the server and have an active CAD unit, as well as be on duty in FivePD.

The bridge is built against the published FivePD API and checked against SonoranCADFiveM 4.0.119. It has not been verified in a live FivePD session. Modified FivePD builds and future CAD versions may behave differently.

## Install

1. Download **sonoran_fivepd.zip** from the [latest release](https://github.com/Sonoran-Software/sonoran_fivepd/releases/latest).
2. Copy the included `sonoran_fivepd` folder into your server's resources. Keep that folder name exactly as shown.
3. Copy `put_in_fivepd_plugins/SonoranPlugin.net.dll` into `fivepd/plugins/`, replacing the old DLL if present. Keep FivePD's own API DLLs in place.
4. Review `sonoran_fivepd/config.lua`. The default civilian and vehicle mappings match the common CAD field names. Adjust them if your community uses different mappings.
5. Add the resource after FivePD and Sonoran CAD in `server.cfg`:

   ```cfg
   ensure sonorancad
   ensure fivepd
   ensure sonoran_fivepd
   ```

6. Restart the server and reconnect. Link your CAD account, go on duty in CAD and FivePD, and accept a callout or make a traffic stop.

**Upgrading from the old plugin:** remove the old `fivepd` folder from `sonorancad/submodules/` and its FivePD configuration from `sonorancad/configuration/`. Replace the old `SonoranPlugin.net.dll`; do not keep a renamed second copy. This version runs as its own resource and does not go inside `sonorancad`.

## Features

| Trigger | CAD behavior |
| --- | --- |
| Accept a FivePD callout | Creates a dispatch call with its title, description, street, coordinates, case number, and responding officer. Further officers accepting the same FivePD callout are attached to that call. |
| Complete a callout | Adds one completion note per officer. The CAD call remains open for dispatch to manage. |
| Request a FivePD service | Adds a note to the officer's current imported call, such as a tow or ambulance request. |
| Make a traffic stop | Imports the stopped vehicle, driver, and passengers as CAD vehicle and civilian records. |
| Arrest an NPC | Imports that NPC's civilian record. |
| `/fivepdcadped` | Imports the closest networked NPC within 5 metres. Useful for callout suspects and witnesses. |
| `/fivepdcadvehicle` | Imports the closest networked vehicle within 15 metres. |

- Civilian data includes name, date of birth, age, gender, and address.
- Vehicle data includes plate, owner name, model, color, and registration status. Insurance and FivePD flags are available for custom mappings.
- Optional license imports include driver, hunting, fishing, and weapon licenses, with FivePD's status and expiration date. Optional warrant imports use FivePD's warrant text.
- Imported records and dispatch calls are automatically deleted by CAD after **60 minutes** by default. Set `deleteAfterMinutes` to a whole number from 1 to 1440.
- Repeated imports are skipped until their expiration, including across resource/server restarts. Re-encountered NPCs and vehicles can be imported again after expiration. Imports are snapshots; existing records are not continuously updated.
- Callout response codes map to CAD priorities: Code 1 -> priority 3, Code 2 -> priority 2, Code 3/99 -> priority 1. Unrecognized codes use priority 2. Both the mapping and call codes are configurable.
- An optional postal resource can provide postals. No new API key or changes to the Sonoran CAD resource are needed.

## Optional Record Mappings

In CAD's custom record editor, find the **field mapping ID** for each destination field. In `config.lua`, the left side is that CAD mapping ID; the right side is a FivePD data field or a Lua function. Record type IDs default to civilian `7`, vehicle `5`, license `4`, and warrant `2`.

Licenses and warrants are disabled by default. Add the relevant mappings before setting their `enabled` options to `true`:

```lua
-- Add to records.license.fields, using your actual CAD field mapping IDs:
['YOUR_LICENSE_TYPE_FIELD'] = 'LicenseType',
['YOUR_LICENSE_STATUS_FIELD'] = 'LicenseStatus',
['YOUR_LICENSE_EXPIRATION_FIELD'] = 'LicenseExpiration',

-- Add to records.warrant.fields:
['YOUR_WARRANT_DESCRIPTION_FIELD'] = 'Warrant',
```

License types are `DRIVER`, `HUNTING`, `FISHING`, and `WEAPON`. Statuses are `Valid`, `Expired`, `Revoked`, and `Suspended`; use a mapping function if your CAD dropdown uses different values. Dates are copied as FivePD provides them; use a mapping function if your CAD requires a different format.

To restrict access further, set `acePermission = 'sonoran_fivepd.use'` and grant that ACE to your officer group. Otherwise, linked players with active CAD units may use the bridge.

## Behavior and Troubleshooting

- Only NPCs and vehicles encountered through the triggers above are imported. This does not import FivePD's entire database, scan every nearby entity, or sync CAD edits back into FivePD.
- Completion adds a note; it does not close the call, detach officers, change duty status, or create arrest reports. Service notes do not dispatch CAD units. Unaccepted callouts do not create 911 calls.
- Writes are queued and paced, so busy servers may see a delay. Queued work older than three minutes or belonging to a disconnected player is discarded. The CAD API's community-wide rate limits still apply.
- If nothing appears, check that all three resources are started, the DLL is in `fivepd/plugins/`, and the officer is linked and on duty in both systems. Look for `[sonoran_fivepd]` in the server console and the client's F8 console.
- If a record is missing fields, check its CAD mapping IDs and dropdown values. If the server logs an API failure, check API access and configuration; re-run the import command after correcting the issue.
- Keep a backup of `config.lua` before replacing the resource with another copy.

## Source

[FivePD API source](https://github.com/KDani-99/FivePD-API) and the [official FivePD.net 1.3.0 package](https://www.nuget.org/packages/FivePD.net/1.3.0) provide the bridge's API contracts. The old FivePD documentation website is unavailable. [Build and verification notes](DEVELOPMENT.md) are included for anyone maintaining their own fork.
