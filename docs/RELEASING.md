# Releasing

Releases are built, signed with a **Developer ID Application** certificate, notarized by Apple, stapled, checksummed and attached to a GitHub Release by `.github/workflows/release.yml`. You can run the same steps locally with `Scripts/release.sh`.

> Pitwall is distributed **outside the Mac App Store** (it cannot be sandboxed; see [ARCHITECTURE.md](ARCHITECTURE.md)).

## No Apple Developer account? Ship an unsigned DMG

You can publish without signing or notarizing:

```sh
UNSIGNED=1 Scripts/release.sh        # dist/Pitwall-<version>.dmg and .sha256 (ad-hoc signed)
```

The release workflow does the same automatically when the `DEVELOPER_ID_CERT_P12_BASE64` secret is not set, and marks the GitHub release as a **pre-release**. The DMG runs normally on the Mac that built it. On other Macs Gatekeeper blocks it until the user approves it under *System Settings → Privacy & Security → Open Anyway* (instructions are in the README). Add signing later without changing anything else: set the secrets below and the same workflow switches to Developer ID + notarization.

## One-time setup (signed releases)

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

## Going public checklist

Settings that cannot be changed from a pull request:

- [ ] **Make the repository public** (Settings → General → Danger Zone). Until then release downloads need a GitHub login.
- [ ] **Social preview:** Settings → General → *Social preview* → upload `docs/assets/social-preview.png` (1280×640). GitHub has no API for this. Regenerate it with `Scripts/make-social-preview.swift`.
- [ ] **Topics and description** are already set (20 topics). Revisit them if the product changes.
- [ ] **GitHub Pages:** Settings → Pages → *Deploy from a branch* → `main` / `/docs`. The landing page is `docs/index.html` and is served at `https://shijisohail.github.io/pitwall/`. Then set the repository *Website* to that URL, and link it from the README.
- [ ] **Search Console:** add the Pages URL as a property and submit `https://shijisohail.github.io/pitwall/sitemap.xml`.
- [ ] **Branch protection** on `main`: require the `build-and-test` check and a pull request.
- [ ] **Private vulnerability reporting:** Settings → Code security, so [SECURITY.md](../SECURITY.md) and the Code of Conduct contact work.
- [ ] Optional: enable **Discussions** for questions, and pin the v1.0.0 release.

## Release checklist

- [ ] `swift test` and `Scripts/build.sh` pass; CI is green
- [ ] Manually: open a project, send a prompt, approve a tool, open two tabs, switch model, stop a run, open in Terminal
- [ ] README screenshots and `PRIVACY.md` still accurate
- [ ] `docs/CLAUDE_CODE_PROTOCOL.md` verified against the current Claude Code version
- [ ] Notarization and Gatekeeper checks above pass on a clean machine
