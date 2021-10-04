# Red Hat Certified Specialist in Performance Tuning exam

Reference:
- [Exame page](https://www.redhat.com/en/services/training/ex442-red-hat-certified-specialist-in-linux-performance-tuning-exam?section=Objectives)

NOTE:
- This is not a certification sguide, this is a group of notes based on public objectives.


## Objectives

Use utilities to analyze system behavior
- Use utilities such as vmstat, iostat, mpstat, sar, gnome-system-monitor, top, powertop, and others to analyze and report system and application behavior
- Use utilities such as Performance Co-Pilot (PCP) to analyze system behaviour
- Use utilities such as dmesg, dmidecode, and sosreport to profile system hardware configurations

Monitor and alter kernel behavior
- Use /proc/sys, sysctl, and /sys to examine, modify, and set kernel run-time parameters
- Configure kernel behavior by altering module parameters

Analyze system and application performance
- Analyze system and application behavior using tools such as ps, top, and Valgrind
- Configure systems to run SystemTap scripts
Use the eBPF family of tools (e.g. syscount, gethostlatency and others) to diagnose system and application behavior
- Given multiple versions of applications that perform the same or similar tasks, choose which version of the application to run on a system based on its observed performance characteristics

Tune running systems
- Alter process priorities of both new and existing processes
- Select and configure tuned profiles
- Manage system resource usage using control groups

Tune memory utilization
- Configure systems to support alternate page sizes for applications that use large amounts of memory

Configure disk and file subsystems
- Select proper I/O scheduling algorithm
- Tune file system layout for a given use

Tune network performance
- Calculate network buffer sizes based on known quantities such as bandwidth and round-trip time
- Set system buffer sizes based on those calculations