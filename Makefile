SHELL=/usr/bin/env bash

EPOCH_NOW = $(shell ol query --epoch | cut -f2- -d"H" | (cut -f1 -d"-") | sed 's/[^0-9]*//g' | bc)

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
TRANS_LEN = 1
endif


LATEST_BACKUP = $(shell ls -a ~/epoch-archive/ | sort -n | tail -1 | tr -dc '0-9')

NEXT_BACKUP = $$((${LATEST_BACKUP} + 1)) 

END_EPOCH = $(shell expr ${EPOCH} + ${EPOCH_LEN})

EPOCH_WAYPOINT = $(shell jq -r ".waypoints[0]" ${ARCHIVE_PATH}/${EPOCH}/ep*/epoch_ending.manifest)

EPOCH_HEIGHT = $(shell echo ${EPOCH_WAYPOINT} | cut -d ":" -f 1)

check:
	@echo ${EPOCH_NOW}
	# @if test -z "$$EPOCH"; then \
	# 	echo "Must provide EPOCH in environment" 1>&2; \
	# 	exit 1; \
	# fi
	# @echo data-path: ${DATA_PATH}
	# @echo target-db: ${DB_PATH}
	# @echo backup-service-url: ${URL}
	# @echo start-epoch: ${EPOCH}
	# @echo end-epoch: ${END_EPOCH}
	# @echo epoch-height: ${EPOCH_HEIGHT}

wipe:
	sudo rm -rf ${DB_PATH}

create-folder: check
	@if test ! -d ${ARCHIVE_PATH}/${EPOCH}; then \
		mkdir ${ARCHIVE_PATH}/${EPOCH}; \
	fi

create-version-folder: check
	@if test -z "$$VERSION"; then \
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
	#save to epoch archive repo for testing
	git add -A && git commit -a -m "epoch archive ${EPOCH} - ${EPOCH_WAYPOINT}" && git push

zip:
# zip -r ${EPOCH}.zip ${EPOCH}
	tar -czvf ${EPOCH}.tar.gz ${EPOCH}

epoch:
	@echo ${EPOCH_NOW}

restore-all: wipe restore-epoch restore-transaction restore-snapshot restore-waypoint restore-yaml
	# Destructive command. node.yaml, and db will be wiped.

restore-latest:
	export EPOCH=$(shell ls | sort -n | tail -1) && make restore-all restore-yaml

backup-all: backup-epoch backup-transaction backup-snapshot

backup-epoch: create-folder
# IMPORTANT: The db-restore tool assumes you are running this from the location of your backups (likely the epoch-archive git project)
# The manifest file includes OS paths to chunks. Those paths are relative and fail if this is run outside of epoch-archive

	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 epoch-ending --start-epoch ${EPOCH} --end-epoch ${END_EPOCH} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

backup-transaction: create-folder
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 transaction --num_transactions ${TRANS_LEN} --start-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

backup-snapshot: create-folder
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 state-snapshot --state-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-epoch:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-transaction:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-snapshot:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_${EPOCH_HEIGHT}*/state.manifest --state-into-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

restore-waypoint:
	@echo ${EPOCH_WAYPOINT} > ${DATA_PATH}/restore_waypoint

restore-yaml:
	@if test ! -d ${DATA_PATH}; then \
		mkdir ${DATA_PATH}; \
	fi
	cp ${ARCHIVE_PATH}/fullnode_template.node.yaml ${DATA_PATH}/node.yaml
	sed 's/THE_WAYPOINT/${EPOCH_WAYPOINT}/g' ${DATA_PATH}/node.yaml

backup-version: create-version-folder
# IMPORTANT: this assumes that EPOCH is already backed up
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 transaction --num_transactions $(shell expr ${VERSION} - ${EPOCH_HEIGHT} + 1) --start-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
	${BIN_PATH}/db-backup one-shot backup --backup-service-address ${URL}:6186 state-snapshot --state-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}

restore-version:
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_${EPOCH_HEIGHT}*/state.manifest --state-into-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/state_ver_${VERSION}*/state.manifest --state-into-version ${VERSION} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}
	${BIN_PATH}/db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/${VERSION}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}/${VERSION}


prod-backup:
	URL=http://34.130.64.207 make backup-all

devnet-backup:
	URL=http://157.230.15.42 make backup-all

cron:
	cd ~/epoch-archive/ && git pull && EPOCH=${NEXT_BACKUP} make backup-all zip commit |& tee ~/.0L/logs/backup.log
