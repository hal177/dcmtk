#!/bin/bash
######################################################################
## Build DCMTK and package it into debians:
##
##   pulmera-dcmtk       runtime: the versioned shared libraries
##   pulmera-dcmtk-dev   SDK: headers, cmake files, the command line tools
##
######################################################################
set -euo pipefail

readonly PROJECT_DIR=$(readlink -f "$(dirname "$0")")

#----------------------------------------------------------------------
# Shared scripts live in the thirdparty repository, pinned by ref.
# Keep the thirdparty clone on the same level as the thirdparty repo
# clones, so that it can be reused.
readonly COMMON_DIR="$PROJECT_DIR/common"
readonly COMMON_REF=packaging

if [[ ! -r $COMMON_DIR/scripts/packaging.bash ]]; then
    url="git@github.com:hal177/thirdparty.git"
    if ! git clone --depth 1 --branch "$COMMON_REF" "$url" "$COMMON_DIR"; then
        echo " ** ERROR: failed to clone thirdparty at $COMMON_DIR" >&2
        exit 1
    fi
fi
if [[ ! -L $COMMON_DIR ]]; then
    git -C "$COMMON_DIR" checkout "$COMMON_REF"
    git -C "$COMMON_DIR" pull
fi
source "$COMMON_DIR/scripts/packaging.bash"

#----------------------------------------------------------------------
readonly SOURCE_DIR=$PROJECT_DIR/src
readonly BUILD_DIR=$PROJECT_DIR/build
readonly STAGE_DIR=$BUILD_DIR/stage

readonly INSTALL_PREFIX=/opt/pulmera

#----------------------------------------------------------------------
function configure() {

    pm::require_commands cmake g++ make git

    # * The image codecs and compression backends off: the applications
    #   read DICOM through DCMTK but do their image work with OpenCV, so
    #    pulling in PNG, TIFF, XML and zlib here would add unnecessary deps.
    # * OpenSSL stays on for TLS
    # * The dictionary is built into the library.
    
    pm::info "configuring dcmtk in $BUILD_DIR"
    cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" \
          -DCMAKE_BUILD_TYPE=Release \
	  -DCMAKE_CXX_FLAGS="-fPIC -s -flto" \
          -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
          -DCMAKE_INSTALL_RPATH='$ORIGIN:$ORIGIN/../lib' \
          -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
          -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
          -DBUILD_SHARED_LIBS=ON \
          -DBUILD_APPS=ON \
          -DDCMTK_ENABLE_STL=ON \
          -DDCMTK_ENABLE_CXX11=ON \
          -DDCMTK_ENABLE_PRIVATE_TAGS=ON \
          -DDCMTK_DEFAULT_DICT=builtin \
          -DDCMTK_ENABLE_BUILTIN_DICTIONARY=ON \
          -DDCMTK_ENABLE_EXTERNAL_DICTIONARY=OFF \
          -DDCMTK_WITH_OPENSSL=ON \
          -DDCMTK_WITH_ZLIB=OFF \
          -DDCMTK_WITH_PNG=OFF \
          -DDCMTK_WITH_TIFF=OFF \
          -DDCMTK_WITH_XML=OFF \
          -DDCMTK_WITH_SNDFILE=OFF \
          -DDCMTK_WITH_ICONV=OFF \
          -DDCMTK_WITH_ICU=OFF \
          -DDCMTK_WITH_WRAP=OFF \
          -DDCMTK_WITH_DOXYGEN=OFF \
          -DDCMTK_ENABLE_MANPAGES=OFF \
          -DBUILD_DOCUMENTATION=OFF
}

#----------------------------------------------------------------------
function build() {
    pm::info "building dcmtk with $(nproc) jobs"
    cmake --build "$BUILD_DIR" --parallel "$(nproc)"

    pm::info "installing into the staging root $STAGE_DIR"
    rm -rf "$STAGE_DIR"
    DESTDIR="$STAGE_DIR" cmake --install "$BUILD_DIR"
}

#----------------------------------------------------------------------
function package() {
    # How the installed tree is split between the two packages. Everything
    # installed has to be matched by one list or the other.
    PACKAGE_PREFIX="$INSTALL_PREFIX"
    PACKAGE_STAGE_DIR="$STAGE_DIR"

    # What the built libraries load at run time. packaging.bash derives
    # nothing, so this list is the whole truth.
    PACKAGE_RUNTIME_DEPENDENCIES="libc6, libgcc-s1, libssl3t64, libstdc++6"
    PACKAGE_DEV_DEPENDENCIES="$PACKAGE_RUNTIME_DEPENDENCIES"

    PACKAGE_RUNTIME_PATTERNS=(
	'lib/lib*.so.*'          # versioned shared objects and soname links
	'bin'                    # storescu, dcmdump and the rest of the tools
	'etc'                    # storescp.cfg and friends, read at run time
	'share/dcmtk*'           # data files the tools read
    )
    PACKAGE_DEV_PATTERNS=(
	'lib/lib*.so.*'          # its own copy of the libraries, so the SDK
	                         # stands alone and versions coexist
	'include'                # dcmtk/... headers
	'bin'                    # DCMTKTargets.cmake exports these as imported
	                         # targets, so the SDK needs its own copies or
	                         # find_package fails on a missing file
	'lib/lib*.so'            # unversioned link-time symlinks
	'lib/cmake'              # DCMTKConfig.cmake, for find_package(DCMTK)
	'lib/pkgconfig'          # dcmtk.pc
	'share/doc'              # licence and copyright texts
    )

    pm::create_packages
    pm::info "Done packaging: $(ls -1 "$PACKAGE_OUTPUT_DIR"/*.deb)"
}

#======================================================================
configure
build
package

