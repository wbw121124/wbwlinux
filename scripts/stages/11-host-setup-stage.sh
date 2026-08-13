# host setup stage: LFS 4.2/7.2/7.3 (direct commands, not pkg_run)
# --- 4.2. Creating a Limited Directory Layout in the LFS Filesystem
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}

for i in bin lib sbin; do
  ln -sv usr/$i $LFS/$i
done

case $(uname -m) in
  x86_64) mkdir -pv $LFS/lib64 ;;
esac

# --- 4.2. Creating a Limited Directory Layout in the LFS Filesystem
mkdir -pv $LFS/tools

# --- 4.3. Adding the LFS User
groupadd lfs
useradd -s /bin/bash -g lfs -m -k /dev/null lfs

# --- 4.3. Adding the LFS User
passwd lfs

# --- 4.3. Adding the LFS User
chown -v lfs $LFS/{usr{,/*},var,etc,tools}
case $(uname -m) in
  x86_64) chown -v lfs $LFS/lib64 ;;
esac

# --- 4.3. Adding the LFS User
su - lfs

# --- 4.4. Setting Up the Environment
cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

# --- 4.4. Setting Up the Environment
cat > ~/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
EOF

# --- 4.4. Setting Up the Environment
[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE

# --- 4.4. Setting Up the Environment
make -j32

# --- 4.4. Setting Up the Environment
export MAKEFLAGS=-j32

# --- 4.4. Setting Up the Environment
cat >> ~/.bashrc << "EOF"
export MAKEFLAGS=-j$(nproc)
EOF

# --- 4.4. Setting Up the Environment
source ~/.bash_profile

# --- 7.2. Changing Ownership
chown --from lfs -R root:root $LFS/{usr,var,etc,tools}
case $(uname -m) in
  x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
esac

# --- 7.3. Preparing Virtual Kernel File Systems
mkdir -pv $LFS/{dev,proc,sys,run}

# --- 7.3.1. Mounting and Populating /dev
mount -v --bind /dev $LFS/dev

# --- 7.3.2. Mounting Virtual Kernel File Systems
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run

# --- 7.3.2. Mounting Virtual Kernel File Systems
if [ -h $LFS/dev/shm ]; then
  install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
  mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

