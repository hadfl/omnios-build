#!/usr/bin/bash
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}

# Copyright 2025 OmniOS Community Edition (OmniOSce) Association.

. ../../lib/build.sh

BUILD_DEPENDS_IPS="
    developer/acpi
    developer/nasm
"

PROG=uefi-edk2
PKG=system/bhyve/firmware
VER=20241101
SUMMARY="UEFI-EDK2(+CSM) firmware for bhyve"
DESC="$SUMMARY"

init
prep_build

fwdir=$DESTDIR/usr/share/bhyve/firmware
XFORM_ARGS+=" -D FWDIR=usr/share/bhyve/firmware"
logcmd mkdir -p $fwdir

export GMAKE=/usr/bin/gmake
export GAS=/usr/bin/gas
export GAR=/usr/bin/gar
export GLD=/usr/bin/gld
export GOBJCOPY=/usr/bin/gobjcopy

# Since the firmware builds will run in parallel in the background,
# put them in a new task which will be killed on interrupt.
newtask -c $$
trap "pkill -T0; exit" SIGINT

# Build the UEFI firmware

tag=il-edk2-stable202411-1
XFORM_ARGS+=" -D UEFITAG=$tag"

typeset -A jobs

(
    if [ -z "$FLAVOR" -o "$FLAVOR" = UEFI ]; then
        set_builddir uefi-edk2-$tag
        download_source bhyve-fw uefi-edk2 $tag
        ((EXTRACT_MODE)) && exit
        pushd $TMPDIR/$BUILDDIR >/dev/null
        logcmd cp OvmfPkg/License.txt $fwdir/LICENCE.$tag.OvmfPkg
        logcmd cp OvmfPkg/Bhyve/License.txt $fwdir/LICENCE.$tag.BhyvePkg
        for v in RELEASE DEBUG; do
            [ -n "$DEPVER" -a "$DEPVER" != $v ] && continue
            note "Building UEFI $v firmware"
            logcmd ./build clean
            if ! logcmd ./build -b -j $((MJOBS/2)) $v; then
                logmsg -e "UEFI $v build failed"
                exit 1
            fi
            if ! logcmd cp Build/BhyveX64/${v}_ILLGCC/FV/BHYVE_CODE.fd \
                $fwdir/BHYVE_$v.fd; then
                    logmsg -e "Copy UEFI firmware failed"
                    exit 1
            fi
        done
        if ! logcmd cp Build/BhyveX64/${v}_ILLGCC/FV/BHYVE_VARS.fd \
            $fwdir/BHYVE_VARS.fd; then
                logmsg -e "Copy UEFI variables failed"
                exit 1
        fi
        popd >/dev/null
    fi
) &
jobs[UEFI]=$!

# Also build the stock OVMF ROM
(
    if [ -z "$FLAVOR" -o "$FLAVOR" = OVMF ]; then
        set_builddir uefi-edk2-$tag
        download_source bhyve-fw uefi-edk2 $tag $TMPDIR/ovmf
        ((EXTRACT_MODE)) && exit
        pushd $TMPDIR/ovmf/$BUILDDIR >/dev/null
        for v in RELEASE DEBUG; do
            [ -n "$DEPVER" -a "$DEPVER" != $v ] && continue
            note "Building OVMF $v firmware"
            logcmd ./build clean
            if ! logcmd ./build -o -j $((MJOBS/2)) $v; then
                logmsg -e "OVMF $v build failed"
                exit 1
            fi
            if ! logcmd cp Build/OvmfX64/${v}_ILLGCC/FV/OVMF_CODE.fd \
                $fwdir/OVMF_$v.fd; then
                    logmsg -e "Copy OVMF firmware failed"
                    exit 1
            fi
        done
        popd >/dev/null
    fi
) &
jobs[OVMF]=$!

# The CSM firmware is still built from the old 2014 branch using gcc 4.

tag=il-udk2014.sp1-3
XFORM_ARGS+=" -D CSMTAG=$tag"

(
    if [ -z "$FLAVOR" -o "$FLAVOR" = CSM ]; then
        set_builddir uefi-edk2-$tag

        BUILDDIR=gcc-4.4.4 download_source gcc/dist gcc 4.4.4
        GCCPATH=$TMPDIR/gcc-4.4.4
        GCC=$GCCPATH/bin/gcc
        GXX=$GCCPATH/bin/g++
        PATH=$GCCPATH/bin:$BASEPATH

        export GCC GXX GCCPATH PATH

        download_source bhyve-fw uefi-edk2 $tag
        patch_source patches-csm
        ((EXTRACT_MODE)) && exit
        pushd $TMPDIR/$BUILDDIR >/dev/null

        # The CSM firmware build needs python2
        export PYTHON=python2

        logcmd cp OvmfPkg/License.txt $fwdir/LICENCE.$tag.OvmfPkg
        for v in RELEASE DEBUG; do
            [ -n "$DEPVER" -a "$DEPVER" != $v ] && continue
            note "Building CSM $v firmware"
            logcmd ./build clean
            if ! logcmd bash -x ./build -csm $v; then
                logmsg -e "CSM $v build failed"
                exit 1
            fi
            if ! logcmd cp Build/BhyveX64/${v}_ILLGCC/FV/BHYVE.fd \
                $fwdir/BHYVE_${v}_CSM.fd; then
                    logmsg -e "Copy CSM firmware failed"
                    exit 1
            fi
        done
        popd >/dev/null
    fi
) &
jobs[CSM]=$!

# Firmware branches are built in parallel, wait for them to finish
while (( ${#jobs[*]} > 0 )); do
    wait -fn -p pid ${jobs[*]}
    stat=$?
    for job in ${!jobs[*]}; do
        if (( ${jobs[$job]} == $pid )); then
            unset jobs[$job]
            if (( stat == 0 )); then
                logmsg -n "$job firmware build completed successfully"
            else
                logerr "$job firmware build failed ($stat)"
            fi
        fi
    done
done

((EXTRACT_MODE)) && exit
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
