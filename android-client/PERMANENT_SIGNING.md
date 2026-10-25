# PGRP Android — permanent signing (v0.4.2)

The v0.4.0 and v0.4.1 development APKs were signed by **different ephemeral
GitHub Actions debug keys**. Android rejects an APK with a different signing
certificate as an in-place update, even if package name and versionCode match.
Those keys are not recoverable from the public APK.

## Permanent release identity

- applicationId: `ir.paladinguard.gameclient`
- First permanently signed version: `0.4.2`, `versionCode 6`
- Signing alias: `pgrp_release`
- PKCS#12 password-protected keystore, RSA-3072, valid until 2056
- Release certificate SHA-256:
  `0880fb4c4f565950fef3f6334c5ebf85a649a1c0a20077df458515f6c09bf9c0`
- Signing scheme: Android APK Signature v2 and v3; minimum SDK 26

**Security:** The private `.p12` key and its password are **not** stored in
this public repository, and must never be committed or published as a release
asset. The user must download, safeguard, and back up the separately delivered
private signing key. Store copies on controlled offline media, not in the
repository or a public chat. Anyone with both the private key and password
could produce a counterfeit PGRP update.

## First migration

1. Back up anything useful from the old application.
2. Uninstall the old `ir.paladinguard.gameclient` debug-signed app **once**.
   Updating over v0.4 or v0.4.1 without a matching private key is not possible.
3. Install `PGRP_Android_v0.4.2_Permanent_Signed.apk`, signed by the key
   shown above. This is a release-mode APK, not a debug app.
4. Open the app and select the existing user-owned GTA folder in
   `Download/PGRP-GTA/GTA.San.Andreas` again. The external shared-storage
   folder is separate from the app sandbox and should remain after uninstall.
5. All future same-package updates must use this same release private key and
   increment `versionCode`.

## GitHub Actions automatic signing (one-time owner configuration)

The pipeline `.github/workflows/build-android-stable-v042.yml` compiles,
runs unit tests and produces an unsigned release. It publishes a signed APK
**only** after two repository secrets are configured:

- `PGRP_ANDROID_KEYSTORE_B64`: Base64 of the complete PKCS#12 private keystore,
  without additional whitespace, from the user's secure signing backup.
- `PGRP_ANDROID_STORE_PASSWORD`: The keystore password supplied to its owner.

Configure these under the repository's
**Settings → Secrets and variables → Actions → New repository secret**.
Select workflow **PGRP Android v0.4.2 Permanent Release Signing**,
then **Run workflow** on branch `feature/pgrp-android-stable-signing-v042`.
The pipeline verifies the resulting certificate fingerprint and refuses to
publish an APK signed by a different key.

If either secret is missing, the workflow **does not publish a public
release** and only provides an unsigned CI artifact. This protects the update
chain from silently reverting to GitHub's per-run debug signing.

## Future versions

For v0.4.3 and later, use the same secret names / keystore and build signing
logic. Bump `versionCode` above 6 and keep `applicationId` identical.

The current native game prototype does not yet render real GTA DFF/TXD geometry
or connect as a playable user to the open.mp game mode. The Android v0.4.2
release is a stabilized asset inspection and map placement preview baseline.
