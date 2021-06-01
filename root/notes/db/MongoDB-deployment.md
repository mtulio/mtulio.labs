# MongoDB Sharded Deployment

* MongoDB components

mongod
mongo config
mongos

* Architecture

      development ()
      standalone
      rset (odd nodes)
      sharded (odd nodes)
      config nodes / arbiters
      mongos on app server
      mongos as centralized router

* Filesystem


* Replication

* Sharding


* Production checklist (HandsOn) [OS]

      [Main](https://docs.mongodb.com/manual/administration/production-checklist-operations/)
      [FS XFS]
      [THP](https://docs.mongodb.com/manual/tutorial/transparent-huge-pages/)
      [readahead](https://docs.mongodb.com/manual/administration/production-notes/#readahead)
      blockdev --getra /dev/nvme1n1
      [Disble tuned on RHEL]
      [disable noop on the data  disk scheduler 
      [disable NUMA] sysctl -a |grep vm.zone_reclaim_mode
      https://www.anchor.com.au/blog/2012/09/noop-io-scheduling-with-ssd-storage/
      [Adjust the ulimit ]
      [Use noatime for the dbPath mount point.]
      [sysctl]
      fs.file-max value of 98000,
      kernel.pid_max value of 64000,
      kernel.threads-max value of 64000, and
      vm.max_map_count value of 128000
      [adjust the swap according to the OS]
      [keep alive]
      net.ipv4.tcp_keepalive_time 300


* Monitoring

      Node  
      MongoDB
      -> exporter
      -> commands
      -> alerts
      lock percent (for the MMAPv1 storage engine)
      replication lag
      replication oplog window
      assertions
      queues
      page faults

* Load Balancing (https://docs.mongodb.com/manual/administration/production-checklist-operations/#load-balancing)


Advanced ref: https://docs.mongodb.com/manual/administration/production-notes/#readahead
