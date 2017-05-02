#!/bin/bash
# Make tarball release for ompcloud in Ubuntu 16.04 docker

# Any subsequent commands which fail will cause the script to exit immediately
set -e

function realpath { echo $(cd $(dirname $1); pwd)/$(basename $1); }

if [ $# -eq 0 ]
then
    echo "ERROR: No version especified"
    echo "Usage: $0 <release_version>"
    exit
fi

# Directory of the script
BASEDIR=$(dirname "$0")
VERSION=$1

if [ ! -d "/io" ]; then
    echo "Entering ubuntu docker"

    sudo docker run -t -i --rm -v $(realpath $BASEDIR/..):/io ubuntu:latest /io/release/make-release.sh $VERSION

    exit
fi

export OMPCLOUD_RELEASE_PREFIX="/opt/release"
export MAKE_ARGS="-j4"

export LIBHDFS3_SRC="$OMPCLOUD_RELEASE_PREFIX/libhdfs3"
export LIBHDFS3_BUILD="$OMPCLOUD_RELEASE_PREFIX/libhdfs3-build"
export LIBHDFS3_INCLUDE_LINK="/usr/local/include/hdfs"

export OMPCLOUD_DIR="/io"
export OMPCLOUD_CONF_DIR="$OMPCLOUD_DIR/conf"
export OMPCLOUD_CONFHDFS_DIR="$OMPCLOUD_DIR/conf-hdfs"
export OMPCLOUD_SCRIPT_DIR="$OMPCLOUD_DIR/script"
export OMPCLOUD_CONF_PATH="$OMPCLOUD_CONF_DIR/cloud_rtl.ini.local"
export LIBHDFS3_CONF="$OMPCLOUD_CONF_DIR/hdfs-client.xml"

export LLVM_SRC="$OMPCLOUD_RELEASE_PREFIX/llvm"
export CLANG_SRC="$LLVM_SRC/tools/clang"
export LLVM_BUILD="$OMPCLOUD_RELEASE_PREFIX/llvm-build"
export LIBOMPTARGET_SRC="$OMPCLOUD_RELEASE_PREFIX/libomptarget"
export LIBOMPTARGET_BUILD="$OMPCLOUD_RELEASE_PREFIX/libomptarget-build"

export INSTALL_RELEASE_SCRIPT="$OMPCLOUD_DIR/release/ompcloud-install-release-ubuntu.sh"

export RELEASE_DIR="$OMPCLOUD_RELEASE_PREFIX/ompcloud-$VERSION-linux-amd64"
export INCLUDE_DIR="$RELEASE_DIR/lib/clang/3.8.0"

mkdir -p $OMPCLOUD_RELEASE_PREFIX

apt-get update && \
apt-get install -y git gcc g++ cmake libxml2-dev libkrb5-dev libgsasl7-dev uuid-dev \
    libprotobuf-dev protobuf-compiler libelf-dev libssh-dev libffi-dev apt-utils \
    apt-transport-https

sbt_list="/etc/apt/sources.list.d/sbt.list"
if [ -f "$sbt_list" ]
then
	echo "Sbt repository is already in apt sources list."
else
  echo "deb https://dl.bintray.com/sbt/debian /" | tee -a $sbt_list
  apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 642AC823
fi

apt-get clean all && \
  apt-get update && \
  apt-get upgrade -y
apt-get install -y sbt


# Install libhdfs3
mkdir $LIBHDFS3_SRC
git clone git://github.com/Pivotal-Data-Attic/pivotalrd-libhdfs3.git $LIBHDFS3_SRC
mkdir $LIBHDFS3_BUILD
cd $LIBHDFS3_BUILD
cmake $LIBHDFS3_SRC
make $MAKE_ARGS

ln -s $LIBHDFS3_SRC/src/client $LIBHDFS3_INCLUDE_LINK

# Build libomptarget
git clone git://github.com/ompcloud/libomptarget.git $LIBOMPTARGET_SRC
mkdir $LIBOMPTARGET_BUILD
cd $LIBOMPTARGET_BUILD
cmake -DCMAKE_BUILD_TYPE=Debug $LIBOMPTARGET_SRC
make $MAKE_ARGS

# Build llvm/clang
git clone git://github.com/ompcloud/llvm.git $LLVM_SRC
git clone git://github.com/ompcloud/clang.git $CLANG_SRC
mkdir $LLVM_BUILD
cd $LLVM_BUILD
cmake $LLVM_SRC -DLLVM_TARGETS_TO_BUILD="X86" -DCMAKE_BUILD_TYPE=Release
make $MAKE_ARGS

#OMPCloud
mkdir -p $RELEASE_DIR
cp -R $OMPCLOUD_CONF_DIR $RELEASE_DIR
cp -R $OMPCLOUD_CONFHDFS_DIR $RELEASE_DIR
cp -R $OMPCLOUD_SCRIPT_DIR $RELEASE_DIR

mkdir -p $RELEASE_DIR/bin
mkdir -p $INCLUDE_DIR

# LLVM/Clang Binaries
cd $LLVM_BUILD/bin/
cp * $RELEASE_DIR/bin/

# LLVM/CLang libraries
cd $LLVM_BUILD/lib/
cp $(ls | fgrep .so) $RELEASE_DIR/lib/
cp -R clang/3.8.0/include $INCLUDE_DIR

# Libomptarget libraries
cd $LIBOMPTARGET_BUILD/lib/
cp $(ls | fgrep .so) $RELEASE_DIR/lib/

## Libhdfs3 libraries
cd $LIBHDFS3_BUILD/src/
cp $(ls | fgrep .so) $RELEASE_DIR/lib/
## mkdir $RELEASE_DIR/src
##cp $LIBHDFS3_BUILD/src/*.so.* $RELEASE_DIR/src

cd $OMPCLOUD_RELEASE_PREFIX

## Data of org.llvm.openmp for sbt
cp -R $HOME/.ivy2/local $RELEASE_DIR

cp $INSTALL_RELEASE_SCRIPT $RELEASE_DIR

cd $RELEASE_DIR
## Create tarball
tar -zcvf $RELEASE_DIR.tar.gz *

## Get tarball from docker
mv $RELEASE_DIR.tar.gz /io/
