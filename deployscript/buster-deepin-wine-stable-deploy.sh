#!/bin/bash
# Pre install
dpkg --add-architecture i386
apt update
apt install -y aptitude wget file bzip2 gcc-multilib

wineworkdir='wineversion'
mkdir -p $wineworkdir


# get dependencies
pkgcachedir='/tmp/.winedeploycache'
mkdir -p $pkgcachedir

cd $wineworkdir

aptitude -y -d -o dir::cache::archives="$pkgcachedir" install libwine:i386
aptitude -y -d -o dir::cache::archives="$pkgcachedir" install mesa-vulkan-drivers:i386 libva2:i386 libva-drm2:i386 libva-x11-2:i386 libvulkan1:i386 libavcodec58:i386

find $pkgcachedir -name '*deb' ! -name 'libwine*' ! -name '*amd64*' -exec dpkg -x {} . \;

rm -rf $pkgcachedir ; rm -rf share/man ; rm -rf usr/share/doc ; rm -rf usr/share/lintian ; rm -rf var ; rm -rf sbin ; rm -rf usr/share/man ; rm -rf usr/share/mime ; rm -rf usr/share/pkgconfig ; rm -rf usr/share/wine
cd ..

# Get Wine
TMP_DIR="$(mktemp -d)"
RELEASE_ASSERTS_URL="$(wget -qO- -T10 --tries=10 --retry-connrefused https://api.github.com/repos/wszqkzqk/deepin-wine-ubuntu/releases/latest | grep tarball_url | cut -d '"' -f 4)"

echo "Download packages: ${RELEASE_ASSERTS_URL}, wait..."
wget -c -T10 --tries=10 --show-progress -qO- "${RELEASE_ASSERTS_URL}" | tar zxf - -C "${TMP_DIR}" &&
echo " finish"
echo "unpack packages"
cd $wineworkdir
find ${TMP_DIR} -name '*deb' -exec dpkg -x {} . \;
rm -fr "${TMP_DIR}"
cd ..

# compile & strip libhookexecv wine-preloader_hook
gcc -shared -fPIC -m32 -ldl src/libhookexecv.c -o src/libhookexecv.so
gcc -std=c99 -m32 -static src/preloaderhook.c -o src/wine-preloader_hook
strip src/libhookexecv.so src/wine-preloader_hook
chmod +x src/wine-preloader_hook


# Make absolutely sure it will not load stuff from /lib or /usr
sed -i -e 's|/usr|/xxx|g' lib/ld-linux.so.2
sed -i -e 's|/usr/lib|/ooo/ooo|g' lib/ld-linux.so.2

# Remove duplicate (why is it there?)
rm -f lib/i386-linux-gnu/ld-*.so

# Disable winemenubuilder
sed -i 's/winemenubuilder.exe -a -r/winemenubuilder.exe -r/g' share/wine/wine.inf

# appimage
cd -

wget -nv -c "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" -O  appimagetool.AppImage
chmod +x appimagetool.AppImage

chmod +x AppRun

cp src/{libhookexecv.so,wine-preloader_hook} $wineworkdir/bin
rm src/{libhookexecv.so,wine-preloader_hook}

cp AppRun $wineworkdir
cp resource/* $wineworkdir

# Remove library path from vk icd files
sed -i -E 's,(^.+"library_path": ")/.*/,\1,' $wineworkdir/usr/share/vulkan/icd.d/*.json

./appimagetool.AppImage --appimage-extract

export ARCH=x86_64; squashfs-root/AppRun -v $wineworkdir -u 'gh-releases-zsync|Wine_Appimage|continuous|deepin-wine-stable*buster.AppImage.zsync' deepin-wine-stable-i386_${ARCH}-buster.AppImage
