# Releasing

Releases are built, signed with a **Developer ID Application** certificate, notarized by Apple, stapled, checksummed and attached to a GitHub Release by `.github/workflows/release.yml`. You can run the same steps locally with `Scripts/release.sh`.

> Pitwall is distributed **outside the Mac App Store** (it cannot be sandboxed; see [ARCHITECTURE.md](ARCHITECTURE.md)).

## One-time setup

1. **Apple Developer Program** membership.
2. **Developer ID Application certificate.** Create it in your developer account, install it in Keychain Access, then export it as a `.p12` with a password.
3. **Notarization credentials.** Create an App Store Connect API key (App Store Connect → Users and Access → Integrations → Keys) with the *Developer* role. Keep the `.p8`, the Key ID and the Issuer ID.
4. **Choose your identifiers** and set them (the build refuses to release with the `OWNER` placeholders):
   - `BUNDLE_ID`, a reverse-DNS id you control.
   - `PITWALL_REPO_URL`, the GitHub URL (shown in the Help menu).
5. **GitHub repository settings.** Create an environment named `release` (add required reviewers if you want a manual gate), then add:

   | Kind | Name | Value |
   |---|---|---|
   | secret | `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i cert.p12` |
   | secret | `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` password |
   | secret | `SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
   | secret | `NOTARY_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` |
   | secret | `NOTARY_KEY_ID` | the Key ID |
   | secret | `NOTARY_ISSUER` | the Issuer ID |
   | variable | `BUNDLE_ID` | your bundle id |
   | variable | `PITWALL_REPO_URL` | your repo URL |

   Also enable **private vulnerability reporting** (Settings → Code security) so [SECURITY.md](../SECURITY.md) works, and set the contact in `CODE_OF_CONDUCT.md`.
6. Check the runner label in the workflows (`macos-26`) exists for your account; it must provide Xcode with the macOS 26 SDK.

## Cutting a release

1. Move the `CHANGELOG.md` entries from **Unreleased** to a new version heading.
2. Set the version in `VERSION` (for example `0.2.0`) and commit.
3. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`. The workflow refuses to run if the tag and `VERSION` disagree.
4. When it finishes, download the DMG from the draft or published release and run the checks below on a clean Mac.

## Verifying a build

```sh
spctl --assess --type open --context context:primary-signature -vv Pitwall-X.Y.Z.dmg   # accepted, Notarized Developer ID
xcrun stapler validate Pitwall-X.Y.Z.dmg
codesign --verify --deep --strict --verbose=2 /Applications/Pitwall.app
codesign -dv --verbose=4 /Applications/Pitwall.app 2>&1 | grep -E "flags|Authority"      # runtime flag, your Developer ID
shasum -a 256 -c Pitwall-X.Y.Z.dmg.sha256
```

## Local dry run

```sh
SIGN_IDENTITY="Developer ID Application: …" BUNDLE_ID=com.you.pitwall SKIP_NOTARIZE=1 Scripts/release.sh
```

## Release checklist

- [ ] `swift test` and `Scripts/build.sh` pass; CI is green
- [ ] Manually: open a project, send a prompt, approve a tool, open two tabs, switch model, stop a run, open in Terminal
- [ ] README screenshots and `PRIVACY.md` still accurate
- [ ] `docs/CLAUDE_CODE_PROTOCOL.md` verified against the current Claude Code version
- [ ] Notarization and Gatekeeper checks above pass on a clean machine
