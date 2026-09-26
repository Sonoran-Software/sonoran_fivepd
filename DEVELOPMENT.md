# Development

## Build and test

Install .NET SDK 8.0.424 and Python 3.12, then run from the repository root:

```sh
dotnet restore src_of_fivepd_plugin/SonoranPlugin.csproj --locked-mode
dotnet build src_of_fivepd_plugin/SonoranPlugin.csproj -c Release --no-restore
python3 -m pip install lupa==2.8
python3 tests/run.py /path/to/SonoranCADFiveM
```

The optional test argument loads that checkout's actual bundled Sonoran.lua client and captures its HTTP requests. No CAD credentials or live API writes are used. Without the argument, tests use mocked SDK methods.

Copy `src_of_fivepd_plugin/bin/Release/net452/SonoranPlugin.net.dll` to `put_in_fivepd_plugins/` after a successful build. Ship only that plugin DLL, not the API, CitizenFX, or framework reference assemblies. A `v*` tag builds, tests, and publishes the installation ZIP through GitHub Actions.

## Verified contracts

- FivePD API source: [`f44d987`](https://github.com/KDani-99/FivePD-API/tree/f44d9872a3e8b783ece4d048e5874aea2c3228da), last upstream commit July 11, 2021.
- FivePD's [official NuGet 1.3.0 package](https://www.nuget.org/packages/FivePD.net/1.3.0), published July 2021 for the FivePD 1.5 update. Package references and their hashes are locked. The DLL compiles against the real published API, not substitute type definitions.
- The public API is a wrapper, not the full FivePD runtime. It exposes callout, service, and arrest events; `GetPedData`, `GetVehicleData`, and traffic-stop accessors. It does not expose a general record-viewed event. Traffic-stop imports use a two-second poll with a one-minute per-entity cooldown. Current callouts are checked once per minute to recover missed acceptance events or resource restarts.
- CAD target: [SonoranCADFiveM 4.0.119, commit `4823168`](https://github.com/Sonoran-Software/SonoranCADFiveM/tree/482316841a853210f861fa9135543a25675265bd). Server code obtains `getCadClient()` and calls only `createDispatchCallV2`, `attachUnitsToDispatchCallV2`, `addDispatchNoteV2`, and `createRecordV2`.
- The v2 record endpoint accepts the zero UUID through its `user` selector for unowned NPC records. Using zero UUID as `accountUuid` is rejected by its account resolver. The selector does not change the endpoint: requests still go to `POST /v2/general/records` through Sonoran.lua.
- `deleteAfterMinutes` is passed on creation. Deletion is scheduled by CAD, independent of whether the game server remains online.

## Verification scope

Automated tests cover authorization using the real event source, malformed data, priority conversion, shared call deduplication, officer attachment, notes, optional licenses/warrants, record expiry, persistent deduplication, failed writes, missing response IDs, disconnected sessions, concurrent acceptance, and SDK v2 routing. The server never accepts a player ID, CAD unit ID, or record template ID from the client payload.

No live FiveM/FivePD session was available during development. The release therefore requires an in-game smoke test on the community's own FivePD build. Confirm a two-officer callout, traffic-stop driver/passengers/vehicle, arrest, nearby import commands, optional custom fields, completion/service notes, resource restart, and CAD deletion after the configured interval.

Successful imports are snapshots and are deduplicated until expiration. KVP state is scoped by CAD community and server. Deleting that KVP state, running duplicate installations, or an HTTP response lost after CAD commits a write can produce duplicates. FivePD's client API supplies the NPC data; linked on-duty players are trusted to report it. Optional ACE restrictions narrow who can submit it.

The original integration was sponsored by LakeSide RP.
