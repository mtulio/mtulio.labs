# Resize Machines


`oc` plugin to resize a Machine on OpenShift cluster.

!!! tldr "Important Note"
    - All steps described here will follow the safety way to resize a Machine in OCP 4.x.
    - This is not a official documentation and this plugin was tested on versions 4.9+

## Install

Download the script:

``` shell
curl -o /usr/local/bin/oc-machine_resize https://github.com/mtulio/mtulio.labs/blob/master/labs/ocp-machine-resize-plugin/kubectl-machine_resize
chmod u+x /usr/local/bin/oc-machine_resize
```

Test it:

``` shell
oc machine-resize -h
```

## Commands

### help

`--help`

### list machines

`--list-machines | -l`

### resize machine

`--machine-name <machine_to_resize> --size <new_machine_size> [--force|--continue]`

**Extra args**:

 - `--force` : force to skip healthy checks. Eg if node holds a etcd leader pod
 - `--continue` : continue to stop from broken script. Eg when node was already cordoned/stopped, and not resize from cloud provider. It will skip the initial sanity checks (Eg: Ready node)

## Usage

<script id="asciicast-440747" src="https://asciinema.org/a/440747.js" async></script>

- list current machines

``` shell
oc machine-resize -l
```

- resize  a nachine

``` shell
oc machine-resize -N mrb-gptgl-master-1 -s m5.xlarge
```

- resize a nachine that holds the etcd leader pod

``` shell
oc machine-resize -N mrb-gptgl-master-0 -s m5.xlarge --force
```

## ToDo Next

- support new platforms: Azure
- increase the final healthy checks:
    - check if COs are not degraded
    - check apiserver, etcd pods
    - check etcd cluster: health ndoes, leaders, etc
    - firing alarms?
