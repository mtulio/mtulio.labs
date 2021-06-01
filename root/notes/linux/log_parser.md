# Web 

DRAFT Operations in access log file with combined values

## Get RPS from an specific time

 ```bash
 grep "15/Nov/2017:20" /var/log/apache2/*-access.log | cut -d[ -f2 | cut -d] -f1 | awk -F: '{print $2":"$3}' | sort -nk1 -nk2 | uniq -c | awk '{ if ($1 > 10) print $0}'
 ```
 

### Get Codes

```bash
awk -F'"' '{print $3}' /var/log/apache2/*-access.log  |awk '{print$1}' |sort |uniq -c
```


### Get top10 slow requests

```bash
cat -n *-access.log |awk -F']' '{print$2}' |awk -F'" ' '{print$5" "$1" "$2" "$3}' |tr -d '"' |sort -n |tail -n 10`
```

### Get top10 slow requests

CODE METHOD TIME PATH

```bash
cat -n *-access.log |awk -F']' '{print$2}' |awk -F'" ' '{print $2" "$1" "$5" "$3}' |tr -d '"' |awk '{print$1" "$4" "$7" "$5}'
```

By time
```bash
cat -n *-access.log |awk -F']' '{print$2}' |awk -F'" ' '{print $2" "$1" "$5" "$3}' |tr -d '"' |awk '{print$5" "$1" "$4" "$7"}'
```

Each file by top10

```bash
for F in $(ls *-access.log); do
  echo "##>> Top10 slowl of FILE: $F"
  cat -n $F |awk -F']' '{print$2}' |awk -F'" ' '{print $2" "$1" "$5" "$3}' |tr -d '"' |awk '{print$7" "$1" "$4" "$5}' |sort -n |tail -n 10
done
```

### Check apache mem uasge

```bash
 sudo ps -ylC apache2 | awk '{x += $8;y += 1} END {print "Apache Memory Usage (MB): "x/1024; print "Average Process Size (MB): "x/((y-1)*1024)}
```
