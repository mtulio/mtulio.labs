# Network tools

## Commands

* Show SYN_REC packets

`ss -pitl -o state syn-recv -e`

`netstat -anplt | grep SYN_REC`

## HowTO

### Advanced packet tshoot

#### Trace TCP Connections

* Capture packets

`tcpdump -nnn -w /tmp/tcpdump.out -s 1580`


* Show  the simple trace

`tcptrace netdump-20171110022044.out`

* Show  the trace by connection ID 3079

`tcptrace -o3079 netdump-20171110022044.out`

* Debug problematic packet with detailed and long output

`tcptrace -l -o3079 netdump-20171110022044.out`

And so on.. :P


> Articles

* http://prefetch.net/blog/index.php/2006/04/17/debugging-tcp-connections-with-tcptrace/
* http://veithen.github.io/2014/01/01/how-tcp-backlog-works-in-linux.html
* https://tweaked.io/guide/kernel/




## Articles

### Tools

### 
* [TCP Backlog](http://veithen.github.io/2014/01/01/how-tcp-backlog-works-in-linux.html)
