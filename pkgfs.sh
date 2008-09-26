#!/bin/sh
#
# pkgfs - Packages from source distribution files.
#
#	A GNU's Stow alike approach, with some ideas from Gobolinux'
#	Compile and maybe others.
#
#-
# Copyright (c) 2008 Juan Romero Pardines.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
# IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-
#
# TODO
# 	Multiple distfiles in a package.
#	Multiple URLs to download source distribution files.
#	Support GNU/BSD-makefile style source distribution files.
# 	Actually do the symlink dance (stow/unstow).
#	Fix PKGFS_{C,CXX}FLAGS, aren't passed to the make environment.
#
#
# Default path to configuration file, can be overriden
# via the environment or command line.
#
: ${PKGFS_CONFIG_FILE:=/usr/local/etc/pkgfs.conf}

# Global private stuff
: ${_progname:=$(basename $0)}
: ${_TOP:=$(/bin/pwd -P 2>/dev/null)}
: ${_FETCH_CMD:=/usr/bin/ftp -a}
: ${_CKSUM_CMD:=/usr/bin/cksum -a rmd160}
: ${_AWK_CMD:=/usr/bin/awk}
: ${_MKDIR_CMD:=/bin/mkdir -p}
: ${_TAR_CMD:=/usr/bin/tar}
: ${_UNZIP_CMD:=/usr/pkg/bin/unzip}

_SFILE=
_EXTRACT_CMD=

usage() {
	cat << _EOF
$_progname: [-cef] <target> <file>

Targets
	build	Build package from <file>.
	info	Show information about <file>.

Options
	-c	Path to global configuration file.
		If not specified /usr/local/etc/pkgfs.conf is used.
	-e	Only extract the source distribution file(s).
	-f	Only fetch the source distribution file(s).

_EOF
	exit 1
}

check_path()
{
	eval orig="$1"

	case "$orig" in
	/)
		;;
	/*)
		orig="${orig%/}"
		;;
	*)
		orig="${_TOP}/${orig%/}"
		;;
	esac

	_SFILE="$orig"
}

show_info_from_local_tmpl()
{
	echo "Template build file definitions:"
	echo
	echo "	pkgname:	$pkgname"
	for i in "${distfiles}"; do
		[ -n "$i" ] && echo "	distfile:	$i"
	done
	echo "	URL:		$url"
	echo "	maintainer:	$maintainer"
	[ -n "${checksum}" ] && echo "	checksum:	$checksum"
	echo "	build_style:	$build_style"
	echo "	short_desc:	$short_desc"
	echo "$long_desc"
	echo
}

check_build_vars()
{
	local dfile=

	if [ -z "$distfiles" ]; then
		dfile="$pkgname$extract_sufx"
	elif [ -n "${distfiles}" ]; then
		dfile="$distfiles$extract_sufx"
	else
		echo "*** ERROR unsupported fetch state ***"
		exit 1
	fi

	dfile="$PKGFS_SRC_DISTDIR/$dfile"

	REQ_VARS="pkgname extract_sufx url build_style checksum"

	# Check if required vars weren't set.
	for i in "${REQ_VARS}"; do
		eval i=\""$$i\""
		if [ -z "$i" ]; then
			echo -n "*** ERROR: $i not set (incomplete build"
			echo	" file), aborting ***"
			exit 1
		fi
	done

	case "$extract_sufx" in
	.tar.bz2|.tar.gz|.tgz|.tbz)
		_EXTRACT_CMD="${_TAR_CMD} xvfz $dfile -C $PKGFS_BUILDDIR"
		;;
	.tar)
		_EXTRACT_CMD="${_TAR_CMD} xvf $dfile -C $PKGFS_BUILDDIR"
		;;
	.zip)
		_EXTRACT_CMD="${_UNZIP_CMD} -x $dfile -C $PKGFS_BUILDDIR"
		;;
	*)
		echo -n "*** ERROR: unknown 'extract_sufx' argument in build "
		echo	"file ***"
		exit 1
		;;
	esac
}

check_rmd160_cksum()
{
	local passed_var="$1"

	if [ -z "${distfiles}" ]; then
		dfile="$pkgname$extract_sufx"
	elif [ -n "${distfiles}" ]; then
		dfile="$distfiles$extract_sufx"
	else
		dfile="$passed_var$extract_sufx"
	fi

	origsum="$checksum"
	dfile="$PKGFS_SRC_DISTDIR/$dfile"
	filesum="$(${_CKSUM_CMD} $dfile | ${_AWK_CMD} '{print $4}')"
	if [ "$origsum" != "$filesum" ]; then
		echo "*** WARNING: checksum doesn't match (rmd160) ***"
		return 1
	fi

	return 0
}

fetch_source_distfiles()
{
	local file=

	if [ -z "$distfiles" ]; then
		file="$pkgname"
	else
		file="$distfiles"
	fi

	for f in "$file"; do
		if [ -f "$PKGFS_SRC_DISTDIR/$f$extract_sufx" ]; then
			check_rmd160_cksum $f
			if [ "$?" -eq 0 ]; then
				if [ -n "${only_fetch}" ]; then
					echo
					echo -n "=> checksum ok"
					echo 	" (only_fetch set)"
					exit 0
				fi
				return 0
			fi
		fi
		echo "*** Fetching $f ***"
		cd "$PKGFS_SRC_DISTDIR" && \
			${_FETCH_CMD} $url/$f$extract_sufx
		if [ "$?" -ne 0 ]; then
			echo -n "*** ERROR: there was an error fetching "
			echo	"'$f', aborting ***"
			exit 1
		else
			if [ -n "${only_fetch}" ]; then
				echo
				echo "=> checksum ok (only_fetch set)"
				exit 0
			fi
		fi
	done
}

check_build_dirs()
{
	check_path "${PKGFS_CONFIG_FILE}"
	. ${_SFILE}

	if [ ! -f "${PKGFS_CONFIG_FILE}" ]; then
		echo -n "*** ERROR: cannot find global config file: "
		echo	"'${PKGFS_CONFIG_FILE}' ***"
		exit 1
	fi

	if [ -z "${PKGFS_DESTDIR}" ]; then
		echo -n	"*** ERROR: PKGFS_DESTDIR not set in configuration"
		echo	" file ***"
		exit 1
	fi

	if [ -z "${PKGFS_BUILDDIR}" ]; then
		echo -n	"*** ERROR PKGFS_BUILDDIR not set in configuration"
		echo	" file ***"
		exit 1;
	fi

	if [ ! -d "$PKGFS_DESTDIR" ]; then
		${_MKDIR_CMD} "$PKGFS_DESTDIR"
		if [ "$?" -ne 0 ]; then
			echo -n "*** ERROR: couldn't create PKGFS_DESTDIR "
			echo "directory, aborting ***"
			exit 1
		fi
	fi

	if [ ! -d "$PKGFS_BUILDDIR" ]; then
		${_MKDIR_CMD} "$PKGFS_BUILDDIR"
		if [ "$?" -ne 0 ]; then
			echo -n "*** ERROR: couldn't create PKFS_BUILDDIR "
			echo "directory, aborting ***"
			exit 1
		fi
	fi

	if [ -z "$PKGFS_SRC_DISTDIR" ]; then
		echo "*** ERROR: PKGFS_SRC_DISTDIR is not set, aborting ***"
		exit 1
	fi

	${_MKDIR_CMD} "$PKGFS_SRC_DISTDIR"
	if [ "$?" -ne 0 ]; then
		echo "*** ERROR couldn't create PKGFS_SRC_DISTDIR, aborting ***"
		exit 1
	fi
}

build_pkg()
{
	echo "*** Extracting package: $pkgname ***"
	${_EXTRACT_CMD}
	if [ "$?" -ne 0 ]; then
		echo -n "*** ERROR: there was an error extracting the "
		echo "distfile, aborting *** "
		exit 1
	fi

	[ -n "${only_extract}" ] && exit 0

	echo "*** Building package: $pkgname ***"
	if [ -z "$wrksrc" ]; then
		if [ -z "$distfiles" ]; then
			cd $PKGFS_BUILDDIR/$pkgname
		else
			cd $PKGFS_BUILDDIR/$distfiles
		fi
	else
		cd $PKGFS_BUILDDIR/$wrksrc
	fi
	#
	# Packages using GNU autoconf
	#
	if [ "$build_style" = "gnu_configure" ]; then
		for i in "${configure_env}"; do
			[ -n "$i" ] && export "$i"
		done

		./configure --prefix="${PKGFS_DESTDIR}" "${configure_args}"
		if [ "$?" -ne 0 ]; then
			echo -n "*** ERROR building (configure state)"
			echo " $pkgname ***"
			exit 1
		fi
		if [ -z "$make_cmd" ]; then
			MAKE_CMD="/usr/bin/make"
		else
			MAKE_CMD="$make_cmd"
		fi

		/usr/bin/env CFLAGS="$PKGFS_CFLAGS" CXXFLAGS="$PKGFS_CXXFLAGS" \
			${MAKE_CMD} ${make_build_args}
		if [ "$?" -ne 0 ]; then
			echo "*** ERROR building (make stage) $pkgname ***"
			exit 1
		fi

		${MAKE_CMD} ${make_install_args} \
			install prefix="$PKGFS_DESTDIR/$pkgname"
		if [ "$?" -ne 0 ]; then
			echo "*** ERROR instaling $pkgname ***"
			exit 1
		fi

		echo "*** SUCCESSFUL build for $pkgname ***"
	fi
}

build_pkg_from_source()
{
	save_path="$PATH"

	export PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

	check_build_dirs
	check_build_vars
	fetch_source_distfiles
	build_pkg

	export PATH="${_save_path}"
}

#
# main()
#
args=$(getopt c:ef $*)
[ "$?" -ne 0 ] && usage

set -- $args
while [ "$#" -gt 0 ]; do
	case "$1" in
	-c)
		PKGFS_CONFIG_FILE="$2"
		shift
		;;
	-e)
		only_extract=yes
		;;
	-f)
		only_fetch=yes
		;;
	--)
		shift
		break
		;;
	esac
	shift
done

[ "$#" -gt 2 ] && usage

_target="$1"
if [ -z "${_target}" ]; then
	echo "*** ERROR missing target ***"
	usage
fi

_buildfile="$2"
if [ -z "${_buildfile}" -o ! -f "${_buildfile}" ]; then
	echo "*** ERROR: invalid template file '${_buildfile}', aborting ***"
	exit 1
fi

check_path "${_buildfile}"
. ${_SFILE}


# Main switch
case "${_target}" in
build)
	build_pkg_from_source
	;;
info)
	show_info_from_local_tmpl
	;;
*)
	echo "*** ERROR invalid target '${_target}' ***"
	usage
esac

# Agur
exit 0
