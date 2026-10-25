# PGRP Android v0.4.4 — Real DFF Preview

This milestone reads **original GTA San Andreas model geometry** directly from a
user-selected, legally obtained `models/gta3.img` on Android. No GTA models,
textures, game archives, or files are distributed in the APK.

## Installation and use

1. Update the installed stable-signed v0.4.3 app with
   `PGRP_Android_v0.4.4_SameKey_Update.apk`. The application ID stays
   `ir.paladinguard.gameclient` and versionCode increases from 7 to 8.
2. Open PGRP → **دیتای GTA** → inspect the existing
   `Download/PGRP-GTA/GTA.San.Andreas` folder.
3. In the successful inspection dialog, tap **مدل DFF سه‌بعدی**.
4. The app scans the `VER2` archive and chooses one small, supported static
   `.dff` mesh, then opens a separate fullscreen GLSurfaceView.
5. Drag a finger to rotate the **untextured real mesh**.

No new data transfers are needed.

## Verified

- Android Gradle compilation and JVM tests for RenderWare CLUMP parsing,
  archive indexing, triangle extraction, malformed chunk and invalid indices
  succeeded in GitHub Actions.
- Stable release signed with the existing PGRP private key.
- Android APK Signature Schemes v2/v3 verified; certificate SHA-256:
  `0880fb4c4f565950fef3f6334c5ebf85a649a1c0a20077df458515f6c09bf9c0`.

## Limitations

- Single static untextured mesh **preview**, not a complete GTA map or
  multiplayer client.
- RenderWare DFF features such as skinned models, some native geometry,
  material textures, frame hierarchy, lighting, and multi-geometry assembly
  are not implemented. If the first scanned 160 small DFF candidates are all
  unsupported the app displays the specific error instead of showing fake
  game models.
- Neither `TXD` texture decoding nor COLL, world streaming, character
  animations, vehicle physics, and authenticated open.mp gameplay are done.
- Build/tests prove parser behaviour on synthetic DFF data, **not successful
  rendering on the user's exact original GTA installation**. An on-device
  screenshot of the model viewer or its error is needed to validate that.
