# vdo


## Maintenance

### Discarding Unused Blocks

- Perform a batch discard 

Syntax:
~~~
fstrim mount-point
~~~

Example:
~~~
df -h /mnt/data/ && sudo vdostats --human-readable
fstrim /mnt/data
df -h /mnt/data/ && sudo vdostats --human-readable
~~~

## References

- [CHAPTER 2. MAINTAINING VDO](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/deduplicating_and_compressing_storage/maintaining-vdo_deduplicating-and-compressing-storage)
- [CHAPTER 5. DISCARDING UNUSED BLOCKS](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/deduplicating_and_compressing_storage/discarding-unused-blocks_deduplicating-and-compressing-storage)


