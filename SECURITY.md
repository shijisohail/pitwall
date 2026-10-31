# Security Policy

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private reporting: on the repository, go to **Security → Report a vulnerability**. Include the version (Pitwall → About), your macOS version, and steps to reproduce.

You can expect an acknowledgement within a few days and a fix or mitigation plan as soon as the report is confirmed. We credit reporters unless they ask us not to.

## Supported versions

Only the latest release receives security fixes while the project is pre-1.0.

## What is in scope

Pitwall runs your own `claude` CLI and reads Claude Code's local files. Issues we care most about:

- Command or argument injection (for example through session ids, file paths, folder names, or transcript content reaching a shell, `Process` arguments or the Terminal hand-off).
- Anything that makes Pitwall read, write or delete files outside the folders you opened and `~/.claude`.
- Any network access, telemetry or data leaving the Mac that is not performed by the `claude` CLI itself.
- Bypassing a confirmation (for example enabling **Full access**, reverting files, or approving a tool without the user acting).
- Unsafe handling of untrusted transcript or model output in the UI.
- Release integrity: signing, notarization, checksums, CI secrets.

## Things that are by design

- **Not sandboxed.** The App Sandbox would block launching your CLI and reading `~/.claude`. The app is signed with the Hardened Runtime and notarized.
- **Full access mode** disables all of Claude Code's permission checks after a confirmation dialog.
- **Transcripts may contain secrets** because Claude Code stores them. Pitwall only reads them locally.

Vulnerabilities in Claude Code itself should go to Anthropic's own disclosure channel.
