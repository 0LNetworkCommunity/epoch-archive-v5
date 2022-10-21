# epoch-archive
daily snapshots at each epoch boundary


# NOTE:  You may not need these instructions
There is a restore tool `ol restore`  which covers these steps. The instructions below are for specific interventions.


# Quick Start: Restore


### 1. Build the binaries
The `make` recipes assume your 0L source is at `~/libra`. See ENV vars below for setting custom path

```
git clone https://github.com/OLSF/epoch-archive.git
cd epoch-archive
make bins
```

### 2. Restore from the latest epoch in this archive

#### WILL DESTROY LOCAL DB and NODE.YAML

```
cd epoch-archive
make restore-latest
```

# Quick start: Backup

Create new backup from a remote node (which has backup-service enabled publicly, and epoch must be within the prune window)

```
EPOCH=104 URL=http://[fullnode-ip] make backup-all

```

-----

# The Archive

This repo keeps archives of 0L database at different block heights. The objective is to archive the state of heights at 1) the end of a calendar month 2) at the time of network updades.

The archive is predominantly used for new nodes to join consensus at an advanced waypoint. These backups will also allow for network recovery in catastrophic failure.

# Objective

A prospective node (full or validator) ordinarily needs to sync from the genesis transaction. This is costly and time consuming. A fast sync would start from a known waypoint.
 
A Node's libra DB needs to be "bootstrapped" at the time of the node starting. This is ordinarily done with a genesis.blob if starting from the beginning of the ledger. If catching up from an advanced waypoint, the DB needs to be bootstrapped some other way.

Backups are a way of bootstrapping the DB. There are 3 types of point-in-time backups:
- Epoch Ending
- Transactions
- State Snapshot

All three types of backups are needed to restore and bootstrap a database.


# Backup-cli

The backup cli is composed of two binaries `db-backup` and `db-restore`. These must be compiled and saved to your user directory. `make bins` can do this.

IMPORTANT: The db-restore tool assumes you are running this from the location of your backups (likely the epoch-archive git project)

The manifest file includes OS paths to chunks. Those paths are relative and fail if this is run outside of epoch-archive

Sample commands (from Makefile)

```
# backup-epoch:
	db-backup one-shot backup --backup-service-address ${URL}:6186 epoch-ending --start-epoch ${EPOCH} --end-epoch ${END_EPOCH} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}
	
# backup-transaction:
	db-backup one-shot backup --backup-service-address ${URL}:6186 transaction --num_transactions ${TRANS_LEN} --start-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

# backup-snapshot:
	db-backup one-shot backup --backup-service-address ${URL}:6186 state-snapshot --state-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

# restore-epoch:
	db-restore --target-db-dir ${DB_PATH} epoch-ending --epoch-ending-manifest ${ARCHIVE_PATH}/${EPOCH}/epoch_ending_${EPOCH}*/epoch_ending.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

# restore-transaction:
	db-restore --target-db-dir ${DB_PATH} transaction --transaction-manifest ${ARCHIVE_PATH}/${EPOCH}/transaction_${EPOCH_HEIGHT}*/transaction.manifest local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

# restore-snapshot:
	db-restore --target-db-dir ${DB_PATH} state-snapshot --state-manifest ${ARCHIVE_PATH}/${EPOCH}/state_ver_${EPOCH_HEIGHT}*/state.manifest --state-into-version ${EPOCH_HEIGHT} local-fs --dir ${ARCHIVE_PATH}/${EPOCH}

```


## Makefile

Many of the typical operations of the backup tools (db-restore, db-backup) can be automated with the sample Makefile.

# Node Yaml

For convenience the epoch backups include a fullnode_template.node.yaml which can be used for initializing a node. 

Use `make restore-yaml` to copy to appropriate folder.

# Env Variables

EPOCH:  this variable must be set by user before calling makefile.

`EPOCH=30 make restore-all`

VERSION: this variable must be set by user before calling `backup-version` / `restore-version`:

`EPOCH=30 VERSION=12345 make backup-version`

`EPOCH=30 VERSION=12345 make restore-version`

SOURCE_PATH: optional, the path of libra source, for building bins. Will default to `~/libra`

ARCHIVE_PATH: optional, the path of this repo. Will default to `~/epoch-archive`

DB_PATH: optional for backups only, path to the node's database. Will default  to `~/.0L/db`

URL: optional for backups only, url of backup service. Will default to `http://localhost`. Can use a remote node which has the backup-service-address open to `0.0.0.0/6186`

# Debugging Log messages

The node is trying to catch up with the network
```
2021-03-01T20:08:03.720285Z [state-sync] INFO execution/executor/src/lib.rs:568 sync_request_received {"first_version_in_request":41316059,"local_synced_version":41316058,"name":"chunk_executor","num_txns_in_request":1000}
2021-03-01T20:08:03.749924Z [state-sync] INFO language/libra-vm/src/libra_transaction_executor.rs:627 Executing block, transaction count: 1000 {"first_version":41316059,"name":"execution","txn_id":0}
======================================  round is 998
======================================  round is 999
======================================  round is 1000
======================================  round is 1001
======================================  round is 1002
======================================  round is 1003
======================================  round is 1004
======================================  round is 1005
======================================  round is 1006
======================================  round is 1007
======================================  round is 1008
```

After state sync
```
======================================  round is 38407
2021-03-01T23:58:06.181071Z [state-sync] INFO execution/executor/src/speculation_cache/mod.rs:202 Updated with a new root block {"name":"speculation_cache","root_block_id":"9c04c747c4ac6d9c6fa04dcd18115bf1f32dcfb0fef9bc482182d280f0fcbcf5"}
2021-03-01T23:58:06.181157Z [state-sync] INFO execution/executor/src/lib.rs:614 sync_finished {"committed_with_ledger_info":true,"name":"chunk_executor","synced_to_version":45972972}
2021-03-01T23:58:06.324104Z [state-sync] INFO execution/executor/src/speculation_cache/mod.rs:202 Updated with a new root block {"name":"speculation_cache","root_block_id":"9c04c747c4ac6d9c6fa04dcd18115bf1f32dcfb0fef9bc482182d280f0fcbcf5"}
2021-03-01T23:58:06.324214Z [state-sync] INFO execution/executor/src/lib.rs:568 sync_request_received {"first_version_in_request":45972973,"local_synced_version":45972972,"name":"chunk_executor","num_txns_in_request":1}
2021-03-01T23:58:06.329665Z [state-sync] INFO language/libra-vm/src/libra_transaction_executor.rs:627 Executing block, transaction count: 1 {"first_version":45972973,"name":"execution","txn_id":0}
======================================  round is 38408
```

