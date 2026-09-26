Unofficial, unsupported, and not maintained. Provided as-is for legacy FivePD communities.

- Automatically imports NPCs and vehicles retained by accepted callouts, including later spawns. Nearby commands remain optional fallbacks for custom callouts that cannot be inspected.
- Civilian, vehicle, license, and warrant imports enabled with verified default CAD mapping IDs and matching dropdown values.
- Supports both original and saved default license UIDs. Fishing licenses remain opt-in because the default CAD template has no fishing option.
- README includes illustrated field-ID instructions and clear automatic-import limits.
- All CAD writes still use the bundled Sonoran.lua v2 client, paced with persistent duplicate suppression and 60-minute CAD-managed deletion by default.

**Upgrade:** back up your configuration, replace both the resource and `SonoranPlugin.net.dll`, and merge custom settings into the new `config.lua`. Restart the server and reconnect. No Sonoran CAD resource changes are needed.

Build, collector tests, and bridge tests through the real bundled CAD v2 SDK pass. Live FivePD gameplay has not been verified. See the README for installation and limitations.
