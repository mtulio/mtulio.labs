# Wireshark


## tshark (cli)

https://www.wireshark.org/docs/man-pages/tshark.html


```bash
sudo tshark -r /tmp/localhost-port443.pcap -o "ssl.desegment_ssl_records: TRUE" \
-o "ssl.desegment_ssl_application_data: TRUE" \
-o "ssl.keys_list: 0.0.0.0,443,http,/etc/ssl/private/ssl-cert-snakeoil.key" \
-o "ssl.debug_file: /tmp/ssl-debug.log"
```

## Encrypted traffic

- https://www.baeldung.com/linux/tcpdump-capture-ssl-handshake
- https://www.benburwell.com/posts/intercepting-golang-tls-with-wireshark/

