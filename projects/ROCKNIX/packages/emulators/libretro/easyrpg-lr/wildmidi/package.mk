################################################################################
#      This file is part of OpenELEC - http://www.openelec.tv
#      Copyright (C) 2009-2012 Stephan Raue (stephan@openelec.tv)
#
#  This Program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.
#
#  This Program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with OpenELEC.tv; see the file COPYING.  If not, write to
#  the Free Software Foundation, 51 Franklin Street, Suite 500, Boston, MA 02110, USA.
#  http://www.gnu.org/copyleft/gpl.html
################################################################################

PKG_NAME="wildmidi"
PKG_VERSION="405ca73adfa11659b7579f0b09df1303f42659a4" # tag wildmidi-0.4.3 | last-known-tag: wildmidi-0.4.3 # reverted: HEAD/0.4.6 CMakeLists.txt incompatible with cmake 3.30 (WRITE_BASIC_PACKAGE_VERSION_FILE missing VERSION, INSTALL missing DESTINATION)
PKG_SITE="https://github.com/Mindwerks/wildmidi"
PKG_URL="${PKG_SITE}/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="WildMIDI is a simple software midi player which has a core softsynth library that can be used with other applications."

PKG_TOOLCHAIN="cmake"

PKG_CMAKE_OPTS_TARGET="-DWANT_PLAYER=OFF -DWANT_ALSA=ON"
