#!/usr/bin/bash

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

PROG=xz
VER=5.8.1
PKG=compress/xz
SUMMARY="XZ Utils - general-purpose data compression software"
DESC="Free general-purpose data compression software with a "
DESC+="high compression ratio"

SKIP_LICENCES=xz

forgo_isaexec

post_configure() {
    logcmd gmake -C $TMPDIR/$BUILDDIR/src/liblzma foo
}

TESTSUITE_SED="/libtool/d"

init
download_source $PROG v$VER
patch_source
prep_build autoconf -autoreconf
build
run_testsuite check
make_package
clean_up

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
