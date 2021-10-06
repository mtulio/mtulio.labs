# Resize Machines

<!--
Dev note: This markdown was created to be rendered using mkdocs-material plugin.
Reference of resources enabled on this page:
- https://squidfunk.github.io/mkdocs-material/reference/content-tabs/
- https://squidfunk.github.io/mkdocs-material/reference/admonitions/
-->


## Commands

ToDo

## Usage

- dependency check

``` shell
oc machine-resize
```

- list current machines

``` shell
oc machine-resize -l
```

- resize  a nachine

``` shell
oc machine-resize -N mrb-gptgl-master-1 -s m5.xlarge
```

- resize  a nachine that is etcd leader (not recommended)

``` shell
oc machine-resize -N mrb-gptgl-master-0 -s m5.xlarge --force
```
