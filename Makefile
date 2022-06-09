SHELL=/usr/bin/env bash

ifndef BIN_PATH
BIN_PATH=~/bin
endif

ifndef SOURCE_PATH
SOURCE_PATH=~/libra
endif

ifndef ARCHIVE_PATH
ARCHIVE_PATH=~/epoch-archive
endif

ifndef DATA_PATH
DATA_PATH=~/.0L
endif

ifndef DB_PATH
DB_PATH=${DATA_PATH}/db
endif

ifndef URL
URL=http://localhost
endif

ifndef EPOCH
EPOCH=$(shell expr ${EPOCH_NOW} - 1)
endif

ifndef EPOCH_LEN
EPOCH_LEN = 1
endif

ifndef TRANS_LEN
TRANS_LEN = 100
endif



EPOCH_NOW := $(shell db-backup one-shot query node-state | cut -d ":" -d "," -f 1 | cut -d ":" -f 2| xargs)

DB_VERSION := $(shell db-backup one-shot query node-state | cut -d ":" -d "," -f 2 | cut -d ":" -f 2| xargs)

LATEST_BACKUP = $(shell ls -a ~/epoch-archive/ | sort -n | tail -1 | tr -dc '0-9')

NEXT_BACKUP = $(shell expr ${LATEST_BACKUP} + 1)

END_EPOCH = $(shell expr ${EPOCH} + ${EPOCH_LEN})

EPOCH_WAYPOINT := $(shell ol query --epoch | cut -d ":" -f 2-3| xargs)

ifndef EPOCH_HEIGHT
EPOCH_HEIGHT = $(shell echo ${EPOCH_WAYPOINT} | cut -d ":" -f 1)
endif

EPOCH_HEIGHT_FOR_RESTORE = $(shell jq -r ".waypoints[0]" ${ARCHIVE_PATH}/${EPOCH}/ep*/epoch_ending.manifest | cut -d ":" -f 1)

# the version to take the snapshot of. Get 100 versions/transactions after the epoch boundary
# EPOCH_SNAPSHOT_VERSION = $(shell expr ${EPOCH_HEIGHT} + 100)

ifndef VERSION
VERSION = ${DB_VERSION}
endif

check:
	@if test -z ${EPOCH}; then \
		echo "Must provide EPOCH in environment" 1>&2; \
	 	exit 1; \
	fi
	@echo data-path: ${DATA_PATH}
	@echo target-db: ${DB_PATH}
	@echo backup-service-url: ${URL}
	@echo start-epoch: ${EPOCH}
	@echo epoch-now: ${EPOCH_NOW}
	@echo end-epoch: ${END_EPOCH}
	@echo epoch-waypoint: ${EPOCH_WAYPOINT}
	@echo epoch-height: ${EPOCH_HEIGHT}
	@echo epoch-height-for-restore: ${EPOCH_HEIGHT_FOR_RESTORE}
	@echo db-version: ${DB_VERSION}
	@echo env-versions: ${VERSION}
wipe:
	sudo rm -rf ${DB_PATH}

create-folder: check
	@if test ! -d ${ARCHIVE_PATH}/${EPOCH}; then \
		mkdir ${ARCHIVE_PATH}/${EPOCH}; \
	fi

create-version-folder: check
	@if test -z ${VERSION}; then \
	 	echo "Must provide VERSION in environment" 1>&2; \
	 	exit 1; \
	fi
	@if test ! -d ${ARCHIVE_PATH}/${EPOCH}/${VERSION}; then \
		mkdir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}; \
	fi

bins:
	cd ${SOURCE_PATH} && cargo build -p backup-cli --release
	cp -f ${SOURCE_PATH}/target/release/db-restore /usr/local/bin/db-restore
	cp -f ${SOURCE_PATH}/target/release/db-backup /usr/local/bin/db-backup

commit:
# save to epoch archive repo for testing
	git add -A && git commit -a -m "epoch archive ${EPOCH} - ${EPOCH_WAYPOINT} - ${VERSION}" && git push

zip:
# zip -r ${EPOCH}.zip ${EPOCH}
	tar -czvf ${EPOCH}.tar.gz ${EPOCH}

epoch:
	@echo ${EPOCH_NOW}

restore-all: restore-epoch restore-transaction restore-snapshot restore-waypoint restore-yaml
	# Destructive command. node.yaml, and db will be wiped.

restore-latest:
	export EPOCH=$(shell ls | sort -n | tail -1) && make restore-all restore-yaml

backup-all: backup-epoch backup-transaction backup-snapshot

backup-epoch: create-folder
# IMPORTANT: The db-restore tool assumes you are running this from the location of your backups (likely the epoch-archive git project)
# The manifest file includes OS paths to chunks. Those paths are relative and fail if this is run outside of epoch-archive

	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 epoch-ending --start-epoch ${EPOCH} --end-epoch ${END_EPOCH} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

backup-transaction: create-folder
# Get 200 transactions. Half on on each side of the epoch boundary
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 transaction --num_transactions 200 --start-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

backup-snapshot: create-folder

	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 state-snapshot --state-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

backup-version: create-version-folder
# IMPORTANT: this assumes that EPOCH is already backed up
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 transaction --num_transactions 1  --start-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 state-snapshot --state-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}

restore-epoch:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-transaction:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-snapshot:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_*/state.manifest --state-into-version ${EPOCH_HEIGHT_FOR_RESTORE} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-waypoint:
	@echo ${EPOCH_WAYPOINT} > ${DATA_PATH}/restore_waypoint

restore-yaml:
	@if test ! -d ${DATA_PATH}; then \
		mkdir ${DATA_PATH}; \
	fi
	cp ${ARCHIVE_PATH}/fullnode_template.node.yaml ${DATA_PATH}/node.yaml
	sed 's/THE_WAYPOINT/${EPOCH_WAYPOINT}/g' ${DATA_PATH}/node.yaml

restore-version: restore-all
# ${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
# ${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_${EPOCH_HEIGHT}*/state.manifest --state-into-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
# ${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/state_ver_${VERSION}*/state.manifest --state-into-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/transaction_${VERSION}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}

cron:
	cd ~/epoch-archive/ && git pull && EPOCH=${NEXT_BACKUP} make backup-all zip commit

cron-hourly:
	cd ~/epoch-archive/ && git pull && EPOCH=${LATEST_BACKUP} VERSION=${DB_VERSION} make backup-version zip commit

