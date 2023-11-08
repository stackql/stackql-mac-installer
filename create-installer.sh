#
# StackQL multi-arch installer for MacOS
#

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
TARGET_DIR="$SCRIPTPATH/dist"
BIN_DIR="$SCRIPTPATH/bin"
CONFIG_DIR="$SCRIPTPATH/config"
RES_DIR="$SCRIPTPATH/resources"
SCRIPTS_DIR="$SCRIPTPATH/scripts"
DATE=`date +%Y-%m-%d`
TIME=`date +%H:%M:%S`
LOG_PREFIX="[$DATE $TIME]"
#RESP=`curl https://api.github.com/repos/stackql/${REPO}/actions/artifacts \
#   -H "Authorization: Token $GH_TOKEN"`
dev_account="${DEV_ACCOUNT}"
app_signature="${APP_SIGNATURE}"
inst_signature="${INST_SIGNATURE}"
dev_team="${DEV_TEAM}"
app_spec_pwd="${APP_SPECIFIC_PASSWORD}"

# functions
log_info() {
	echo ""
	echo "${LOG_PREFIX}[INFO]" $1
	echo ""
}

log_warn() {
    echo "${LOG_PREFIX}[WARN]" $1
}

log_error() {
    echo "${LOG_PREFIX}[ERROR]" $1
}

function downloadBuild() {
log_info "getting latest build for $1"
echo $RESP | jq .artifacts | jq -c '.[]' | while read i; do
 buildname=`echo $i | jq .name | tr -d '"'`
 echo "buildname = $buildname"
 if [ "$buildname" == "$1" ]; then
  url=`echo $i | jq .archive_download_url | tr -d '"'`
  echo "url = $url"
  echo "BIN_DIR = $BIN_DIR"
  # wget -O $BIN_DIR/$1.zip --header="Authorization: Token $GH_TOKEN" $url
  curl -o $BIN_DIR/$1.zip -H "Authorization: Token $GH_TOKEN" "$url"
  break
 fi
done
}

requeststatus() { # $1: requestUUID
    requestUUID=${1?:"need a request UUID"}
    req_status=$(xcrun altool --notarization-info "$requestUUID" \
                              --username "$dev_account" \
                              --password "$app_spec_pwd" 2>&1 \
                 | awk -F ': ' '/Status:/ { print $2; }' )
    echo "$req_status"
}

notarizefile() { # $1: path to file to notarize, $2: identifier
    filepath=${1:?"need a filepath"}
    identifier=${2:?"need an identifier"}

    # upload file
    echo "## uploading $filepath for notarization"
    requestUUID=$(xcrun altool --notarize-app \
                               --primary-bundle-id "$identifier" \
                               --username "$dev_account" \
                               --password "$app_spec_pwd" \
                               --asc-provider "$dev_team" \
                               --file "$filepath" 2>&1 \
                  | awk '/RequestUUID/ { print $NF; }')

    echo "Notarization RequestUUID: $requestUUID"

    if [[ $requestUUID == "" ]]; then
        echo "could not upload for notarization"
				xcrun altool --notarize-app \
		                               --primary-bundle-id "$identifier" \
		                               --username "$dev_account" \
		                               --password "$app_spec_pwd" \
		                               --asc-provider "$dev_team" \
		                               --file "$filepath"
        exit 1
    fi

    # wait for status to be not "in progress" any more
    request_status="in progress"
    while [[ "$request_status" == "in progress" ]]; do
        echo -n "waiting... "
        sleep 10
        request_status=$(requeststatus "$requestUUID")
        echo "$request_status"
    done

		if [[ $request_status != "success" ]]; then
        echo "## could not notarize $filepath"
				echo $request_status
        exit 1
    fi

    # print status information
    xcrun altool --notarization-info "$requestUUID" \
                 --username "$dev_account" \
                 --password "$app_spec_pwd"
    echo
}

# clean bin and target dirs
log_info "deleting bin/ and target/ contents..."
rm -f $BIN_DIR/stackql
rm -f $BIN_DIR/stackql.gz
rm -f $BIN_DIR/stackql_amd64
rm -f $BIN_DIR/stackql_arm64
#rm -f $BIN_DIR/stackql_darwin_arm64.zip
#rm -f $BIN_DIR/stackql_darwin_amd64.zip
rm -f $TARGET_DIR/archive/stackql*
rm -f $TARGET_DIR/package/stackql*

# download mac builds
log_info "downloading ARM build..."
#downloadBuild "stackql_darwin_arm64"

log_info "downloading x64 build..."
#downloadBuild "stackql_darwin_amd64"

# unzip binaries
cd $BIN_DIR

log_info "unzipping ARM build..."
unzip stackql_darwin_arm64.zip
log_info "renaming ARM build..."
mv stackql stackql_arm64

log_info "unzipping x64 build..."
unzip stackql_darwin_amd64.zip
log_info "renaming x64 build..."
mv stackql stackql_amd64

ls .

read -p "press any key to continue"

# combine
log_info "combining builds..."
lipo -create -output stackql stackql_amd64 stackql_arm64

# get version
log_info "getting version..."
chmod +x stackql
chmod 755 stackql
VERSION=`./stackql --version 2>&1 | head -n 1 | cut -dv -f2 | cut -d' ' -f1`
log_info "version ${VERSION}..."

# sign binary
log_info "signing binary..."
codesign --options=runtime -s "$app_signature" --timestamp stackql

# verify signature
log_info "verifying signature..."
codesign -dv --verbose=4 stackql

# clean root dir
log_info "cleaning bin/ directory..."
rm $BIN_DIR/stackql_amd64
rm $BIN_DIR/stackql_arm64
rm $BIN_DIR/stackql_darwin_arm64.zip
rm $BIN_DIR/stackql_darwin_amd64.zip

cd $SCRIPTPATH

# create and sign latest package
log_info "creating package..."
pkgbuild --identifier com.stackql.pkg \
--version ${VERSION} \
--install-location /usr/local/bin \
--sign "$inst_signature" \
--timestamp \
--root $BIN_DIR \
${TARGET_DIR}/package/stackql_darwin_multiarch.pkg

# notarize package
log_info "notarizing package..."
notarizefile "${TARGET_DIR}/package/stackql_darwin_multiarch.pkg" "com.stackql.pkg"

# staple ticket
log_info "stapling ticket..."
xcrun stapler staple "${TARGET_DIR}/package/stackql_darwin_multiarch.pkg"

# create versioned package
log_info "creating versioned package..."
cp "${TARGET_DIR}/package/stackql_darwin_multiarch.pkg" "${TARGET_DIR}/package/stackql_${VERSION}_darwin_multiarch.pkg"

log_info "DONE!!!"
