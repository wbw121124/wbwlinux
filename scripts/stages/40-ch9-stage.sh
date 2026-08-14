#!/usr/bin/env bash
# WARNING: reference transcript extracted from the LFS book ch9.
# DO NOT RUN - contains interactive/placeholder commands (<xxx>, tzselect,
# timedatectl set-time ...). The real configuration is scripts/chroot/04-sysconfig.sh.
### ch-config-network :: 9.2. General Network Configuration
systemctl disable systemd-networkd-wait-online

### ch-config-network :: 9.2. General Network Configuration
ln -s /dev/null /etc/systemd/network/99-default.link

### ch-config-network :: 9.2. General Network Configuration
cat > /etc/systemd/network/10-ether0.link << "EOF"
[Match]
# Change the MAC address as appropriate for your network device
MACAddress=12:34:45:78:90:AB

[Link]
Name=ether0
EOF

### ch-config-network :: 9.2. General Network Configuration
cat > /etc/systemd/network/10-eth-static.network << "EOF"
[Match]
Name=<network-device-name>

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
Domains=<Your Domain Name>
EOF

### ch-config-network :: 9.2. General Network Configuration
cat > /etc/systemd/network/10-eth-dhcp.network << "EOF"
[Match]
Name=<network-device-name>

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF

### resolv.conf :: 9.2.2. Creating the /etc/resolv.conf File
systemctl disable systemd-resolved

### resolv.conf :: 9.2.2. Creating the /etc/resolv.conf File
cat > /etc/resolv.conf << "EOF"
# Begin /etc/resolv.conf

domain <Your Domain Name>
nameserver <IP address of your primary nameserver>
nameserver <IP address of your secondary nameserver>

# End /etc/resolv.conf
EOF

### ch-config-hostname :: 9.2.3. Configuring the system hostname
echo "<lfs>" > /etc/hostname

### ch-config-hosts :: 9.2.4. Customizing the /etc/hosts File
cat > /etc/hosts << "EOF"
# Begin /etc/hosts

<192.168.0.2> <FQDN> [alias1] [alias2] ...
::1       ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters

# End /etc/hosts
EOF

### ch-config-symlinks :: 9.4. Managing Devices
udevadm info -a -p /sys/class/video4linux/video0

### ch-config-symlinks :: 9.4. Managing Devices
cat > /etc/udev/rules.d/83-duplicate_devs.rules << "EOF"

# Persistent symlinks for webcam and tuner
KERNEL=="video*", ATTRS{idProduct}=="1910", ATTRS{idVendor}=="0d81", SYMLINK+="webcam"
KERNEL=="video*", ATTRS{device}=="0x036f",  ATTRS{vendor}=="0x109e", SYMLINK+="tvtuner"

EOF

### ch-config-clock :: 9.5. Configuring the System Clock
cat > /etc/adjtime << "EOF"
0.0 0 0.0
0
LOCAL
EOF

### ch-config-clock :: 9.5. Configuring the System Clock
timedatectl set-local-rtc 1

### ch-config-clock :: 9.5. Configuring the System Clock
timedatectl set-time YYYY-MM-DD HH:MM:SS

### ch-config-clock :: 9.5. Configuring the System Clock
timedatectl set-timezone TIMEZONE

### ch-config-clock :: 9.5. Configuring the System Clock
timedatectl list-timezones

### ch-config-clock :: 9.5. Configuring the System Clock
systemctl disable systemd-timesyncd

### ch-config-console :: 9.6. Configuring the Linux Console
echo FONT=Lat2-Terminus16 > /etc/vconsole.conf

### ch-config-console :: 9.6. Configuring the Linux Console
cat > /etc/vconsole.conf << "EOF"
KEYMAP=de-latin1
FONT=Lat2-Terminus16
EOF

### ch-config-console :: 9.6. Configuring the Linux Console
localectl set-keymap MAP

### ch-config-console :: 9.6. Configuring the Linux Console
localectl set-x11-keymap LAYOUT [MODEL] [VARIANT] [OPTIONS]

### ch-config-locale :: 9.7. Configuring the System Locale
locale -a

### ch-config-locale :: 9.7. Configuring the System Locale
LC_ALL=<locale name> locale charmap

### ch-config-locale :: 9.7. Configuring the System Locale
LC_ALL=<locale name> locale language
LC_ALL=<locale name> locale charmap
LC_ALL=<locale name> locale int_curr_symbol
LC_ALL=<locale name> locale int_prefix

### ch-config-locale :: 9.7. Configuring the System Locale
cat > /etc/locale.conf << "EOF"
LANG=<ll>_<CC>.<charmap><@modifiers>
EOF

### ch-config-locale :: 9.7. Configuring the System Locale
cat > /etc/profile << "EOF"
# Begin /etc/profile

for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  source /etc/locale.conf

  for i in $(locale); do
    key=${i%=*}
    if [[ -v $key ]]; then
      export $key
    fi
  done
fi

# End /etc/profile
EOF

### ch-config-locale :: 9.7. Configuring the System Locale
localectl set-locale LANG="<ll>_<CC>.<charmap><@modifiers>"

### ch-config-locale :: 9.7. Configuring the System Locale
localectl set-locale LANG="en_US.UTF-8" LC_CTYPE="en_US"

### ch-config-inputrc :: 9.8. Creating the /etc/inputrc File
cat > /etc/inputrc << "EOF"
# Begin /etc/inputrc
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line

# End /etc/inputrc
EOF

### ch-config-systemd-custom :: 9.10. Systemd Usage and Configuration
mkdir -pv /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << EOF
[Service]
TTYVTDisallocate=no
EOF

### systemd-no-tmpfs :: 9.10.3. Disabling tmpfs for /tmp
ln -sfv /dev/null /etc/systemd/system/tmp.mount

### systemd-no-tmpfs :: 9.10.3. Disabling tmpfs for /tmp
mkdir -p /etc/tmpfiles.d
cp /usr/lib/tmpfiles.d/tmp.conf /etc/tmpfiles.d

### systemd-no-tmpfs :: 9.10.3. Disabling tmpfs for /tmp
mkdir -pv /etc/systemd/system/foobar.service.d

cat > /etc/systemd/system/foobar.service.d/foobar.conf << EOF
[Service]
Restart=always
RestartSec=30
EOF

### systemd-no-tmpfs :: 9.10.3. Disabling tmpfs for /tmp
mkdir -pv /etc/systemd/coredump.conf.d

cat > /etc/systemd/coredump.conf.d/maxuse.conf << EOF
[Coredump]
MaxUse=5G
EOF

