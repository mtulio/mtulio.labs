# systemd and their subsystems 

![alt text](https://lcom.static.linuxfound.org/images/stories/41373/Systemd-components.png "Sys")

> Most of these explanations comes from [public articles referenced here](#external-reference), all rights to it. =)


systemd is a Linux initialization system and service manager that includes features like on-demand starting of daemons, mount and automount point maintenance, snapshot support, and processes tracking using Linux control groups. systemd provides a logging daemon and other tools and utilities to help with common system administration tasks.

**The Linux Boot Process and systemd**

Linux requires an initialization system during its boot and startup process. At the end of the boot process, the Linux kernel loads systemd and passes control over to it and the startup process begins. During this step, the kernel initializes the first user space process, the systemd init process with process ID 1, and then goes idle unless called again. systemd prepares the user space and brings the Linux host into an operational state by starting all other processes on the system.

Below is a simplified overview of the entire Linux boot and startup process:

1. The system powers up. 1 The BIOS does minimal hardware initialization and hands over control to the boot loader.
1. The boot loader calls the kernel.
1. The kernel loads an initial RAM disk that loads the system drives and then looks for the root file system.
1. Once the kernel is set up, it begins the systemd initialization system.
1. systemd takes over and continues to mount the host’s file systems and start services.

# hostnamed

> Most of info comes from [hostnamed wiki](https://www.freedesktop.org/wiki/Software/systemd/hostnamed/)

This is a tiny daemon that can be used to control the host name and related machine meta data from user programs. It currently offers access to five variables:

1. The current host name (Example: dhcp-192-168-47-11)
1. The static (configured) host name (Example: lennarts-computer)
1. The static (configured) host name (Example: lennarts-computer)
The pretty host name (Example: Lennart's Computer)
1. The static (configured) host name (Example: lennarts-computer)
1. The static (configured) host name (Example: lennarts-computer)
A suitable icon name for the local host (Example: computer-laptop)
1. The static (configured) host name (Example: lennarts-computer)
A chassis type (Example: "tablet")

The daemon is accessible via D-Bus:

> ***D-Bus (for "Desktop Bus"), a software bus, is an inter-process communication (IPC) and remote procedure call (RPC) mechanism that allows communication between multiple computer programs (that is, processes) concurrently running on the same machine.*** [D-Bus wiki](https://en.wikipedia.org/wiki/D-Bus)

* Sample:

`dbus introspect --system --dest org.freedesktop.hostname1 --object-path /org/freedesktop/hostname1`



# Commands

## systemctl

### Unit Types

* `service`: System services
* `target`: group of units
* `automount`: filesystem auto-mountpoint
* `device`: kernel device names, which you can see in sysfs and udev
* `mount`: filesystem mountpoint
* `path`: file or directory
* `scope`: external processes not started by systemd
* `slice`: a management unit of processes
* `socket`: IPC (inter-process communication) socket
* `swap`: swap file
* `timer`: systemd timer.
* Snapshot: systemd saved state

### cheatset

```bash
# systemctl start [name.service][
# systemctl stop [name.service]
# systemctl restart [name.service]
# systemctl reload [name.service]
$ systemctl status [name.service]
# systemctl is-active [name.service]
$ systemctl list-units --type service --all
```

#### unit files

`systemctl list-unit-files`

`systemctl list-unit-files --type=service`

## systemd-analyze blame

> [Main docummentation page](https://www.freedesktop.org/software/systemd/man/systemd-analyze.html)
### cheatset

```bash
$ systemd-analyze blame
$ systemd-analyze verify [FILES...]
```

* `systemd-analyze blame`

With `systemd-analyze blame` you cal to tshoot the targets bottlenecks on boot.

* `systemd-analyze verify [FILES...]`

You can check de state of an timer target, for example: 

`$ systemd-analyze verify /etc/systemd/system/my-db-backup.timer`


# External reference

* ["What is systemd?" by Linode](https://www.linode.com/docs/quick-answers/linux-essentials/what-is-systemd/)
* ["Understanding and using systemd" by www.linux.com"](https://www.linux.com/learn/understanding-and-using-systemd)
* [systemd wiki](https://www.freedesktop.org/wiki/Software/systemd/)

