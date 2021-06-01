# redis DB


## Scan

* Get total of keys for each slot:

```
> /tmp/slots.txt; \
for X in $(seq 0 16383); do \
  echo -ne "$X: " >> /tmp/slots.txt; \
  redis-cli -h 10.10.103.178 -p 7500 cluster countkeysinslot $X >> /tmp/slots.txt; \
done
```

## Keyspace

* CRC16 calc

```python
In [1]: import crcmod
In [4]: crc16_func = crcmod.mkCrcFun(0x18005)

In [5]: crc16_func('123456789')
Out[5]: 19255


```


http://crcmod.sourceforge.net/crcmod.html
https://redis.io/topics/cluster-spec
http://crcmod.sourceforge.net/crcmod.predefined.html

## Benchmark

https://redis.io/topics/benchmarks

time redis-benchmark -p 7500 -r 1000000 -n 2000000 -q -c 1000 -d 64000

