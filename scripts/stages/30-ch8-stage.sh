# chroot stage: LFS ch8 basic system

# --- 8.3. Man-pages-6.17
pkg_run 'man-pages-6.17' <<'CMD'
rm -v man3/crypt*
make -R GIT=false prefix=/usr install
CMD

# --- 8.4. Iana-Etc-20260202
pkg_run 'iana-etc-20260202' <<'CMD'
cp -v services protocols /etc
CMD

# --- 8.5. Glibc-2.43
pkg_run 'glibc-2.43' <<'CMD'
patch -Np1 -i ../glibc-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr                   \
             --disable-werror                \
             --disable-nscd                  \
             libc_cv_slibdir=/usr/lib        \
             --enable-stack-protector=strong \
             --enable-kernel=5.4
make
grep "Timed out" $(find -name \*.out) || true
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
rm -f /usr/sbin/nscd
systemctl disable --now nscd
make DESTDIR=$PWD/dest install
install -vm755 dest/usr/lib/*.so.* /usr/lib
DIR=$(dirname $(gcc -print-libgcc-file-name))
[ -e $DIR/include/limits.h ]    || mv $DIR/include{-fixed,}/limits.h
[ -e $DIR/include/syslimits.h ] || mv $DIR/include{-fixed,}/syslimits.h
rm -rfv $DIR/include-fixed/*
unset DIR
make install
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd
localedef -i C -f UTF-8 C.UTF-8
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8
make localedata/install-locales
CMD

# --- 8.5.2. Configuring Glibc
shell_run <<'CMD'
cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF
tar -xf ../../tzdata2025c.tar.gz

ZONEINFO=/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica  \
          asia australasia backward; do
    zic -L /dev/null   -d $ZONEINFO       ${tz}
    zic -L /dev/null   -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p America/New_York
unset ZONEINFO tz
tzselect
ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime
cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

EOF
cat >> /etc/ld.so.conf << "EOF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
mkdir -pv /etc/ld.so.conf.d
CMD

# --- 8.6. Zlib-1.3.2
pkg_run 'zlib-1.3.2' <<'CMD'
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libz.a
CMD

# --- 8.7. Bzip2-1.0.8
pkg_run 'bzip2-1.0.8' <<'CMD'
patch -Np1 -i ../bzip2-1.0.8-install_docs-1.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do
  ln -sfv bzip2 $i
done
rm -fv /usr/lib/libbz2.a
CMD

# --- 8.8. Xz-5.8.2
pkg_run 'xz-5.8.2' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.8.2
make
make install
CMD

# --- 8.9. Lz4-1.10.0
pkg_run 'lz4-1.10.0' <<'CMD'
make BUILD_STATIC=no PREFIX=/usr
make BUILD_STATIC=no PREFIX=/usr install
CMD

# --- 8.10. Zstd-1.5.7
pkg_run 'zstd-1.5.7' <<'CMD'
make prefix=/usr
make prefix=/usr install
rm -v /usr/lib/libzstd.a
CMD

# --- 8.11. File-5.46
pkg_run 'file-5.46' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.12. Readline-8.3
pkg_run 'readline-8.3' <<'CMD'
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
sed -e '270a\
     else\
       chars_avail = 1;'      \
    -e '288i\   result = -1;' \
    -i.orig input.c
./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline-8.3
make SHLIB_LIBS="-lncursesw"
make install
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.3
CMD

# --- 8.13. Pcre2-10.47
pkg_run 'pcre2-10.47' <<'CMD'
./configure --prefix=/usr                       \
            --docdir=/usr/share/doc/pcre2-10.47 \
            --enable-unicode                    \
            --enable-jit                        \
            --enable-pcre2-16                   \
            --enable-pcre2-32                   \
            --enable-pcre2grep-libz             \
            --enable-pcre2grep-libbz2           \
            --enable-pcre2test-libreadline      \
            --disable-static
make
make install
CMD

# --- 8.14. M4-1.4.21
pkg_run 'm4-1.4.21' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.15. Bc-7.0.3
pkg_run 'bc-7.0.3' <<'CMD'
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
make
make install
CMD

# --- 8.16. Flex-2.6.4
pkg_run 'flex-2.6.4' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/flex-2.6.4
make
make install
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
CMD

# --- 8.17. Tcl-8.6.17
pkg_run 'tcl8.6.17-src' <<'CMD'
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --disable-rpath
make

sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|"     \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|"  \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|"             \
    -i pkgs/tdbc1.1.12/tdbcConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|"            \
    -i pkgs/itcl4.3.4/itclConfig.sh

unset SRCDIR
make install 
chmod 644 /usr/lib/libtclstub8.6.a
chmod -v u+w /usr/lib/libtcl8.6.so
make install-private-headers
ln -sfv tclsh8.6 /usr/bin/tclsh
mv -v /usr/share/man/man3/{Thread,Tcl_Thread}.3
cd ..
tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1
mkdir -v -p /usr/share/doc/tcl-8.6.17
cp -v -r  ./html/* /usr/share/doc/tcl-8.6.17
CMD

# --- 8.18. Expect-5.45.4
pkg_run 'expect5.45.4' <<'CMD'
python3 -c 'from pty import spawn; spawn(["echo", "ok"])'
patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include
make
make install
ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
CMD

# --- 8.19. DejaGNU-1.6.3
pkg_run 'dejagnu-1.6.3' <<'CMD'
mkdir -v build
cd       build
../configure --prefix=/usr
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
make install
install -v -dm755  /usr/share/doc/dejagnu-1.6.3
install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
CMD

# --- 8.20. Pkgconf-2.5.1
pkg_run 'pkgconf-2.5.1' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/pkgconf-2.5.1
make
make install
ln -sv pkgconf   /usr/bin/pkg-config
ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
CMD

# --- 8.21. Binutils-2.46.0
pkg_run 'binutils-2.46.0' <<'CMD'
mkdir -v build
cd       build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
make tooldir=/usr
grep '^FAIL:' $(find -name '*.log') || true
make tooldir=/usr install
rm -rfv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a \
        /usr/share/doc/gprofng/
CMD

# --- 8.22. GMP-6.3.0
pkg_run 'gmp-6.3.0' <<'CMD'
sed -i '/long long t1;/,+1s/()/(...)/' configure
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0
make
make html
awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
make install
make install-html
CMD

# --- 8.23. MPFR-4.2.2
pkg_run 'mpfr-4.2.2' <<'CMD'
./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-4.2.2
make
make html
make install
make install-html
CMD

# --- 8.24. MPC-1.3.1
pkg_run 'mpc-1.3.1' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-1.3.1
make
make html
make install
make install-html
CMD

# --- 8.25. Attr-2.5.2
pkg_run 'attr-2.5.2' <<'CMD'
./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-2.5.2
make
make install
CMD

# --- 8.26. Acl-2.3.2
pkg_run 'acl-2.3.2' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/acl-2.3.2
make
make install
CMD

# --- 8.27. Libcap-2.77
pkg_run 'libcap-2.77' <<'CMD'
sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib
make prefix=/usr lib=lib install
CMD

# --- 8.28. Libxcrypt-4.5.2
pkg_run 'libxcrypt-4.5.2' <<'CMD'
sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens
make
make install
make distclean
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=glibc  \
            --disable-static             \
            --disable-failure-tokens
make
cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib
CMD

# --- 8.29. Shadow-4.19.3
pkg_run 'shadow-4.19.3' <<'CMD'
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --disable-logind    \
            --with-group-name-max-length=32
make
make exec_prefix=/usr install
make -C man install-man
CMD

# --- 8.29.2. Configuring Shadow
shell_run <<'CMD'
pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd

CMD

# --- 8.30. GCC-15.2.0
pkg_run 'gcc-15.2.0' <<'CMD'
sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
mkdir -v build
cd       build
../configure --prefix=/usr            \
             LD=ld                    \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib
make
ulimit -s -H unlimited
sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp


make install
chown -v -R root:root \
    /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}
ln -svr /usr/bin/cpp /usr/lib
ln -sv gcc.1 /usr/share/man/man1/cc.1
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so \
        /usr/lib/bfd-plugins/
echo 'int main(){}' | cc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
grep -B4 '^ /usr/include' dummy.log
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
grep "/lib.*/libc.so.6 " dummy.log
grep found dummy.log
rm -v a.out dummy.log
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
CMD

# --- 8.31. Ncurses-6.6
pkg_run 'ncurses-6.6' <<'CMD'
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make
make DESTDIR=$PWD/dest install
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i dest/usr/include/curses.h
cp --remove-destination -av dest/* /
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cp -v -R doc -T /usr/share/doc/ncurses-6.6
make distclean
./configure --prefix=/usr    \
            --with-shared    \
            --without-normal \
            --without-debug  \
            --without-cxx-binding \
            --with-abi-version=5
make sources libs
cp -av lib/lib*.so.5* /usr/lib
CMD

# --- 8.32. Sed-4.9
pkg_run 'sed-4.9' <<'CMD'
./configure --prefix=/usr
make
make html

make install
install -d -m755           /usr/share/doc/sed-4.9
install -m644 doc/sed.html /usr/share/doc/sed-4.9
CMD

# --- 8.33. Psmisc-23.7
pkg_run 'psmisc-23.7' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.34. Gettext-1.0
pkg_run 'gettext-1.0' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-1.0
make
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
CMD

# --- 8.35. Bison-3.8.2
pkg_run 'bison-3.8.2' <<'CMD'
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make
make install
CMD

# --- 8.36. Grep-3.12
pkg_run 'grep-3.12' <<'CMD'
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make
make install
CMD

# --- 8.37. Bash-5.3
pkg_run 'bash-5.3' <<'CMD'
./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            --docdir=/usr/share/doc/bash-5.3
make


make install

CMD

# --- 8.38. Libtool-2.5.4
pkg_run 'libtool-2.5.4' <<'CMD'
./configure --prefix=/usr
make
make install
rm -fv /usr/lib/libltdl.a
CMD

# --- 8.39. GDBM-1.26
pkg_run 'gdbm-1.26' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make
make install
CMD

# --- 8.40. Gperf-3.3
pkg_run 'gperf-3.3' <<'CMD'
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
make
make install
CMD

# --- 8.41. Expat-2.7.4
pkg_run 'expat-2.7.4' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.7.4
make
make install
install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.7.4
CMD

# --- 8.42. Inetutils-2.7
pkg_run 'inetutils-2.7' <<'CMD'
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
make
make install
mv -v /usr/{,s}bin/ifconfig
CMD

# --- 8.43. Less-692
pkg_run 'less-692' <<'CMD'
./configure --prefix=/usr --sysconfdir=/etc
make
make install
CMD

# --- 8.44. Perl-5.42.0
pkg_run 'perl-5.42.0' <<'CMD'
export BUILD_ZLIB=False
export BUILD_BZIP2=0
sh Configure -des                                          \
             -D prefix=/usr                                \
             -D vendorprefix=/usr                          \
             -D privlib=/usr/lib/perl5/5.42/core_perl      \
             -D archlib=/usr/lib/perl5/5.42/core_perl      \
             -D sitelib=/usr/lib/perl5/5.42/site_perl      \
             -D sitearch=/usr/lib/perl5/5.42/site_perl     \
             -D vendorlib=/usr/lib/perl5/5.42/vendor_perl  \
             -D vendorarch=/usr/lib/perl5/5.42/vendor_perl \
             -D man1dir=/usr/share/man/man1                \
             -D man3dir=/usr/share/man/man3                \
             -D pager="/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads
make
make install
unset BUILD_ZLIB BUILD_BZIP2
CMD

# --- 8.45. XML::Parser-2.47
pkg_run 'XML-Parser-2.47' <<'CMD'
perl Makefile.PL
make
make install
CMD

# --- 8.46. Intltool-0.51.0
pkg_run 'intltool-0.51.0' <<'CMD'
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
make
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
CMD

# --- 8.47. Autoconf-2.72
pkg_run 'autoconf-2.72' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.48. Automake-1.18.1
pkg_run 'automake-1.18.1' <<'CMD'
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
make
make install
CMD

# --- 8.49. OpenSSL-3.6.1
pkg_run 'openssl-3.6.1' <<'CMD'
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.6.1
cp -vfr doc/* /usr/share/doc/openssl-3.6.1
CMD

# --- 8.50. Libelf from Elfutils-0.194
pkg_run 'elfutils-0.194' <<'CMD'
./configure --prefix=/usr        \
            --disable-debuginfod \
            --enable-libdebuginfod=dummy
make -C lib
make -C libelf
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
CMD

# --- 8.51. Libffi-3.5.2
pkg_run 'libffi-3.5.2' <<'CMD'
./configure --prefix=/usr    \
            --disable-static \
            --with-gcc-arch=native
make
make install
CMD

# --- 8.52. Sqlite-3510200
pkg_run 'sqlite-autoconf-3510200' <<'CMD'
tar -xf ../sqlite-doc-3510200.tar.xz
./configure --prefix=/usr     \
            --disable-static  \
            --enable-fts{4,5} \
            CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 \
                      -D SQLITE_ENABLE_UNLOCK_NOTIFY=1   \
                      -D SQLITE_ENABLE_DBSTAT_VTAB=1     \
                      -D SQLITE_SECURE_DELETE=1"
make LDFLAGS.rpath=""
make install
install -v -m755 -d /usr/share/doc/sqlite-3.51.2
cp -v -R sqlite-doc-3510200/* /usr/share/doc/sqlite-3.51.2
CMD

# --- 8.53. Python-3.14.3
pkg_run 'Python-3.14.3' <<'CMD'
./configure --prefix=/usr          \
            --enable-shared        \
            --with-system-expat    \
            --enable-optimizations \
            --without-static-libpython
make
make install
cat > /etc/pip.conf << EOF
[global]
root-user-action = ignore
disable-pip-version-check = true
EOF
install -v -dm755 /usr/share/doc/python-3.14.3/html

tar --strip-components=1  \
    --no-same-owner       \
    --no-same-permissions \
    -C /usr/share/doc/python-3.14.3/html \
    -xvf ../python-3.14.3-docs-html.tar.bz2
CMD

# --- 8.54. Flit-Core-3.12.0
pkg_run 'flit_core-3.12.0' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist flit_core
CMD

# --- 8.55. Packaging-26.0
pkg_run 'packaging-26.0' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist packaging
CMD

# --- 8.56. Wheel-0.46.3
pkg_run 'wheel-0.46.3' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist wheel
CMD

# --- 8.57. Setuptools-82.0.0
pkg_run 'setuptools-82.0.0' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist setuptools
CMD

# --- 8.58. Ninja-1.13.2
pkg_run 'ninja-1.13.2' <<'CMD'
sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
python3 configure.py --bootstrap --verbose
install -vm755 ninja /usr/bin/
install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
CMD

# --- 8.59. Meson-1.10.1
pkg_run 'meson-1.10.1' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist meson
install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
CMD

# --- 8.60. Kmod-34.2
pkg_run 'kmod-34.2' <<'CMD'
mkdir -p build
cd       build

meson setup --prefix=/usr ..    \
            --buildtype=release \
            -D manpages=false
ninja
ninja install
CMD

# --- 8.61. Coreutils-9.10
pkg_run 'coreutils-9.10' <<'CMD'
patch -Np1 -i ../coreutils-9.10-i18n-1.patch
autoreconf -fv
automake -af
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr
make




groupdel dummy
make install
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
CMD

# --- 8.62. Diffutils-3.12
pkg_run 'diffutils-3.12' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.63. Gawk-5.3.2
pkg_run 'gawk-5.3.2' <<'CMD'
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make

rm -f /usr/bin/gawk-5.3.2
make install
ln -sv gawk.1 /usr/share/man/man1/awk.1
install -vDm644 doc/{awkforai.txt,*.{eps,pdf,jpg}} -t /usr/share/doc/gawk-5.3.2
CMD

# --- 8.64. Findutils-4.10.0
pkg_run 'findutils-4.10.0' <<'CMD'
./configure --prefix=/usr --localstatedir=/var/lib/locate
make

make install
CMD

# --- 8.65. Groff-1.23.0
pkg_run 'groff-1.23.0' <<'CMD'
PAGE=<paper_size> ./configure --prefix=/usr
make
make install
CMD

# --- 8.66. GRUB-2.14
pkg_run 'grub-2.14' <<'CMD'
unset {C,CPP,CXX,LD}FLAGS
sed 's/--image-base/--nonexist-linker-option/' -i configure
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --disable-efiemu  \
            --disable-werror
make
make install
CMD

# --- 8.67. Gzip-1.14
pkg_run 'gzip-1.14' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.68. IPRoute2-6.18.0
pkg_run 'iproute2-6.18.0' <<'CMD'
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin install
install -vDm644 COPYING README* -t /usr/share/doc/iproute2-6.18.0
CMD

# --- 8.69. Kbd-2.9.0
pkg_run 'kbd-2.9.0' <<'CMD'
patch -Np1 -i ../kbd-2.9.0-backspace-1.patch
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock
make
make install
cp -R -v docs/doc -T /usr/share/doc/kbd-2.9.0
CMD

# --- 8.70. Libpipeline-1.5.8
pkg_run 'libpipeline-1.5.8' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.71. Make-4.4.1
pkg_run 'make-4.4.1' <<'CMD'
./configure --prefix=/usr
make

make install
CMD

# --- 8.72. Patch-2.8
pkg_run 'patch-2.8' <<'CMD'
./configure --prefix=/usr
make
make install
CMD

# --- 8.73. Tar-1.35
pkg_run 'tar-1.35' <<'CMD'
FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=/usr
make
make install
make -C doc install-html docdir=/usr/share/doc/tar-1.35
CMD

# --- 8.74. Texinfo-7.2
pkg_run 'texinfo-7.2' <<'CMD'
sed 's/! $output_file eq/$output_file ne/' -i tp/Texinfo/Convert/*.pm
./configure --prefix=/usr
make
make install
make TEXMF=/usr/share/texmf install-tex
pushd /usr/share/info
  rm -v dir
  for f in *
    do install-info $f dir 2>/dev/null
  done
popd
CMD

# --- 8.75. Vim-9.2.0078
pkg_run 'vim-9.2.0078' <<'CMD'
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make
sed '/test_plugin_glvs/d' -i src/testdir/Make_all.mak
make install
ln -sv vim /usr/bin/vi
for L in  /usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1
done
ln -sv ../vim/vim92/doc /usr/share/doc/vim-9.2.0078
CMD

# --- 8.75.2. Configuring Vim
shell_run <<'CMD'
cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

" Ensure defaults are set before customizing settings, not after
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF

CMD

# --- 8.76. MarkupSafe-3.0.3
pkg_run 'markupsafe-3.0.3' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Markupsafe
CMD

# --- 8.77. Jinja2-3.1.6
pkg_run 'jinja2-3.1.6' <<'CMD'
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Jinja2
CMD

# --- 8.78. Systemd-259.1
pkg_run 'systemd-259.1' <<'CMD'
sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //'               \
    -i rules.d/50-udev-default.rules.in
mkdir -p build
cd       build

meson setup ..                \
      --prefix=/usr           \
      --buildtype=release     \
      -D default-dnssec=no    \
      -D firstboot=false      \
      -D install-tests=false  \
      -D ldconfig=false       \
      -D sysusers=false       \
      -D rpmmacrosdir=no      \
      -D homed=disabled       \
      -D man=disabled         \
      -D mode=release         \
      -D pamconfdir=no        \
      -D dev-kvm-mode=0660    \
      -D nobody-group=nogroup \
      -D sysupdate=disabled   \
      -D ukify=disabled       \
      -D docdir=/usr/share/doc/systemd-259.1
ninja
echo 'NAME="Linux From Scratch"' > /etc/os-release
ninja install
tar -xf ../../systemd-man-pages-259.1.tar.xz \
    --no-same-owner --strip-components=1     \
    -C /usr/share/man
systemd-machine-id-setup
systemctl preset-all
CMD

# --- 8.79. D-Bus-1.16.2
pkg_run 'dbus-1.16.2' <<'CMD'
mkdir build
cd    build

meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
ninja

ninja install
ln -sfv /etc/machine-id /var/lib/dbus
CMD

# --- 8.80. Man-DB-2.13.1
pkg_run 'man-db-2.13.1' <<'CMD'
./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db-2.13.1 \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap
make
make install
CMD

# --- 8.81. Procps-ng-4.0.6
pkg_run 'procps-ng-4.0.6' <<'CMD'
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.6 \
            --disable-static                        \
            --disable-kill                          \
            --enable-watch8bit                      \
            --with-systemd
make

make install
CMD

# --- 8.82. Util-linux-2.41.3
pkg_run 'util-linux-2.41.3' <<'CMD'
./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.41.3
make
bash tests/run.sh --srcdir=$PWD --builddir=$PWD
touch /etc/fstab
make install
CMD

# --- 8.83. E2fsprogs-1.47.3
pkg_run 'e2fsprogs-1.47.3' <<'CMD'
mkdir -v build
cd       build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fsck
make
make install
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
CMD

# --- 8.83.2. Configuring E2fsprogs
shell_run <<'CMD'
sed 's/metadata_csum_seed,//' -i /etc/mke2fs.conf
CMD

# --- 8.85. Stripping
shell_run <<'CMD'
save_usrlib="$(cd /usr/lib; ls ld-linux*[^g])
             libc.so.6
             libthread_db.so.1
             libquadmath.so.0.0.0
             libstdc++.so.6.0.34
             libitm.so.1.0.0
             libatomic.so.1.2.0"

cd /usr/lib

for LIB in $save_usrlib; do
    objcopy --only-keep-debug --compress-debug-sections=zstd $LIB $LIB.dbg
    cp $LIB /tmp/$LIB
    strip --strip-debug /tmp/$LIB
    objcopy --add-gnu-debuglink=$LIB.dbg /tmp/$LIB
    install -vm755 /tmp/$LIB /usr/lib
    rm /tmp/$LIB
done

online_usrbin="bash find strip"
online_usrlib="libbfd-2.46.0.20260210.so
               libsframe.so.3.0.0
               libhistory.so.8.3
               libncursesw.so.6.6
               libm.so.6
               libreadline.so.8.3
               libz.so.1.3.2
               libzstd.so.1.5.7
               $(cd /usr/lib; find libnss*.so* -type f)"

for BIN in $online_usrbin; do
    cp /usr/bin/$BIN /tmp/$BIN
    strip --strip-debug /tmp/$BIN
    install -vm755 /tmp/$BIN /usr/bin
    rm /tmp/$BIN
done

for LIB in $online_usrlib; do
    cp /usr/lib/$LIB /tmp/$LIB
    strip --strip-debug /tmp/$LIB
    install -vm755 /tmp/$LIB /usr/lib
    rm /tmp/$LIB
done

for i in $(find /usr/lib -type f -name \*.so* ! -name \*dbg) \
         $(find /usr/lib -type f -name \*.a)                 \
         $(find /usr/{bin,sbin,libexec} -type f); do
    case "$online_usrbin $online_usrlib $save_usrlib" in
        *$(basename $i)* )
            ;;
        * ) strip --strip-debug $i
            ;;
    esac
done

unset BIN LIB save_usrlib online_usrbin online_usrlib
CMD

# --- 8.86. Cleaning Up
shell_run <<'CMD'
rm -rf /tmp/{*,.*}
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf

CMD
