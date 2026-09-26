Unofficial, unsupported, and not maintained. Provided as-is for legacy FivePD communities.

- Includes the same PolyForm Noncommercial License 1.0.0 as SonoranCADFiveM, in both the repository and release ZIP.
- Corrects installation to use `exec sonorancad.cfg` and removes legacy upgrade instructions.
- Verifies four officers submitting the same callout entities concurrently create only one of each applicable record, including after a resource restart. Deduplication lasts until record expiry and is shared across callouts.
- NPC portraits remain excluded; the shared headshot capture path has not been verified for concurrent automatic NPC captures.
- Automatic callout imports, default CAD mappings, and v2-only writes through the bundled Sonoran.lua client remain unchanged.

Build, collector tests, and bridge tests through the real bundled CAD v2 SDK pass. Live FivePD gameplay has not been verified. See the README for installation and limitations.
