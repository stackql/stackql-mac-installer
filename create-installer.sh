#!/usr/bin/env bash
#
# StackQL multi-arch installer for MacOS
#
# Downloads the darwin build artifacts for a given build number from the
# stackql GitHub Actions build workflow, combines them into a universal (fat)
# binary, signs it, creates a signed pkg, notarizes and staples the pkg, then
# uploads the pkg to the matching GitHub release.
#
# usage:
#   bash create-installer.sh <build_number>
#   eg: bash create-installer.sh 669
#
# Machine specific values (signing identities, login keychain password and the
# app specific password used for notarization) are read from vars.sh, which is
# gitignored. See vars.sh.example.
#

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
TARGET_DIR="$SCRIPTPATH/dist"
BIN_DIR="$SCRIPTPATH/bin"
DL_DIR="$SCRIPTPATH/downloads"
CONFIG_DIR="$SCRIPTPATH/config"
RES_DIR="$SCRIPTPATH/resources"
SCRIPTS_DIR="$SCRIPTPATH/scripts"
DATE=`date +%Y-%m-%d`
TIME=`date +%H:%M:%S`
LOG_PREFIX="[$DATE $TIME]"

# github source repo and build workflow (override with env vars if needed)
GH_REPO="${GH_REPO:-stackql/stackql}"
GH_WORKFLOW="${GH_WORKFLOW:-build.yml}"
GH_RUN_LOOKUP_LIMIT="${GH_RUN_LOOKUP_LIMIT:-500}"
ARTIFACT_AMD64="stackql_darwin_amd64"
ARTIFACT_ARM64="stackql_darwin_arm64"
PKG_NAME="stackql_darwin_multiarch.pkg"
PKG_FILE="${TARGET_DIR}/package/${PKG_NAME}"
NOTARY_PROFILE="stackql"

# functions
log_info() {
	echo ""
	echo "${LOG_PREFIX}[INFO]" "$1"
	echo ""
}

log_warn() {
    echo "${LOG_PREFIX}[WARN]" "$1"
}

log_error() {
    echo "${LOG_PREFIX}[ERROR]" "$1"
}

die() {
    log_error "$1"
    exit 1
}

# download a build artifact from the workflow run as a zip file into downloads/
downloadArtifact() {
    local name="$1"
    local dest="${DL_DIR}/${name}.zip"
    local artifact_info artifact_id artifact_expired

    log_info "downloading artifact ${name} from run ${RUN_ID}..."
    artifact_info=$(gh api "repos/${GH_REPO}/actions/runs/${RUN_ID}/artifacts?per_page=100" \
        --jq ".artifacts[] | select(.name == \"${name}\") | \"\(.id) \(.expired)\"")
    [[ -n "$artifact_info" ]] || die "artifact ${name} not found on run ${RUN_ID}"
    artifact_id=$(echo "$artifact_info" | head -n 1 | awk '{print $1}')
    artifact_expired=$(echo "$artifact_info" | head -n 1 | awk '{print $2}')
    [[ "$artifact_expired" == "false" ]] || die "artifact ${name} (id ${artifact_id}) has expired, re-run the build workflow"

    gh api "repos/${GH_REPO}/actions/artifacts/${artifact_id}/zip" > "$dest" || die "could not download artifact ${name}"
    unzip -tq "$dest" >/dev/null 2>&1 || die "${dest} is not a valid zip file"
    echo "downloaded ${dest} ($(du -h "$dest" | cut -f1))"
}

# notarize package using notarytool
notarizefile() {
    filepath=${1:?"need a filepath"}
    identifier=${2:?"need an identifier"}

    # upload file using notarytool and wait for the notarization to complete
    echo "## uploading $filepath for notarization"
    notarization_result=$(xcrun notarytool submit "$filepath" \
                               --keychain-profile "$NOTARY_PROFILE" \
                               --wait \
                               --output-format json)

    notarization_info=$(echo "$notarization_result" | jq -r '.id')
    echo "Notarization Info: $notarization_info"

    # Check if notarization failed
    if [[ $notarization_info == "" ]]; then
        echo "Could not upload for notarization"
        echo "$notarization_result"
        exit 1
    fi

    # Extracting the status
    notarization_status=$(echo "$notarization_result" | jq -r '.status')
    if [[ $notarization_status != "Accepted" ]]; then
        echo "## could not notarize $filepath"
        echo "$notarization_result"
        exit 1
    fi

    echo "## notarization was successful for $filepath"
}

# staple notarization ticket to package using notarytool
staplefile() {
    filepath=${1:?"need a filepath"}
    echo "## stapling ticket to $filepath"
    xcrun stapler staple "$filepath"
    if [[ $? != 0 ]]; then
        echo "## could not staple $filepath"
        exit 1
    fi
    echo "## successfully stapled ticket to $filepath"
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
BUILD_NUMBER="$1"
if [[ -z "$BUILD_NUMBER" ]]; then
    echo "usage: bash $(basename "$0") <build_number>    (eg: bash $(basename "$0") 669)"
    exit 1
fi
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || die "build number must be numeric, got '${BUILD_NUMBER}'"

# ---------------------------------------------------------------------------
# machine specific variables
# ---------------------------------------------------------------------------
if [[ -f "$SCRIPTPATH/vars.sh" ]]; then
    source "$SCRIPTPATH/vars.sh"
fi
for v in DEV_TEAM DEV_ACCOUNT APP_SIGNATURE INST_SIGNATURE KEYCHAIN_PASSWORD APPLE_APP_PASSWORD; do
    [[ -n "${!v}" ]] || die "${v} is not set, add it to ${SCRIPTPATH}/vars.sh (see vars.sh.example)"
done
app_signature="${APP_SIGNATURE}"
inst_signature="${INST_SIGNATURE}"

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
for t in gh unzip lipo codesign pkgbuild xcrun security jq; do
    command -v "$t" >/dev/null 2>&1 || die "required tool '${t}' not found on PATH"
done
gh auth status >/dev/null 2>&1 || die "gh is not authenticated, run 'gh auth login'"

log_info "unlocking keychain and storing notarization credentials..."
security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db || die "could not unlock the login keychain"
xcrun notarytool store-credentials "$NOTARY_PROFILE" \
  --apple-id "$DEV_ACCOUNT" \
  --team-id "$DEV_TEAM" \
  --password "$APPLE_APP_PASSWORD" || die "could not store notarization credentials"

# ---------------------------------------------------------------------------
# clean bin/, downloads/ and dist/ contents
# ---------------------------------------------------------------------------
log_info "cleaning bin/, downloads/ and dist/ contents..."
mkdir -p "$BIN_DIR" "$DL_DIR" "$TARGET_DIR/package" "$TARGET_DIR/archive"
rm -f "$BIN_DIR"/stackql
rm -f "$BIN_DIR"/stackql.gz
rm -f "$BIN_DIR"/stackql_amd64
rm -f "$BIN_DIR"/stackql_arm64
rm -f "$BIN_DIR"/stackql_darwin_arm64.zip
rm -f "$BIN_DIR"/stackql_darwin_amd64.zip
rm -f "$DL_DIR"/*.zip
rm -f "$TARGET_DIR"/archive/stackql*
rm -f "$TARGET_DIR"/package/stackql*

# ---------------------------------------------------------------------------
# step 1-2: locate the build workflow run and download the darwin artifacts
# ---------------------------------------------------------------------------
log_info "looking up build ${BUILD_NUMBER} in ${GH_REPO} (${GH_WORKFLOW})..."
RUN_INFO=$(gh run list --repo "$GH_REPO" --workflow "$GH_WORKFLOW" --limit "$GH_RUN_LOOKUP_LIMIT" \
    --json number,databaseId,headBranch,headSha,conclusion \
    --jq ".[] | select(.number == ${BUILD_NUMBER}) | \"\(.databaseId) \(.headBranch) \(.headSha[0:7]) \(.conclusion)\"")
[[ -n "$RUN_INFO" ]] || die "build ${BUILD_NUMBER} not found in the last ${GH_RUN_LOOKUP_LIMIT} runs of ${GH_WORKFLOW} in ${GH_REPO}"
RUN_ID=$(echo "$RUN_INFO" | head -n 1 | awk '{print $1}')
RUN_BRANCH=$(echo "$RUN_INFO" | head -n 1 | awk '{print $2}')
RUN_SHA=$(echo "$RUN_INFO" | head -n 1 | awk '{print $3}')
RUN_CONCLUSION=$(echo "$RUN_INFO" | head -n 1 | awk '{print $4}')
echo "build ${BUILD_NUMBER} = run ${RUN_ID} (branch ${RUN_BRANCH}, commit ${RUN_SHA}, conclusion ${RUN_CONCLUSION})"
if [[ "$RUN_CONCLUSION" != "success" ]]; then
    log_warn "run ${RUN_ID} conclusion is '${RUN_CONCLUSION}', continuing with whatever artifacts it produced"
fi

downloadArtifact "$ARTIFACT_ARM64"
downloadArtifact "$ARTIFACT_AMD64"

# ---------------------------------------------------------------------------
# step 3: extract the binaries, combine them and get the version
# ---------------------------------------------------------------------------
cd "$BIN_DIR" || die "could not cd to ${BIN_DIR}"

log_info "unzipping ARM build..."
unzip -o "${DL_DIR}/${ARTIFACT_ARM64}.zip" -d "$BIN_DIR" || die "could not unzip ${ARTIFACT_ARM64}.zip"
log_info "renaming ARM build..."
mv stackql stackql_arm64 || die "stackql binary not found in ${ARTIFACT_ARM64}.zip"

log_info "unzipping x64 build..."
unzip -o "${DL_DIR}/${ARTIFACT_AMD64}.zip" -d "$BIN_DIR" || die "could not unzip ${ARTIFACT_AMD64}.zip"
log_info "renaming x64 build..."
mv stackql stackql_amd64 || die "stackql binary not found in ${ARTIFACT_AMD64}.zip"

ls .

# combine
log_info "combining builds..."
lipo -create -output stackql stackql_amd64 stackql_arm64 || die "lipo failed"

# get version
log_info "getting version..."
chmod +x stackql
chmod 755 stackql
VERSION_OUTPUT=$(./stackql --version 2>&1)
echo "$VERSION_OUTPUT"
VERSION=$(echo "$VERSION_OUTPUT" | sed -n -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n 1)
[[ -n "$VERSION" ]] || die "could not parse a semver from the version output above"
VERSION_PATCH="${VERSION##*.}"
[[ "$VERSION_PATCH" == "$BUILD_NUMBER" ]] || die "version ${VERSION} does not match build number ${BUILD_NUMBER}, check the artifacts"
log_info "version ${VERSION}..."

# ---------------------------------------------------------------------------
# step 4-7: check the github release and whether the pkg asset already exists
# ---------------------------------------------------------------------------
RELEASE_TAG="v${VERSION}"
log_info "looking up release ${RELEASE_TAG} in ${GH_REPO}..."
RELEASE_ERR=$(gh release view "$RELEASE_TAG" --repo "$GH_REPO" --json tagName 2>&1 >/dev/null)
RELEASE_RC=$?
if [[ $RELEASE_RC -ne 0 ]]; then
    if echo "$RELEASE_ERR" | grep -qi "release not found"; then
        echo "Release ${VERSION} does not exist, please create it first"
        exit 1
    fi
    die "could not look up release ${RELEASE_TAG}: ${RELEASE_ERR}"
fi

PKG_EXISTS=$(gh release view "$RELEASE_TAG" --repo "$GH_REPO" --json assets \
    --jq "[.assets[].name] | index(\"${PKG_NAME}\") != null")
if [[ "$PKG_EXISTS" == "true" ]]; then
    UPLOAD_PKG="false"
    echo "The ${PKG_NAME} asset already exists in release ${VERSION}, the package will be saved locally for a manual update"
elif [[ "$PKG_EXISTS" == "false" ]]; then
    UPLOAD_PKG="true"
    echo "${PKG_NAME} is not in release ${VERSION} yet, it will be uploaded after packaging"
else
    die "could not list assets for release ${RELEASE_TAG}: ${PKG_EXISTS}"
fi

# ---------------------------------------------------------------------------
# step 8: sign the binary, then create, notarize and staple the pkg
# ---------------------------------------------------------------------------
# sign binary
log_info "signing binary..."
codesign --options=runtime -s "$app_signature" --timestamp stackql || die "codesign failed"

# verify signature
log_info "verifying signature..."
codesign -dv --verbose=4 stackql
codesign --verify --verbose stackql || die "signature verification failed"

# clean bin dir
log_info "cleaning bin/ directory..."
rm -f "$BIN_DIR"/stackql_amd64
rm -f "$BIN_DIR"/stackql_arm64

cd "$SCRIPTPATH" || die "could not cd to ${SCRIPTPATH}"

# create and sign latest package
log_info "creating package..."
pkgbuild --identifier com.stackql.pkg \
--version "${VERSION}" \
--install-location /usr/local/bin \
--sign "$inst_signature" \
--timestamp \
--root "$BIN_DIR" \
"$PKG_FILE" || die "pkgbuild failed"

# notarize package
log_info "notarizing package..."
notarizefile "$PKG_FILE" "com.stackql.pkg"

# staple ticket
log_info "stapling ticket..."
staplefile "$PKG_FILE"

# create versioned package
log_info "creating versioned package..."
cp "$PKG_FILE" "${TARGET_DIR}/package/stackql_${VERSION}_darwin_multiarch.pkg"

# ---------------------------------------------------------------------------
# step 9: upload the pkg to the release (skipped if the asset already exists)
# ---------------------------------------------------------------------------
if [[ "$UPLOAD_PKG" == "true" ]]; then
    log_info "uploading ${PKG_NAME} to release ${RELEASE_TAG}..."
    gh release upload "$RELEASE_TAG" "$PKG_FILE" --repo "$GH_REPO" || die "upload failed, the package is saved at ${PKG_FILE}"
    echo "uploaded ${PKG_NAME} to https://github.com/${GH_REPO}/releases/tag/${RELEASE_TAG}"
else
    log_info "skipping upload, ${PKG_NAME} already exists in release ${RELEASE_TAG}"
    echo "package saved at ${PKG_FILE} for a manual update"
fi

log_info "DONE!!!"
