# stackql-mac-installer

Creates a multi arch (fat) `pkg` MacOS installer for [stackql](https://github.com/stackql/stackql), notarizes the package with Apple, staples the notarization ticket to the package and uploads it to the matching GitHub release.

## Prerequisites

The script is designed to run on a dedicated packaging Mac. It needs:

- Xcode command line tools (`lipo`, `codesign`, `pkgbuild`, `xcrun notarytool`, `xcrun stapler`)
- Apple Developer ID Application and Developer ID Installer certificates installed in the login keychain
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated with an account that can read workflow artifacts and upload release assets in `stackql/stackql` (`gh auth login`, the default `repo` and `workflow` scopes are sufficient)
- `jq`

## Setup

Copy `vars.sh.example` to `vars.sh` and populate it. `vars.sh` is gitignored and holds the machine specific values: team id, Apple ID, signing identities, the login keychain password and the app specific password used for notarization.

```bash
cp vars.sh.example vars.sh
```

## Usage

Pass the stackql build number, this is the run number of the `Build` workflow in `stackql/stackql` and is the patch component of the version (for example build `669` is `v0.11.669`).

```bash
bash create-installer.sh 669
```

The script will:

1. Unlock the login keychain and store the notarization credentials as the `stackql` notarytool profile
2. Look up the `Build` workflow run for the build number and download the `stackql_darwin_amd64` and `stackql_darwin_arm64` artifacts to `downloads/` (gitignored)
3. Extract both binaries, combine them into a universal binary with `lipo` and read the version from `stackql --version`
4. Look up the GitHub release for the version, if it does not exist the script stops with `Release x.x.x does not exist, please create it first`
5. Check whether `stackql_darwin_multiarch.pkg` and its `.sha256` sidecar are already assets of that release, and read the SHA-256 digest GitHub recorded for the package
6. Sign the binary, build the `pkg`, notarize it and staple the ticket
7. Compute `stackql_darwin_multiarch.pkg.sha256` (sha256sum format) from the stapled package, upload the package and the sidecar to the release and verify the digest GitHub recorded for the attached package, or, if the package already exists, leave it in `dist/package/` for a manual update and upload the sidecar only if the attached package is byte-identical to the local one

Outputs are written to `dist/package/stackql_darwin_multiarch.pkg`, `dist/package/stackql_darwin_multiarch.pkg.sha256` and `dist/package/stackql_<version>_darwin_multiarch.pkg`.

## Configuration

The following can be overridden with environment variables if needed:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GH_REPO` | `stackql/stackql` | Repo to read artifacts from and upload the release asset to |
| `GH_WORKFLOW` | `build.yml` | Workflow whose run number is the build number |
| `GH_RUN_LOOKUP_LIMIT` | `500` | How many recent workflow runs to search for the build number |
