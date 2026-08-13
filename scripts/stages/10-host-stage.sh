# host stage: LFS ch5 (cross toolchain) + ch6 (temporary tools)

# --- 5.2. Binutils-2.46.0 - Pass 1
pkg_run 'binutils-2.46.0' <<'CMD'
mkdir -v build
cd       build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
make
make install
CMD

# --- 5.3. GCC-15.2.0 - Pass 1
pkg_run 'gcc-15.2.0' <<'CMD'
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build
cd       build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.43 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make
make install
cd ..
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
CMD

# --- 5.4. Linux-6.18.10 API Headers
pkg_run 'linux-6.18.10' <<'CMD'
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
CMD

# --- 5.5. Glibc-2.43
pkg_run 'glibc-2.43' <<'CMD'
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-fhs-1.patch
mkdir -v build
cd       build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib           \
      --enable-kernel=5.4
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -x c - -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
grep -E -o "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
grep -B3 "^ $LFS/usr/include" dummy.log
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
grep "/lib.*/libc.so.6 " dummy.log
grep found dummy.log
rm -v a.out dummy.log
CMD

# --- 5.6. Libstdc++ from GCC-15.2.0
pkg_run 'gcc-15.2.0' <<'CMD'
mkdir -v build
cd       build
../libstdc++-v3/configure      \
    --host=$LFS_TGT            \
    --build=$(../config.guess) \
    --prefix=/usr              \
    --disable-multilib         \
    --disable-nls              \
    --disable-libstdcxx-pch    \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
CMD

# --- 6.2. M4-1.4.21
pkg_run 'm4-1.4.21' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.3. Ncurses-6.6
pkg_run 'ncurses-6.6' <<'CMD'
mkdir build
pushd build
  ../configure --prefix=$LFS/tools AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic $LFS/tools/bin
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping          \
            AWK=gawk
make
make DESTDIR=$LFS install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i $LFS/usr/include/curses.h
CMD

# --- 6.4. Bash-5.3
pkg_run 'bash-5.3' <<'CMD'
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
CMD

# --- 6.5. Coreutils-9.10
pkg_run 'coreutils-9.10' <<'CMD'
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot              $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/'                    $LFS/usr/share/man/man8/chroot.8
CMD

# --- 6.6. Diffutils-3.12
pkg_run 'diffutils-3.12' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            gl_cv_func_strcasecmp_works=y \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.7. File-5.46
pkg_run 'file-5.46' <<'CMD'
mkdir build
pushd build
  ../configure --disable-bzlib      \
               --disable-libseccomp \
               --disable-xzlib      \
               --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
CMD

# --- 6.8. Findutils-4.10.0
pkg_run 'findutils-4.10.0' <<'CMD'
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.9. Gawk-5.3.2
pkg_run 'gawk-5.3.2' <<'CMD'
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.10. Grep-3.12
pkg_run 'grep-3.12' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.11. Gzip-1.14
pkg_run 'gzip-1.14' <<'CMD'
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
CMD

# --- 6.12. Make-4.4.1
pkg_run 'make-4.4.1' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.13. Patch-2.8
pkg_run 'patch-2.8' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.14. Sed-4.9
pkg_run 'sed-4.9' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.15. Tar-1.35
pkg_run 'tar-1.35' <<'CMD'
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
CMD

# --- 6.16. Xz-5.8.2
pkg_run 'xz-5.8.2' <<'CMD'
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.8.2
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
CMD

# --- 6.17. Binutils-2.46.0 - Pass 2
pkg_run 'binutils-2.46.0' <<'CMD'
sed '6031s/$add_dir//' -i ltmain.sh
mkdir -v build
cd       build
../configure                   \
    --prefix=/usr              \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --disable-nls              \
    --enable-shared            \
    --enable-gprofng=no        \
    --disable-werror           \
    --enable-64-bit-bfd        \
    --enable-new-dtags         \
    --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
CMD

# --- 6.18. GCC-15.2.0 - Pass 2
pkg_run 'gcc-15.2.0' <<'CMD'
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir -v build
cd       build
../configure                   \
    --build=$(../config.guess) \
    --host=$LFS_TGT            \
    --target=$LFS_TGT          \
    --prefix=/usr              \
    --with-build-sysroot=$LFS  \
    --enable-default-pie       \
    --enable-default-ssp       \
    --disable-fixincludes      \
    --disable-nls              \
    --disable-multilib         \
    --disable-libatomic        \
    --disable-libgomp          \
    --disable-libquadmath      \
    --disable-libsanitizer     \
    --disable-libssp           \
    --disable-libvtv           \
    --enable-languages=c,c++   \
    CXX_FOR_TARGET="$LFS_TGT-gcc -nostdinc++" \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc \
    target_configargs=gcc_cv_target_thread_file=posix
make
make DESTDIR=$LFS install
# 6.18 assertion: pass2 must install the libgcc runtime artifacts
# (run#13/14: configure-target-libgcc failed silently, crtbeginS.o/libgcc
#  were never installed -> 'cannot find crtbeginS.o' at first link)
GCC_LIBGCC_DIR="$LFS/usr/lib/gcc/$LFS_TGT/15.2.0"
for f in crtbeginS.o libgcc.a libgcc_s.so; do
    if [ ! -e "$GCC_LIBGCC_DIR/$f" ]; then
        echo "ERROR: pass2 libgcc artifact missing: $GCC_LIBGCC_DIR/$f" >&2
        exit 1
    fi
done
ls -l "$GCC_LIBGCC_DIR"/{crtbeginS.o,libgcc.a,libgcc_s.so}
ln -sv gcc $LFS/usr/bin/cc
CMD
