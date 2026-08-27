# BackgroundComputerUse Runtime Notes

Use this reference when the short workflow in `SKILL.md` is not enough.

## Install Modes

Prefer this order:

1. Existing healthy runtime from `$TMPDIR/background-computer-use/runtime-manifest.json`.
2. Local source checkout via `BCU_SOURCE_DIR=/path/to/background-computer-use`.
3. Installed app at `~/Applications/BackgroundComputerUse.app`.
4. App zip via `BCU_APP_ZIP=/path/to/BackgroundComputerUse.app.zip`.
5. Release zip via `BCU_RELEASE_URL=https://.../BackgroundComputerUse.app.zip`, or the default latest GitHub Release asset:

```text
https://github.com/actuallyepic/background-computer-use/releases/latest/download/BackgroundComputerUse.app.zip
```

When using a release zip, set `BCU_RELEASE_SHA256` when possible.

When the manifest runtime is unreachable and the helper falls back to launching the installed app, it first terminates any running `BackgroundComputerUse` process and deletes the stale manifest, so the relaunched runtime publishes a fresh base URL and auth token.

## Permission Contract

macOS Accessibility and Screen Recording permissions attach to the signed app bundle. The helper scripts install and launch the app, but the user may still need to grant permissions in System Settings. Read the manifest first, then trust the authenticated `GET /v1/bootstrap` response:

- `instructions.ready == true`: action routes are available.
- `instructions.ready == false`: report `instructions.user` and recovery guidance to the user.

## Manifest

Runtime metadata is written to:

```text
$TMPDIR/background-computer-use/runtime-manifest.json
```

The manifest includes `baseURL` and `authToken`; clients should not assume a fixed port. Send `authToken` as the `X-Background-Computer-Use-Token` header for every `/v1` request. `/health` is intentionally unauthenticated for liveness checks.

## Route Discovery

Call:

```bash
python3 "$SKILL_DIR/scripts/bcu-request.py" GET /v1/routes
```

Use the route catalog as source of truth for:

- endpoint paths
- request fields
- response fields
- execution policy
- examples
- error codes

This matters because browser routes may or may not be present depending on the installed runtime version.

Application names and bundle IDs are not selectors. Call `list_apps`, choose the exact positive `pid`
for the intended process, and pass only that PID to `list_windows`. If the process exits, discover it
again; the runtime never falls back to a sibling process with the same bundle ID.

## Release Packaging Checklist

For a public install experience:

1. Build a universal macOS app bundle.
2. Sign it with a stable identity.
3. Notarize and staple the app.
4. Zip as `BackgroundComputerUse.app.zip` with `script/package_release.sh`.
5. Publish it as a GitHub Release asset.
6. Publish the SHA-256 checksum.
7. Update install instructions or defaults to point `BCU_RELEASE_URL` and `BCU_RELEASE_SHA256` at that release.

Avoid committing generated app bundles to the skill unless the repo is private and size/security tradeoffs are intentional.
