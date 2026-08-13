#!/usr/bin/env bash
# Runs INSIDE the LFS chroot. System configuration (LFS ch9, customized).
set -euo pipefail
export SOURCES=/sources
export SCRIPTS_DIR=/build
export STAGES_DIR=/build/stages
export CONFIG_DIR=/config
source /build/env.sh
source /build/common.sh

# --- 9.2. networkd: DHCP on the first ethernet interface -----------
systemctl disable systemd-networkd-wait-online
ln -sf /dev/null /etc/systemd/network/99-default.link

cat > /etc/systemd/network/10-eth-dhcp.network << 'EOF'
[Match]
Type=ether

[Network]
DHCP=ipv4

[DHCPv4]
UseDomains=true
EOF

cat > /etc/systemd/network/10-eth-static.network << 'EOF'
[Match]
Name=ether0

[Network]
Address=192.168.0.2/24
Gateway=192.168.0.1
DNS=192.168.0.1
EOF

# --- 9.2.3/9.2.4 hostname + hosts ----------------------------------
echo 'lfs-cn' > /etc/hostname

cat > /etc/hosts << 'EOF'
# Begin /etc/hosts
127.0.0.1   localhost
::1         ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
# End /etc/hosts
EOF

# --- 9.5. clock ------------------------------------------------------
cat > /etc/adjtime << 'EOF'
0.0 0 0.0
0
UTC
EOF
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl enable systemd-timesyncd

# --- 9.6. console (fbterm handles CJK; keep plain keymap) ----------
cat > /etc/vconsole.conf << 'EOF'
KEYMAP=us
FONT=eurlatgr
EOF

# --- 9.7. locale: zh_CN.UTF-8 default, C.UTF-8 on raw console ------
if ! locale -a 2>/dev/null | grep -q '^zh_CN.UTF-8$'; then
    log "==> generating zh_CN.UTF-8 locale"
    localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
fi

cat > /etc/locale.conf << 'EOF'
LANG=zh_CN.UTF-8
LC_CTYPE=zh_CN.UTF-8
LC_NUMERIC=zh_CN.UTF-8
LC_TIME=zh_CN.UTF-8
LC_COLLATE=zh_CN.UTF-8
LC_MONETARY=zh_CN.UTF-8
LC_MESSAGES=zh_CN.UTF-8
LC_PAPER=zh_CN.UTF-8
LC_NAME=zh_CN.UTF-8
LC_ADDRESS=zh_CN.UTF-8
LC_TELEPHONE=zh_CN.UTF-8
LC_MEASUREMENT=zh_CN.UTF-8
LC_IDENTIFICATION=zh_CN.UTF-8
EOF

cat > /etc/profile << 'EOF'
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

# --- 9.8. inputrc ----------------------------------------------------
cat > /etc/inputrc << 'EOF'
# Begin /etc/inputrc
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
"\eOH": beginning-of-line
"\eOF": end-of-line
"\e[H": beginning-of-line
"\e[F": end-of-line
# End /etc/inputrc
EOF

# --- 9.10. systemd: keep console content across getty --------------
mkdir -pv /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/noclear.conf << 'EOF'
[Service]
TTYVTDisallocate=no
EOF

# enable systemd-networkd for the live environment
systemctl enable systemd-networkd systemd-resolved

# --- live convenience: root auto-login on tty1 ----------------------
mkdir -pv /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
EOF

# --- full os-release ------------------------------------------------
cat > /etc/os-release << 'EOF'
NAME="LFS-CN"
VERSION="13.0-systemd"
ID=lfs
ID_LIKE=lfs
PRETTY_NAME="LFS-CN 13.0-systemd (Live)"
VERSION_ID="13.0-systemd"
HOME_URL="https://www.linuxfromscratch.org/"
EOF

log '==> system config written'
