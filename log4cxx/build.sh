#!/bin/sh -x

#===============================================================================

: ${APR:="apr-1.4.6"}
: ${APR_UTIL:="apr-util-1.5.1"}
: ${LOG4CXX:="apache-log4cxx-0.10.0"}

#===============================================================================

: ${SRCDIR:=`pwd`}
: ${OS_BUILDDIR=`pwd`/iPhoneOS_build}
: ${SIMULATOR_BUILDDIR=`pwd`/iPhoneSimulator_build}

#===============================================================================
curl http://mirror.csclub.uwaterloo.ca/apache//apr/$APR.tar.gz -o ./$APR.tar.gz
curl http://mirror.csclub.uwaterloo.ca/apache//apr/$APR_UTIL.tar.gz -o ./$APR_UTIL.tar.gz
curl http://mirror.csclub.uwaterloo.ca/apache/logging/log4cxx/0.10.0/$LOG4CXX.tar.gz -o ./$LOG4CXX.tar.gz

echo "Extracting ..."

[[ -d $APR ]] && rm -rf $APR
[[ -d $APR_UTIL ]] && rm -rf $APR_UTIL
[[ -d $LOG4CXX ]] && rm -rf $LOG4CXX

tar xvzf $APR.tar.gz
tar xvzf $APR_UTIL.tar.gz
tar xvzf $LOG4CXX.tar.gz

#===============================================================================
echo "Configuring ..."

cd $SRCDIR/$APR
./configure --without-sendfile

cd $SRCDIR/$APR_UTIL
./configure --with-apr="../$APR/" --without-pgsql --without-mysql --without-sqlite2 --without-sqlite3 --without-oracle --without-freetds --without-odbc

cd $SRCDIR/$APR_UTIL/xml/expat/
./configure

cd $SRCDIR/$LOG4CXX
./configure --with-apr="../$APR/"

#===============================================================================
echo "Patching ..."

patch $SRCDIR/$APR/include/apr_general.h $SRCDIR/patches/apr_general.patch
patch $SRCDIR/$APR/include/apr.h $SRCDIR/patches/apr.patch
patch $SRCDIR/$APR_UTIL/xml/expat/lib/xmlparse.c $SRCDIR/patches/xmlparse.patch

#===============================================================================
echo "Generating CMakeLists.txt ..."

cd $SRCDIR

[[ -f CMakeLists.txt ]] && rm -f CMakeLists.txt

cat > ./CMakeLists.txt <<EOF

cmake_minimum_required(VERSION 2.8.0)

project($LOG4CXX)

include_directories(
    ./$APR/include/
    ./$APR/include/arch
    ./$APR/include/arch/unix

    ./$APR_UTIL/include
    ./$APR_UTIL/include/private
    ./$APR_UTIL/xml/expat
    ./$APR_UTIL/xml/expat/lib

    ./$LOG4CXX/src/main/include
)

add_library($LOG4CXX STATIC
$(find ./$APR -name \*.c | grep -v 'test' | grep 'unix\|tables\|string\|passwd')

$(find ./$APR_UTIL -name \*.c ! -name xmltok_impl.c ! -name xmltok_ns.c | grep -v 'test')
$(find ./$LOG4CXX -name \*.cpp | grep -v 'test' | grep -v 'examples')
)
EOF

#===============================================================================
echo "Building ..."

[[ -d $OS_BUILDDIR ]] && rm -rf $OS_BUILDDIR
[[ -d $SIMULATOR_BUILDDIR ]] && rm -rf $SIMULATOR_BUILDDIR

mkdir $OS_BUILDDIR
mkdir $SIMULATOR_BUILDDIR

cd $OS_BUILDDIR

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=$SRCDIR/ios_cmake/Toolchains/Toolchain-iPhoneOS_Xcode.cmake -DCMAKE_INSTALL_PREFIX=$LOG4CXX_iPhoenOS -GXcode ..

codebuild -sdk iphoneos -configuration Release -target ALL_BUILD
xcodebuild -sdk iphoneos -configuration Release -target $LOG4CXX install

cd $SIMULATOR_BUILDDIR

cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=$SRCDIR/ios_cmake/Toolchains/Toolchain-iPhoneSimulator_Xcode.cmake -DCMAKE_INSTALL_PREFIX=$LOG4CXX_iPhoenSimulator -GXcode ..

codebuild -sdk iphonesimulator -configuration Release -target ALL_BUILD
xcodebuild -sdk iphonesimulator -configuration Release -target $LOG4CXX install

#===============================================================================
cd $SRCDIR

VERSION_TYPE=Alpha
FRAMEWORK_NAME=log4cxx
FRAMEWORK_VERSION=A

FRAMEWORK_CURRENT_VERSION=$LOG4CXX
FRAMEWORK_COMPATIBILITY_VERSION=$LOG4CXX

FRAMEWORK_BUNDLE=$SRCDIR/$FRAMEWORK_NAME.framework
echo "Framework: Building $FRAMEWORK_BUNDLE ..."

[[ -d $FRAMEWORK_BUNDLE ]] && rm -rf $FRAMEWORK_BUNDLE

echo "Framework: Setting up directories..."
mkdir -p $FRAMEWORK_BUNDLE
mkdir -p $FRAMEWORK_BUNDLE/Versions
mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

echo "Framework: Creating symlinks..."
ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
lipo -create $OS_BUILDDIR/Release-iphoneos/lib$LOG4CXX.a $SIMULATOR_BUILDDIR/Release-iphonesimulator/lib$LOG4CXX.a -o $FRAMEWORK_INSTALL_NAME

echo "Framework: Copying includes..."

find ./$APR/include/arch/unix -maxdepth 1 -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;
find ./$APR/include/arch/ -maxdepth 1 -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;
find ./$APR/include/ -maxdepth 1 -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;
find ./$APR_UTIL/include -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;
find ./$APR_UTIL/xml -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;
find ./$LOG4CXX/src/main/include -name \*.h -exec cp {} $FRAMEWORK_BUNDLE/Headers \;

echo "Framework: Creating plist..."

cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>English</string>
        <key>CFBundleExecutable</key>
        <string>${FRAMEWORK_NAME}</string>
        <key>CFBundleIdentifier</key>
        <string>org.boost</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundlePackageType</key>
        <string>FMWK</string>
        <key>CFBundleSignature</key>
        <string>????</string>
        <key>CFBundleVersion</key>
        <string>${FRAMEWORK_CURRENT_VERSION}</string>
    </dict>
</plist>
EOF

echo "Done !"
