#!/bin/bash
# Enable Multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

pacman -Syy
pacman -S --noconfirm wget file pacman-contrib tar grep gcc lib32-gcc-libs

# Get lol patched wine
wget -nv -c "https://gist.github.com/mmtrt/578f4c0694fcfc968b2d9dcc90da4c0e/raw/47efa388cc1adb62f32986d5c0ed0e6719c6c112/wine-tkg-staging-esync-faudio-git-4.11.r6.gfbb8eac8-173-x86_64.pkg.tar.xz"
mkdir wineversion
tar xf wine-tkg*.tar.xz -C wineversion/
mv wineversion/usr/* wineversion
rm -rf wineversion/lib

# Get lol patched glibc
wget -nv -c "https://gist.github.com/mmtrt/578f4c0694fcfc968b2d9dcc90da4c0e/raw/47efa388cc1adb62f32986d5c0ed0e6719c6c112/lib32-glibc-2.29-3-x86_64.pkg.tar.xz"
tar xf lib32-glib*.tar.xz -C wineversion/

# compile & strip libhookexecv wine-preloader_hook
gcc -shared -fPIC -m32 -ldl src/libhookexecv.c -o src/libhookexecv.so
gcc -std=c99 -m32 -static src/preloaderhook.c -o src/wine-preloader_hook
strip src/libhookexecv.so src/wine-preloader_hook
chmod +x src/wine-preloader_hook

wineworkdir=(wineversion)
cd $wineworkdir

# Add a dependency library, such as freetype font library
dependencys=$(pactree -s -u wine |grep lib32 | xargs)

mkdir cache

pacman -Scc --noconfirm
pacman -Syw --noconfirm --cachedir cache lib32-alsa-lib lib32-alsa-plugins lib32-faudio lib32-fontconfig lib32-freetype2 lib32-gcc-libs lib32-gettext lib32-giflib lib32-glu lib32-gnutls lib32-gst-plugins-base-libs lib32-lcms2 lib32-libjpeg-turbo lib32-libldap lib32-libpcap lib32-libpng lib32-libpulse lib32-libsm lib32-libxcomposite lib32-libxcursor lib32-libxdamage lib32-libxi lib32-libxinerama lib32-libxml2 lib32-libxmu lib32-libxrandr lib32-libxslt lib32-libxxf86vm lib32-mesa lib32-mesa-libgl lib32-mpg123 lib32-ncurses lib32-openal lib32-opencl-icd-loader lib32-ocl-icd lib32-sdl2 lib32-v4l-utils lib32-vkd3d lib32-vulkan-icd-loader lib32-libdrm lib32-libva lib32-vulkan-intel lib32-vulkan-radeon $dependencys

# Remove non lib32 pkgs before extracting
find ./cache -type f ! -name "lib32*" -exec rm {} \;

# Remove non patched glibc
rm -v ./cache/lib32-glibc-2.29-3-x86_64.pkg.tar.xz

find ./cache -name '*tar.xz' -exec tar --warning=no-unknown-keyword -xJf {} \;

# wineworkdir cleanup
rm -rf cache; rm -rf include; rm usr/lib32/{*.a,*.o}; rm -rf usr/lib32/pkgconfig; rm -rf share/man; rm -rf usr/include; rm -rf usr/share/{applications,doc,emacs,gtk-doc,java,licenses,man,info,pkgconfig}; rm usr/lib32/locale

# fix broken link libglx_indirect
rm usr/lib32/libGLX_indirect.so.0
ln -s libGLX_mesa.so.0 libGLX_indirect.so.0
mv libGLX_indirect.so.0 usr/lib32

# appimage
cd -

wget -nv -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O  appimagetool.AppImage
chmod +x appimagetool.AppImage

cat > AppRun <<\EOF
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export LD_LIBRARY_PATH="$HERE/usr/lib32":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/lib":$LD_LIBRARY_PATH

# Sound Library
export LD_LIBRARY_PATH="$HERE/usr/lib32/pulseaudio":$LD_LIBRARY_PATH
export LD_LIBRARY_PATH="$HERE/usr/lib32/alsa-lib":$LD_LIBRARY_PATH

# Font Config
export FONTCONFIG_PATH="$HERE/etc/fonts"

# libGL drivers
export LIBGL_DRIVERS_PATH="$HERE/usr/lib32/dri":$LIBGL_DRIVERS_PATH

# LD
export WINELDLIBRARY="$HERE/usr/lib32/ld-linux.so.2"

# Workaround for: wine: loadlocale.c:129: _nl_intern_locale_data:
# Assertion `cnt < (sizeof (_nl_value_type_LC_TIME) / sizeof (_nl_value_type_LC_TIME[0]))' failed.
export LC_ALL=C LANGUAGE=C LANG=C

# Wine env
export WINEPREFIX=$HOME/.wine-appimage-lol
export WINEDEBUG=fixme-all
export WINEDLLOVERRIDES="mscoree,mshtml="

# Disable file associations
if [ ! -d $WINEPREFIX ]; then
cat > /tmp/reg <<'EOF1'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Wine\FileOpenAssociations]
"Enable"="N"
EOF1
$HERE/bin/wine regedit /tmp/reg && rm /tmp/reg
fi

#
# FIXME: find better workaround for this.
#
# Load vulkan icd files as per vendor
#
checkdri=$(cat /var/log/Xorg.0.log | grep -e "DRI driver:" | awk '{print $8}')

if [ "$checkdri" = "i965" ]; then
    export VK_ICD_FILENAMES="$HERE/usr/share/vulkan/icd.d/intel_icd.i686.json":$VK_ICD_FILENAMES
elif [ "$checkdri" = "radeonsi" ]; then
    export VK_ICD_FILENAMES="$HERE/usr/share/vulkan/icd.d/radeon_icd.i686.json":$VK_ICD_FILENAMES
fi

# Checking for d3d* native dlloverride
chkd3d=$(grep -e 'd3d9"=' -e 'd3d11"=' ${WINEPREFIX}/user.reg 2>/dev/null | head -n1 | wc -l)

if [ $chkd3d -eq 1 ]; then
# Checking for d*vk hud env being used already if not then add it
chkdvkh=$(env | grep DXVK_HUD | wc -l)
    if [ $chkdvkh -eq 0 ]; then
        export DXVK_HUD=1
    fi
fi

# Checking for esync env being used already if not then add it
chkesyn=$(env | grep WINEESYNC | wc -l)
if [ $chkesyn -eq 0 ]; then
export WINEESYNC=1
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

export ARCH=x86_64; squashfs-root/AppRun -v $wineworkdir -u 'gh-releases-zsync|mmtrt|Wine_Appimage|continuous|wine-staging*lol*arch*.AppImage.zsync' wine-staging-i386_lol-patched_${ARCH}-archlinux.AppImage
