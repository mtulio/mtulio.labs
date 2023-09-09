# Setup Fedora on RPI

> Reference: https://docs.fedoraproject.org/en-US/quick-docs/raspberry-pi/#_booting_fedora_on_a_raspberry_pi_for_the_first_time

Setup image:

```bash
sudo arm-image-installer \
--image=~/Downloads/Fedora-Server-38-1.6.aarch64.raw.xz \
--target=rpi4 \
--media=/dev/sda \
--resizefs
```

Connect to wifi:

```bash
nmcli device wifi list
export SSID=SSID_NAME
nmcli device wifi connect $SSID --ask
```

Setup ip address for wlan0:

```bash
CONN_NAME=$SSID
sudo nmcli connection modify $CONN_NAME IPv4.address 192.168.15.81/24
sudo nmcli connection modify $CONN_NAME IPv4.dns 8.8.8.8
sudo nmcli connection modify $CONN_NAME IPv4.gateway 192.168.15.1
sudo nmcli connection modify $CONN_NAME IPv4.method manual
sudo nmcli connection down $CONN_NAME
sudo nmcli connection up $CONN_NAME
```