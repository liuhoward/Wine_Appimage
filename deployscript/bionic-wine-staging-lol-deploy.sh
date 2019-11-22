#!/bin/bash
# Pre install
dpkg --add-architecture i386
apt update
apt install -y aptitude wget file bzip2 gcc-multilib software-properties-common
add-apt-repository -y ppa:oibaf/graphics-drivers
apt update

# Get Wine & glibc lol patched
wget -nvc https://launchpad.net/~mmtrt/+archive/ubuntu/testing/+files/wine-staging_4.20-0~bionic1_i386.deb -O wine-staging_4.20-lol~bionic_i386.deb
wget -nvc https://launchpad.net/~mmtrt/+archive/ubuntu/testing/+files/wine-staging-i386_4.20-0~bionic1_i386.deb -O wine-staging-i386_4.20-lol~bionic_i386.deb
wget -nvc https://gist.github.com/mmtrt/578f4c0694fcfc968b2d9dcc90da4c0e/raw/9bcb0abfede983a7093973d33f206da9023a2980/libc6_2.27-3ubuntu1_i386.deb

dpkg -x wine-staging_4.20-lol~bionic_i386.deb wineversion/
dpkg -x wine-staging-i386_4.20-lol~bionic_i386.deb wineversion/

cp -r "wineversion/opt/wine-staging/"* "wineversion"
rm -r "wineversion/opt"
rm -rf "wineversion/usr"

dpkg -x libc6_2.27-3ubuntu1_i386.deb wineversion/

# compile & strip libhookexecv wine-preloader_hook
gcc -shared -fPIC -m32 -ldl src/libhookexecv.c -o src/libhookexecv.so
gcc -std=c99 -m32 -static src/preloaderhook.c -o src/wine-preloader_hook
strip src/libhookexecv.so src/wine-preloader_hook
chmod +x src/wine-preloader_hook

wineworkdir=(wineversion)
cd $wineworkdir

pkgcachedir='/tmp/.winedeploycache'
mkdir -p $pkgcachedir

aptitude -y -d -o dir::cache::archives="$pkgcachedir" install mesa-vulkan-drivers:i386 libwine:i386 libva2:i386 libva-drm2:i386 libva-x11-2:i386 libvulkan1:i386 libavcodec57:i386

find $pkgcachedir -name '*deb' ! -name 'libwine*' ! -name 'libc6*' ! -name '*amd64*' -exec dpkg -x {} . \;

rm -rf $pkgcachedir ; rm -rf share/man ; rm -rf usr/share/doc ; rm -rf usr/share/lintian ; rm -rf var ; rm -rf sbin ; rm -rf usr/share/man ; rm -rf usr/share/mime ; rm -rf usr/share/pkgconfig ; rm -rf usr/share/wine

# Make absolutely sure it will not load stuff from /lib or /usr
sed -i -e 's|/usr|/xxx|g' lib/ld-linux.so.2
sed -i -e 's|/usr/lib|/ooo/ooo|g' lib/ld-linux.so.2

# Remove duplicate (why is it there?)
rm -f lib/i386-linux-gnu/ld-*.so

# Disable winemenubuilder
sed -i 's/winemenubuilder.exe -a -r/winemenubuilder.exe -r/g' share/wine/wine.inf

# Disable FileOpenAssociations
sed -i 's|    LicenseInformation|    LicenseInformation,\\\n    FileOpenAssociations|g;$a \\n[FileOpenAssociations]\nHKCU,Software\\Wine\\FileOpenAssociations,"Enable",,"N"' share/wine/wine.inf

# appimage
cd -

wget -nv -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O  appimagetool.AppImage
chmod +x appimagetool.AppImage

cat > AppRun <<\EOF
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export LD_LIBRARY_PATH="$HERE/usr/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib/i386-linux-gnu":$LD_LIBRARY_PATH

# Sound Library
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/pulseaudio":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib/i386-linux-gnu/alsa-lib":$LD_LIBRARY_PATH

# libGL drivers
export LIBGL_DRIVERS_PATH="$HERE/usr/lib/i386-linux-gnu/dri":$LIBGL_DRIVERS_PATH

# Font Config
export FONTCONFIG_PATH="$HERE/etc/fonts"

# LD
export WINELDLIBRARY="$HERE/lib/ld-linux.so.2"

# Workaround for: wine: loadlocale.c:129: _nl_intern_locale_data:
# Assertion `cnt < (sizeof (_nl_value_type_LC_TIME) / sizeof (_nl_value_type_LC_TIME[0]))' failed.
export LC_ALL=C LANGUAGE=C LANG=C

# Wine env
export WINEVERPATH=${WINEVERPATH:-"$HERE"}
export PATH=${WINEVERPATH}/bin:$PATH 
export WINESERVER=${WINEVERPATH}/bin/wineserver
export WINELOADER=${WINEVERPATH}/bin/wine
export WINEDLLPATH=${WINEVERPATH}/lib/wine/fakedlls
export WINEARCH=win32
export WINEPREFIX=${WINEPREFIX:-"$HOME/.wine-appimage-lol"}
export WINEDEBUG=${WINEDEBUG:-"-all"}
export WINEDLLOVERRIDES=${WINEDLLOVERRIDES:-"mscoree,mshtml="}
export WINEESYNC=${WINEESYNC:-"1"}

# DXVK env
export DXVK_HUD=${DXVK_HUD:-"1"}
export DXVK_LOG_LEVEL=${DXVK_LOG_LEVEL:-"none"}

#
# FIXME: find better workaround for this.
#
# Load vulkan icd files as per vendor
#
checkdri=$(cat /var/log/Xorg.0.log | grep -e "DRI driver:" | awk '{print $8}')

if [ "$checkdri" = "i965" ]; then
    export VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-"$HERE/usr/share/vulkan/icd.d/intel_icd.i686.json"}
elif [ "$checkdri" = "radeonsi" ]; then
    export VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-"$HERE/usr/share/vulkan/icd.d/radeon_icd.i686.json"}
fi

# Load winecfg if no arguments given
APPLICATION=""
if [ -z "$*" ] ; then
  APPLICATION="winecfg"
fi

# Allow the AppImage to be symlinked to e.g., /usr/bin/wineserver
if [ ! -z $APPIMAGE ] ; then
  BINARY_NAME=$(basename "$ARGV0")
else
  BINARY_NAME=$(basename "$0")
fi

if [ ! -z "$1" ] && [ -e "$HERE/bin/$1" ] ; then
  MAIN="$HERE/bin/$1" ; shift
elif [ ! -z "$1" ] && [ -e "$HERE/usr/bin/$1" ] ; then
  MAIN="$HERE/usr/bin/$1" ; shift
elif [ -e "$HERE/bin/$BINARY_NAME" ] ; then
  MAIN="$HERE/bin/$BINARY_NAME"
elif [ -e "$HERE/usr/bin/$BINARY_NAME" ] ; then
  MAIN="$HERE/usr/bin/$BINARY_NAME"
else
  MAIN="$HERE/bin/wine"
fi

if [ -z "$APPLICATION" ] ; then
  LD_PRELOAD="$HERE/bin/libhookexecv.so" "$WINELDLIBRARY" "$MAIN" "$@" | cat
else
  LD_PRELOAD="$HERE/bin/libhookexecv.so" "$WINELDLIBRARY" "$MAIN" "$APPLICATION" | cat
fi
EOF

chmod +x AppRun

cp src/{libhookexecv.so,wine-preloader_hook} $wineworkdir/bin
rm src/{libhookexecv.so,wine-preloader_hook}

cp AppRun $wineworkdir
cp resource/* $wineworkdir

# Remove library path from vk icd files
sed -i -E 's,(^.+"library_path": ")/.*/,\1,' $wineworkdir/usr/share/vulkan/icd.d/*.json

./appimagetool.AppImage --appimage-extract

export ARCH=x86_64; squashfs-root/AppRun -v $wineworkdir -u 'gh-releases-zsync|mmtrt|Wine_Appimage|continuous|wine-staging*lol*bionic.AppImage.zsync' wine-staging-i386_lol-patched_${ARCH}-bionic.AppImage