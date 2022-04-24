EPOCH_NOW=$(ol query --epoch | cut -f2- -d"H" | (cut -f1 -d"-") | sed 's/[^0-9]*//g' | bc)
BIN_PATH="${BIN_PATH:-$HOME/bin}"
SOURCE_PATH="${SOURCE_PATH:-$HOME/libra}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$HOME/epoch-archive}"
DATA_PATH="${DATA_PATH:-$HOME/.0L}"
DB_PATH="${DB_PATH:-${DATA_PATH}/db}"
URL="${URL:-http://localhost}"
EPOCH="${EPOCH:-$((EPOCH_NOW - 1))}"
EPOCH_WAYPOINT=$(jq -r ".waypoints[0]" ${ARCHIVE_PATH}/${EPOCH}/ep*/epoch_ending.manifest)
EPOCH_HEIGHT=$(echo ${EPOCH_WAYPOINT} | cut -d ":" -f 1)

echo epoch-now: $EPOCH_NOW
echo bin-path: $BIN_PATH
echo source-path: $SOURCE_PATH
echo archive-path: $ARCHIVE_PATH
echo data-path: $DATA_PATH
echo db-path: $DB_PATH
echo url: $URL
echo epoch: $EPOCH
echo epoch-waypoint: $EPOCH_WAYPOINT
echo epoch-height: $EPOCH_HEIGHT
echo version: $VERSION

# clone repo
if [ -z "$(ls -A ${ARCHIVE_PATH})" ]; then
    git clone https://github.com/1b5d/epoch-archive.git ${ARCHIVE_PATH} && cd ${ARCHIVE_PATH}
else
    cd ${ARCHIVE_PATH} && git pull
fi

if [ ! -z "$(ls -A ${DB_PATH})" ]; then
    echo DB found! backing up ${DB_PATH} to "${DB_PATH}.bak_$(date +%F_%R)"
    mv ${DB_PATH} "${DB_PATH}.bak_$(date +%F_%R)"
fi

# Restore epoch ending at EPOCH
${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
# Restore state snapshot at EPOCH
${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_${EPOCH_HEIGHT}*/state.manifest --state-into-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
# Restore one transaction at EPOCH
${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

if [ ! -z "$VERSION" ]; then
    # Restore state at VERSION
    ${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/state_ver_${VERSION}*/state.manifest --state-into-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
    # Restore transactions between EPOCH & VERSION
    ${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
fi