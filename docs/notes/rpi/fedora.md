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
export DEV_WLAN=wlan0
export BSSID=$BSSID
sudo nmcli device wifi connect $SSID bssid $BSSID private yes ifname $DEV_WLAN --ask
```

Set hostname:

```bash
hostnamectl hostname pi4
```

Setup ip address for wlan0:

```bash
nmcli connection show
CONN_NAME=$SSID
sudo nmcli connection modify $CONN_NAME IPv4.address 192.168.15.81/24
sudo nmcli connection modify $CONN_NAME IPv4.dns 8.8.8.8
sudo nmcli connection modify $CONN_NAME IPv4.gateway 192.168.15.1
sudo nmcli connection modify $CONN_NAME IPv4.method manual
sudo nmcli connection down $CONN_NAME
sudo nmcli connection up $CONN_NAME
```

Setup ip address for ethernet:

```bash
nmcli connection show
CONN_NAME="Wired connection 1"
sudo nmcli connection modify "$CONN_NAME" IPv4.address 192.168.15.80/24
sudo nmcli connection modify "$CONN_NAME" IPv4.dns 8.8.8.8
sudo nmcli connection modify "$CONN_NAME" IPv4.gateway 192.168.15.1
sudo nmcli connection modify "$CONN_NAME" IPv4.method manual
sudo nmcli connection down "$CONN_NAME"
sudo nmcli connection up "$CONN_NAME"
```