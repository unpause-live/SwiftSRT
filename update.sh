#!/bin/bash

#
#  Updates SRT sources with a specified release version
#

VERSION=${1:-"1.4.1"}
VERSION_PARTS=(${VERSION//./ })
mkdir -p .srt-checkout
cd .srt-checkout
curl -L "https://github.com/Haivision/srt/archive/v$VERSION.tar.gz" > srt.tar.gz
tar xzf srt.tar.gz
git rm -rf ../Sources/CSRT/*
mkdir -p ../Sources/CSRT/include
cd srt-$VERSION
sed -e "s/@SRT_VERSION@/$VERSION/g" srtcore/version.h.in > srtcore/version.h.tmp
sed -e "s/@SRT_VERSION_MAJOR@/${VERSION_PARTS[0]}/g" srtcore/version.h.tmp > srtcore/version.h.tmp1
sed -e "s/@SRT_VERSION_MINOR@/${VERSION_PARTS[1]}/g" srtcore/version.h.tmp1 > srtcore/version.h.tmp2
sed -e "s/@SRT_VERSION_PATCH@/${VERSION_PARTS[2]}/g" srtcore/version.h.tmp2 > srtcore/version.h.tmp3
sed -e "s/#cmakedefine/\/\/#define/g" srtcore/version.h.tmp3 > srtcore/version.h

cp srtcore/*.h ../../Sources/CSRT/include
cp srtcore/*.c* ../../Sources/CSRT

# haicrypt
sed -i '' "/HaiCrypt/d" haicrypt/filelist-openssl.maf
sed -i '' "/PUBLIC/d" haicrypt/filelist-openssl.maf
sed -i '' "/PRIVATE/d" haicrypt/filelist-openssl.maf
sed -i '' "/SOURCES/d" haicrypt/filelist-openssl.maf
cd haicrypt
mkdir tmp
cat filelist-openssl.maf | xargs -I{} cp "{}" tmp
cp tmp/*.c ../../../Sources/CSRT
cp tmp/*.cpp ../../../Sources/CSRT
cp tmp/*.h ../../../Sources/CSRT/include
cp cryspr-config.h ../../../Sources/CSRT/include
cd ../../..

cat <<-EOT > Sources/CSRT/include/module.modulemap
module CSRT [system] {
    header "srt.h"
}
EOT

git add Sources/CSRT
rm -rf .srt-checkout
