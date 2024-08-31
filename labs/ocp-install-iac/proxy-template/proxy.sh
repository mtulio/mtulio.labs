#!/bin/bash
function print_logs() {
    while [[ ! -f /tmp/squid-access.log ]]; do
    sleep 5
    done
    tail -f /tmp/squid-access.log
}
print_logs &
sleep 15
squid -N -f /squid/squid.conf