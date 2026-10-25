# PGRP Android 0.4.3 — Binary IPL update

- **Same Android identity**: `ir.paladinguard.gameclient`; `versionCode 7` (0.4.2 was 6).
- **Same permanent signing certificate**: SHA-256 `0880fb4c4f565950fef3f6334c5ebf85a649a1c0a20077df458515f6c09bf9c0`.
- Build with `.github/workflows/build-android-stable-v043.yml` (Gradle unit tests + unsigned APK).
- Stable signed release uses the owner's original secure signing keystore, never a fresh debug key.
- **New** read-only GTA SA `VER2` IMG directory scan; identify streaming binary `.ipl` entries.
- **New** parse 76-byte `bnry` headers and 40-byte world-placement records (XYZ, quaternion, model ID, flags and LOD). Validate all offsets/counts/finite floats; bound RAM to 12,000 samples.
- **New** merge textual IPL preview and streaming-binary IPL sample positions, with color distinction and per-format counts.
- **Preserved** textual gta.dat / IDE / IPL inspector, existing GTA data selection, touch demo, and network probe.
- **Not yet present** actual GTA DFF mesh rendering, TXD textures, complete binary IPL coordinate streaming, object collisions, player synchronization or authenticated open.mp gameplay.
- Running PGRP Android 0.4.3 needs no new device file transfers. If v0.4.2 is installed with the permanent signing certificate, install the signed update APK directly on top.

The permanently signed test APK can be built from the CI-produced unsigned release using `apksigner` with the owner's offline keystore. Do not commit or upload the keystore or password. Future GitHub CI signing is gated behind encrypted repository secrets `PGRP_ANDROID_KEYSTORE_B64` and `PGRP_ANDROID_STORE_PASSWORD`, which must be manually configured by the repository owner.
