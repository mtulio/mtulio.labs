# MongoDB

## Configuration

* Params https://docs.mongodb.com/manual/reference/parameters/#param.maxTransactionLockRequestTimeoutMillis
* Config https://docs.mongodb.com/v3.2/reference/replica-configuration/#rsconf.settings.electionTimeoutMillis

## Installer

* Install older version

```bash
rpm -e --noscripts mongodb-org-server-3.2.21-1.el7.x86_64
yum list mongodb-org* --showduplicates
yum install mongodb-org-3.2.19
```

## Tunning

* Kernel

* Block Device

## Common Ops

### Replica Set

* States: https://docs.mongodb.com/manual/reference/replica-states/

* Check status

* Change rset config 

> Eg. change the prio of the member

```bash
cfg = rs.conf()
cfg.members[1].priority = 1.5
cfg
rs.reconfig(cfg)
rs.status()
```

* change oplog size

https://docs.mongodb.com/v3.2/tutorial/change-oplog-size/

* Check collections config

`mongos> db.getSiblingDB("config").collections.find();`

`mongo --quiet --eval 'var c = db.getSiblingDB("config").collections.find(); c.forEach(printjsononeline)'`


#### Shutdown

* on the slaves

```
use admin
db.shutdownServer()
```

* on the master [last]

```
rs.stepDown(300)
```

### Cheat Sheet

#### `currentOp`

https://hackernoon.com/mongodb-currentop-18fe2f9dbd68

#### `shutdown'

> https://docs.mongodb.com/manual/tutorial/manage-mongodb-processes/#use-shutdownserver

```bash
use admin
db.shutdownServer()
```

### Shards

* References

https://docs.mongodb.com/manual/core/sharded-cluster-shards/


## MISC

* https://docs.mongodb.com/manual/tutorial/deploy-geographically-distributed-replica-set/

