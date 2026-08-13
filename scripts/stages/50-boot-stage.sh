### ch-bootable-fstab :: 10.2. Creating the /etc/fstab File
cat > /etc/fstab << "EOF"
# Begin /etc/fstab

# file system  mount-point  type     options             dump  fsck
#                                                              order

/dev/<xxx>     /            <fff>    defaults            1     1
/dev/<yyy>     swap         swap     pri=1               0     0

# End /etc/fstab
EOF

### ch-bootable-kernel :: 10.3. Linux-6.18.10
make mrproper

### ch-bootable-kernel :: 10.3. Linux-6.18.10
make menuconfig

### ch-bootable-kernel :: 10.3. Linux-6.18.10
make

### ch-bootable-kernel :: 10.3. Linux-6.18.10
make modules_install

### ch-bootable-kernel :: 10.3. Linux-6.18.10
mount /boot

### ch-bootable-kernel :: 10.3. Linux-6.18.10
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.18.10-lfs-13.0-systemd

### ch-bootable-kernel :: 10.3. Linux-6.18.10
cp -iv System.map /boot/System.map-6.18.10

### ch-bootable-kernel :: 10.3. Linux-6.18.10
cp -iv .config /boot/config-6.18.10

### ch-bootable-kernel :: 10.3. Linux-6.18.10
cp -r Documentation -T /usr/share/doc/linux-6.18.10

### conf-modprobe :: 10.3.2. Configuring Linux Module Load Order
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "EOF"
# Begin /etc/modprobe.d/usb.conf

install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true

# End /etc/modprobe.d/usb.conf
EOF

### ch-bootable-grub :: 10.4. Using GRUB to Set Up the Boot Process
cd /tmp
grub-mkrescue --output=grub-img.iso
xorriso -as cdrecord -v dev=/dev/cdrw blank=as_needed grub-img.iso

### ch-bootable-grub :: 10.4. Using GRUB to Set Up the Boot Process
grub-install /dev/sda

### grub-cfg :: 10.4.4. Creating the GRUB Configuration File
cat > /boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set root=(hd0,2)
set gfxpayload=1024x768x32

menuentry "GNU/Linux, Linux 6.18.10-lfs-13.0-systemd" {
        linux   /boot/vmlinuz-6.18.10-lfs-13.0-systemd root=/dev/sda2 ro
}
EOF

### ch-finish-theend :: 11.1. The End
echo 13.0-systemd > /etc/lfs-release

### ch-finish-theend :: 11.1. The End
cat > /etc/lsb-release << "EOF"
DISTRIB_ID="Linux From Scratch"
DISTRIB_RELEASE="13.0-systemd"
DISTRIB_CODENAME="<your name here>"
DISTRIB_DESCRIPTION="Linux From Scratch"
EOF

### ch-finish-theend :: 11.1. The End
cat > /etc/os-release << "EOF"
NAME="Linux From Scratch"
VERSION="13.0-systemd"
ID=lfs
PRETTY_NAME="Linux From Scratch 13.0-systemd"
VERSION_CODENAME="<your name here>"
HOME_URL="https://www.linuxfromscratch.org/lfs/"
RELEASE_TYPE="stable"
EOF

### ch-finish-reboot :: 11.3. Rebooting the System
logout

### ch-finish-reboot :: 11.3. Rebooting the System
umount -v $LFS/dev/pts
mountpoint -q $LFS/dev/shm && umount -v $LFS/dev/shm
umount -v $LFS/dev
umount -v $LFS/run
umount -v $LFS/proc
umount -v $LFS/sys

### ch-finish-reboot :: 11.3. Rebooting the System
umount -v $LFS/home
umount -v $LFS

### ch-finish-reboot :: 11.3. Rebooting the System
umount -v $LFS

