#!/usr/bin/env bash

set -eux

# https://stackoverflow.com/a/3436177
join() {
    local IFS=$1
    shift
    echo "$*"
}

EXTRA_PATH=
CORE_SUFFIX=libretro
EXTRA_CONFIGURE_ARGS=()

if command -v apt-get &> /dev/null; then
    apt-get update
    apt-get -y upgrade
fi

if [ "$(uname -s)" = "Darwin" ]; then
    EXTRA_PATH=$(join ':' ~/Library/Python/3.*/bin)
    LIB_EXT=dylib
fi

case "$platform" in
    unix)
        pip install tomli
        LIB_EXT=so
        if [ "$(uname -m)" = "x86_64" ]; then
            EXTRA_CONFIGURE_ARGS=("--enable-kvm")
        fi
        ;;
    android-*)
        apt-get -y install ninja-build flex bison libglib2.0-dev
        pip install tomli
        EXTRA_PATH=$ANDROID_NDK_LLVM/bin
        CORE_SUFFIX=libretro_android
        LIB_EXT=so
        case "$platform" in
            android-arm)
                EXTRA_CONFIGURE_ARGS=(
                    "--cross-prefix=arm-linux-androideabi-"
                    "--cc=armv7a-linux-androideabi30-clang"
                    "--host-cc=gcc"
                    "--cxx=armv7a-linux-androideabi30-clang++"
                )
                ;;
            android-arm64)
                EXTRA_CONFIGURE_ARGS=(
                    "--cross-prefix=aarch64-linux-android-"
                    "--cc=aarch64-linux-android30-clang"
                    "--host-cc=gcc"
                    "--cxx=aarch64-linux-android30-clang++"
                )
                ;;
            android-x86)
                EXTRA_CONFIGURE_ARGS=(
                    "--cross-prefix=i686-linux-android-"
                    "--cc=i686-linux-android30-clang"
                    "--host-cc=gcc"
                    "--cxx=i686-linux-android30-clang++"
                )
                ;;
            android-x86_64)
                EXTRA_CONFIGURE_ARGS=(
                    "--cross-prefix=x86_64-linux-android-"
                    "--cc=x86_64-linux-android30-clang"
                    "--host-cc=gcc"
                    "--cxx=x86_64-linux-android30-clang++"
                )
                ;;
            *)
                echo "Unknown Android platform $platform"
                exit 1
                ;;
        esac
        ;;
    win32|win64)
        apt-get -y install python3.8-venv
        python3.8 -m pip install distlib tomli meson
        LIB_EXT=dll
        case "$platform" in
            win32)
                EXTRA_CONFIGURE_ARGS=("--cross-prefix=i686-w64-mingw32.static-")
                ;;
            win64)
                EXTRA_CONFIGURE_ARGS=("--cross-prefix=x86_64-w64-mingw32.static-")
                ;;
        esac
        ;;
    osx)
        CORE_SUFFIX=libretro
        if [ "${CROSS_COMPILE:-}" = "1" ]; then
            CLANG_CMD="clang -target $LIBRETRO_APPLE_PLATFORM -isysroot $LIBRETRO_APPLE_ISYSROOT"
            EXTRA_CONFIGURE_ARGS=(
                "--cross-prefix="
                "--cc=$CLANG_CMD"
                "--cxx=$CLANG_CMD"
                "--objcc=$CLANG_CMD"
            )
        fi
        ;;
    ios*|tvos*)
        case "$platform" in
            ios-arm64)
                IOSSDK="$(xcodebuild -version -sdk iphoneos Path)"
                ARCH=arm64
                CORE_SUFFIX=libretro_ios
                ;;
            ios9)
                IOSSDK="$(xcodebuild -version -sdk iphoneos Path)"
                ARCH=armv7
                CORE_SUFFIX=libretro_ios
                ;;
            tvos-arm64)
                IOSSDK="$(xcodebuild -version -sdk appletvos Path)"
                ARCH=arm64
                CORE_SUFFIX=libretro_tvos
                ;;
            *)
                echo "Unknown iOS platform $platform"
                exit 1
                ;;
        esac
        CLANG_CMD="clang -arch $ARCH -isysroot $IOSSDK"
        EXTRA_CONFIGURE_ARGS=(
            "--enable-tcg-interpreter"
            "--cross-prefix="
            "--cc=$CLANG_CMD"
            "--cxx=$CLANG_CMD"
            "--objcc=$CLANG_CMD"
        )
        ;;
    *)
        echo "Unknown platform $platform"
        exit 1
        ;;
esac

if command -v update-ca-certificates &> /dev/null; then
    update-ca-certificates --fresh
    export SSL_CERT_DIR=/etc/ssl/certs
fi

export PATH="$EXTRA_PATH:$PATH"

(cd zlib && ./configure)

rm -rf build
mkdir build
cd build

CFLAGS="-Os -Wno-error -Wno-nested-externs -Wno-redundant-decls" ../configure \
    --target-list="aarch64-softmmu alpha-softmmu arm-softmmu i386-softmmu m68k-softmmu mips64el-softmmu mips64-softmmu mipsel-softmmu mips-softmmu ppc64-softmmu ppc-softmmu riscv32-softmmu riscv64-softmmu s390x-softmmu sparc64-softmmu sparc-softmmu x86_64-softmmu" \
    --without-default-features \
    --glib=internal \
    --zlib=internal \
    --disable-pie \
    --enable-fdt=internal \
    --disable-modules \
    --disable-plugins \
    --enable-libretro \
    --audio-drv-list=libretro \
    --disable-sdl \
    -Dwrap_mode=forcefallback \
    ${EXTRA_CONFIGURE_ARGS[@]+"${EXTRA_CONFIGURE_ARGS[@]}"}

BUILD_OUT=libqemu_libretro.$LIB_EXT
make -j$NUMPROC $BUILD_OUT
cp $BUILD_OUT ../qemu_$CORE_SUFFIX.$LIB_EXT
