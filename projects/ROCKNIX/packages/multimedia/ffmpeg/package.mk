# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2017-present Team LibreELEC (https://libreelec.tv)
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="ffmpeg"
PKG_VERSION="7.1.1"
PKG_SHA256="733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1"
PKG_LICENSE="GPL-3.0-only"
PKG_SITE="https://ffmpeg.org"
PKG_URL="http://ffmpeg.org/releases/ffmpeg-${PKG_VERSION}.tar.xz"
PKG_DEPENDS_TARGET="toolchain zlib bzip2 openssl speex libxml2 systemd"
PKG_LONGDESC="FFmpeg is a complete, cross-platform solution to record, convert and stream audio and video."

# v4l2 patches from base LibreELEC, ported to 7.1.1
PKG_PATCH_DIRS+=" v4l2-request v4l2-drmprime"

post_unpack() {
  echo "${PKG_VERSION}" > ${PKG_BUILD}/RELEASE
}

# Dependencies
get_graphicdrivers

PKG_FFMPEG_HWACCEL="--enable-hwaccels"

# RK3588 uses MPP path (RKVDEC/RKVENC), not V4L2
case ${DEVICE} in
  RK3588*)
    V4L2_SUPPORT=no
  ;;
  *)
    case ${DEVICE} in
      RK*)
        PKG_PATCH_DIRS+=" vf-deinterlace-v4l2m2m"
      ;;
    esac
  ;;
esac

# libdrm is needed by both V4L2 and rkmpp paths
PKG_DEPENDS_TARGET+=" libdrm"
PKG_NEED_UNPACK+=" $(get_pkg_directory libdrm)"

if [ "${V4L2_SUPPORT}" = "yes" ]; then
  PKG_FFMPEG_V4L2="--enable-v4l2_m2m --enable-libdrm"

  case ${DEVICE} in
    PC|RK*|S922X)
      PKG_V4L2_REQUEST="yes"
    ;;
    *)
      PKG_V4L2_REQUEST="no"
    ;;
  esac

  if [ "${PKG_V4L2_REQUEST}" = "yes" ]; then
    PKG_FFMPEG_V4L2+=" --enable-libudev --enable-v4l2-request"
  else
    PKG_FFMPEG_V4L2+=" --disable-libudev --disable-v4l2-request"
  fi
else
  # V4L2 disabled (e.g., RK3588) — still need libdrm for rkmpp
  PKG_FFMPEG_V4L2="--disable-v4l2_m2m --enable-libdrm --disable-libudev --disable-v4l2-request"
fi

if [ "${VAAPI_SUPPORT}" = "yes" ]; then
  PKG_DEPENDS_TARGET+=" libva"
  PKG_NEED_UNPACK+=" $(get_pkg_directory libva)"
  PKG_FFMPEG_VAAPI="--enable-vaapi"
else
  PKG_FFMPEG_VAAPI="--disable-vaapi"
fi

if [ "${VDPAU_SUPPORT}" = "yes" -a "${DISPLAYSERVER}" = "wl" ]; then
  PKG_DEPENDS_TARGET+=" libvdpau"
  PKG_NEED_UNPACK+=" $(get_pkg_directory libvdpau)"
  PKG_FFMPEG_VDPAU="--enable-vdpau"
else
  PKG_FFMPEG_VDPAU="--disable-vdpau"
fi

if build_with_debug; then
  PKG_FFMPEG_DEBUG="--enable-debug --disable-stripping"
else
  PKG_FFMPEG_DEBUG="--disable-debug --enable-stripping"
fi

if target_has_feature neon; then
  PKG_FFMPEG_FPU="--enable-neon"
else
  PKG_FFMPEG_FPU="--disable-neon"
fi

if [ "${TARGET_ARCH}" = "x86_64" ]; then
  PKG_DEPENDS_TARGET+=" nasm:host"
fi

# Rockchip MPP hardware decode/encode
PKG_FFMPEG_RKMPP=""
case ${DEVICE} in
  RK*)
    PKG_DEPENDS_TARGET+=" rkmpp"
    PKG_FFMPEG_RKMPP="--enable-rkmpp"
  ;;
esac

# x264 H.264 software encoding (aarch64 only — arm32 compat layer only needs decode)
if [ "${TARGET_ARCH}" != "arm" ]; then
  PKG_DEPENDS_TARGET+=" x264"
  PKG_FFMPEG_X264="--enable-libx264"
else
  PKG_FFMPEG_X264="--disable-libx264"
fi

# x265 H.265/HEVC software encoding (aarch64 only — no arm32 emulator needs HEVC encode)
if [ "${TARGET_ARCH}" != "arm" ]; then
  PKG_DEPENDS_TARGET+=" x265"
  PKG_FFMPEG_X265="--enable-libx265"
else
  PKG_FFMPEG_X265="--disable-libx265"
fi

# AV1 software decoding via dav1d
if target_has_feature "(neon|sse)"; then
  PKG_DEPENDS_TARGET+=" dav1d"
  PKG_NEED_UNPACK+=" $(get_pkg_directory dav1d)"
  PKG_FFMPEG_AV1="--enable-libdav1d"
else
  PKG_FFMPEG_AV1="--disable-libdav1d"
fi

pre_configure_target() {
  cd ${PKG_BUILD}
  rm -rf .${TARGET_NAME}
  # GCC 14 on aarch64: LSE atomics in libgcc require -latomic
  # Must go in extra-libs (after library flags) not LDFLAGS (before)
  if [ "${TARGET_ARCH}" = "aarch64" ]; then
    PKG_FFMPEG_LIBS+=" -latomic"
  fi
}

if [ "${FFMPEG_TESTING}" = "yes" ]; then
  PKG_FFMPEG_TESTING="--enable-encoder=wrapped_avframe --enable-muxer=null"
else
  PKG_FFMPEG_TESTING="--disable-programs"
fi

configure_target() {
  ./configure --prefix="/usr" \
              --cpu="${TARGET_CPU}" \
              --arch="${TARGET_ARCH}" \
              --enable-cross-compile \
              --cross-prefix="${TARGET_PREFIX}" \
              --sysroot="${SYSROOT_PREFIX}" \
              --sysinclude="${SYSROOT_PREFIX}/usr/include" \
              --target-os="linux" \
              --nm="${NM}" \
              --ar="${AR}" \
              --as="${CC}" \
              --cc="${CC}" \
              --ld="${CC}" \
              --host-cc="${HOST_CC}" \
              --host-cflags="${HOST_CFLAGS}" \
              --host-ldflags="${HOST_LDFLAGS}" \
              --extra-cflags="${CFLAGS}" \
              --extra-ldflags="${LDFLAGS}" \
              --extra-libs="${PKG_FFMPEG_LIBS}" \
              --disable-static \
              --enable-shared \
              --enable-gpl \
              --enable-version3 \
              --enable-logging \
              --disable-doc \
              ${PKG_FFMPEG_DEBUG} \
              --enable-pic \
              --pkg-config="${TOOLCHAIN}/bin/pkg-config" \
              --enable-optimizations \
              --disable-extra-warnings \
              --enable-avdevice \
              --enable-avcodec \
              --enable-avformat \
              --enable-swscale \
              --enable-postproc \
              --enable-avfilter \
              --disable-devices \
              --enable-pthreads \
              --enable-network \
              --disable-gnutls --enable-openssl \
              --disable-gray \
              --enable-swscale-alpha \
              --disable-small \
              ${PKG_FFMPEG_V4L2} \
              ${PKG_FFMPEG_VAAPI} \
              ${PKG_FFMPEG_VDPAU} \
              ${PKG_FFMPEG_RKMPP} \
              --enable-runtime-cpudetect \
              --disable-hardcoded-tables \
              --disable-encoders \
              --enable-encoder=ac3 \
              --enable-encoder=aac \
              --enable-encoder=wmav2 \
              --enable-encoder=mjpeg \
              --enable-encoder=png \
              --enable-encoder=libx264 \
              --enable-encoder=libx265 \
              ${PKG_FFMPEG_HWACCEL} \
              --disable-muxers \
              --enable-muxer=spdif \
              --enable-muxer=adts \
              --enable-muxer=asf \
              --enable-muxer=ipod \
              --enable-muxer=mpegts \
              --enable-muxer=mp4 \
              --enable-muxer=matroska \
              --enable-demuxers \
              --enable-parsers \
              --enable-bsfs \
              --enable-protocol=http \
              --disable-indevs \
              --disable-outdevs \
              --enable-filters \
              --disable-avisynth \
              --enable-bzlib \
              --disable-lzma \
              --disable-alsa \
              --disable-frei0r \
              --disable-libopencore-amrnb \
              --disable-libopencore-amrwb \
              --disable-libopencv \
              --disable-libdc1394 \
              --disable-libfreetype \
              --disable-libgsm \
              --disable-libmp3lame \
              --disable-libopenjpeg \
              --disable-librtmp \
              ${PKG_FFMPEG_AV1} \
              --enable-libspeex \
              --disable-libtheora \
              --disable-libvo-amrwbenc \
              --disable-libvorbis \
              --disable-libvpx \
              ${PKG_FFMPEG_X264} \
              ${PKG_FFMPEG_X265} \
              --disable-libxavs \
              --enable-libxml2 \
              --disable-libxvid \
              --enable-zlib \
              --enable-asm \
              --disable-altivec \
              ${PKG_FFMPEG_FPU} \
              --disable-symver \
              ${PKG_FFMPEG_TESTING}
}

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/share/ffmpeg/examples
}
