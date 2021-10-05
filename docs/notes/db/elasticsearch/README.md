# HowTO Elasticsearch

## API Rest

### Get node cluster info

```shell
  curl http://${NODE_NAME}:9200/
```

### Get nodes 

```shell
  curl http://${NODE_NAME}:9200/_nodes
```

### Allocate shards to an node

```shell
curl -XPOST -d '{ "commands" : [ {
  "allocate" : {
       "index" : "${INDEX_NAME}", 
       "shard" : ${SHARD_ID}, 
       "node" : "${NODE_NAME}-${CLUSTER_NAME}",
       "allow_primary":true 
     } 
  } ] }' http://${NODE_NAME}:9200/_cluster/reroute?pretty
```

Change/Where:
 - NODE_NAME
 - CLUSTER_NAME
 - SHARD_ID
 - INDEX_NAME

* Refs and credits: 
  * https://www.elastic.co/guide/en/elasticsearch/reference/current/disk-allocator.html
  * https://www.datadoghq.com/blog/elasticsearch-unassigned-shards/
 
### Remove nodes from an Cluster "gracefully"

```bash
curl -XPUT ONE_ES_NODE:9200/_cluster/settings -d '{
  "transient" :{
    "cluster.routing.allocation.exclude._ip" : "ES_NODE_IP_TO_REMOVE"
  }
}';echo
```

* Refs and credits:
  * https://logz.io/blog/elasticsearch-cheat-sheet/

### settings.index.routing.allocation.disable_allocation - Get all

```bash
ES_FQDN=myServer.com
for I in $(curl -s "http://$ES_FQDN:9200/_all/_settings" |jq 'keys[]'); 
do 
  I=$(echo $I |tr -d '"')
  echo $I/disable_allocation=$(curl  -s "http://$ES_FQDN:9200/$I/_settings/index.routing.allocation.disable_allocation" |jq .$I.settings.index.routing.allocation.disable_allocation)
done
```
### settings.index.routing.allocation.disable_allocation - Change all to false

> TODO


## PLUGINS

### Install kopf

> TODO
