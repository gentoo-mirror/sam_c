# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit dot-a libtool flag-o-matic gnuconfig strip-linguas toolchain-funcs

DESCRIPTION="Tools necessary to build programs"
HOMEPAGE="https://sourceware.org/binutils/"

LICENSE="GPL-3+"
IUSE="cet debuginfod doc gprofng hardened multitarget +nls pgo +plugins static-libs test vanilla xxhash zstd"

# Variables that can be set here  (ignored for live ebuilds)
# PATCH_VER          - the patchset version
#                      Default: empty, no patching
# PATCH_BINUTILS_VER - the binutils version in the patchset name
#                    - Default: PV
# PATCH_DEV          - Use download URI https://dev.gentoo.org/~{PATCH_DEV}/distfiles/...
#                      for the patchsets

PATCH_VER=1
PATCH_DEV=dilfridge

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	SLOT=${PV}
elif [[ ${PV} == *9999 ]]; then
	inherit git-r3
	SLOT=$(ver_cut 1-2)
else
	PATCH_BINUTILS_VER=${PATCH_BINUTILS_VER:-${PV}}
	PATCH_DEV=${PATCH_DEV:-dilfridge}
	SRC_URI="mirror://gnu/binutils/binutils-${PV}.tar.xz https://sourceware.org/pub/binutils/releases/binutils-${PV}.tar.xz https://dev.gentoo.org/~${PATCH_DEV}/distfiles/binutils-${PV}.tar.xz"
	[[ -z ${PATCH_VER} ]] || SRC_URI="${SRC_URI}
		https://dev.gentoo.org/~${PATCH_DEV}/distfiles/binutils-${PATCH_BINUTILS_VER}-patches-${PATCH_VER}.tar.xz"
	SLOT=$(ver_cut 1-2)
	#KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
fi

#
# The cross-compile logic
#
export CTARGET=${CTARGET:-${CHOST}}
if [[ ${CTARGET} == ${CHOST} ]] ; then
	if [[ ${CATEGORY} == cross-* ]] ; then
		export CTARGET=${CATEGORY#cross-}
	fi
fi
is_cross() { [[ ${CHOST} != ${CTARGET} ]] ; }

#
# The dependencies
#
RDEPEND="
	>=sys-devel/binutils-config-3
	sys-libs/zlib
	debuginfod? (
		dev-libs/elfutils[debuginfod(-)]
	)
	zstd? ( app-arch/zstd:= )
"
DEPEND="
	${RDEPEND}
	xxhash? ( dev-libs/xxhash )
"
BDEPEND="
	doc? ( sys-apps/texinfo )
	pgo? (
		dev-util/dejagnu
		app-alternatives/bc
	)
	test? (
		dev-util/dejagnu
		app-alternatives/bc
	)
	nls? ( sys-devel/gettext )
	zstd? ( virtual/pkgconfig )
	app-alternatives/lex
	app-alternatives/yacc
"

RESTRICT="!test? ( test )"

MY_BUILDDIR=${WORKDIR}/build

src_unpack() {
	if [[ ${PV} == *9999 ]] ; then
		EGIT_REPO_URI="
			https://anongit.gentoo.org/git/proj/toolchain/binutils-patches.git
			https://github.com/gentoo/binutils-patches
		"
		EGIT_CHECKOUT_DIR=${WORKDIR}/patches-git
		git-r3_src_unpack
		mv patches-git/9999 patch || die

		if [[ ${PV} != 9999 ]] ; then
			EGIT_BRANCH=binutils-$(ver_cut 1)_$(ver_cut 2)-branch
		fi
		EGIT_REPO_URI="
			https://sourceware.org/git/binutils-gdb.git
			https://git.sr.ht/~sourceware/binutils-gdb
			https://gitlab.com/x86-binutils/binutils-gdb.git
		"
		S=${WORKDIR}/binutils
		EGIT_CHECKOUT_DIR=${S}
		git-r3_src_unpack
	else
		unpack ${P/-hppa64/}.tar.xz

		cd "${WORKDIR}" || die
		unpack binutils-${PATCH_BINUTILS_VER}-patches-${PATCH_VER}.tar.xz

		# _p patch versions are Gentoo specific tarballs ...
		local dir=${P%_p?}
		dir=${dir/-hppa64/}

		S=${WORKDIR}/${dir}
	fi

	cd "${WORKDIR}" || die
	mkdir -p "${MY_BUILDDIR}" || die
}

src_prepare() {
	local patchsetname
	if [[ ${PV} == 9999 ]] ; then
		patchsetname="from git master"
	elif [[ ${PV} == *9999 ]] ; then
		patchsetname="from git branch ${EGIT_BRANCH}"
	else
		patchsetname="${PATCH_BINUTILS_VER}-${PATCH_VER}"
	fi

	if [[ -n ${PATCH_VER} ]] || [[ ${PV} == *9999 ]] ; then
		if ! use vanilla; then
			einfo "Applying binutils patchset ${patchsetname}"
			eapply "${WORKDIR}/patch"
			einfo "Done."

			eapply "${FILESDIR}/sframe"

			# This is applied conditionally for now just out of caution.
			# It should be okay on non-prefix systems though. See bug #892549.
			if is_cross || use prefix; then
				eapply "${FILESDIR}"/binutils-2.43-linker-search-path.patch \
					   "${FILESDIR}"/binutils-2.43-linker-prefix.patch
			fi
		fi
	fi

	# Make sure our explicit libdir paths don't get clobbered, bug #562460
	sed -i \
		-e 's:@bfdlibdir@:@libdir@:g' \
		-e 's:@bfdincludedir@:@includedir@:g' \
		{bfd,opcodes}/Makefile.in || die

	# Apply things from PATCHES and user dirs
	default

	# Run misc portage update scripts
	gnuconfig_update
	elibtoolize --portage --no-uclibc
}

toolchain-binutils_bugurl() {
	printf "https://bugs.gentoo.org/"
}
toolchain-binutils_pkgversion() {
	printf "Gentoo ${PV}"
	[[ -n ${PATCH_VER} ]] && printf " p${PATCH_VER}"
}

src_configure() {
	# See https://www.gnu.org/software/make/manual/html_node/Parallel-Output.html
	# Avoid really confusing logs from subconfigure spam, makes logs far
	# more legible.
	MAKEOPTS="--output-sync=line ${MAKEOPTS}"

	# Setup some paths
	LIBPATH=/usr/$(get_libdir)/binutils/${CTARGET}/${PV}
	INCPATH=${LIBPATH}/include
	DATAPATH=/usr/share/binutils-data/${CTARGET}/${PV}
	if is_cross ; then
		TOOLPATH=/usr/${CHOST}/${CTARGET}
	else
		TOOLPATH=/usr/${CTARGET}
	fi
	BINPATH=${TOOLPATH}/binutils-bin/${PV}

	# Make sure we filter $LINGUAS so that only ones that
	# actually work make it through, bug #42033
	strip-linguas -u */po

	# Keep things sane
	strip-flags
	use cet && filter-flags -mindirect-branch -mindirect-branch=*
	use elibc_musl && append-ldflags -Wl,-z,stack-size=2097152
	lto-guarantee-fat

	local x
	echo
	for x in CATEGORY CBUILD CHOST CTARGET CFLAGS LDFLAGS ; do
		einfo "$(printf '%10s' ${x}:) ${!x}"
	done
	echo

	cd "${MY_BUILDDIR}" || die
	local myconf=()

	if use plugins ; then
		myconf+=( --enable-plugins )
	fi

	if use nls ; then
		myconf+=( --without-included-gettext )
	else
		myconf+=( --disable-nls )
	fi

	myconf+=( --with-system-zlib )

	# For bi-arch systems, enable a 64bit bfd. This matches the bi-arch
	# logic in toolchain.eclass. bug #446946
	#
	# We used to do it for everyone, but it's slow on 32bit arches. bug #438522
	case $(tc-arch) in
		ppc|sparc|x86) myconf+=( --enable-64-bit-bfd ) ;;
	esac

	use multitarget && myconf+=( --enable-targets=all --enable-64-bit-bfd )

	[[ -n ${CBUILD} ]] && myconf+=( --build=${CBUILD} )

	is_cross && myconf+=(
		--with-sysroot="${EPREFIX}"/usr/${CTARGET}
		--enable-poison-system-directories
	)

	myconf+=( --enable-secureplt )

	# mips can't do hash-style=gnu ...
	if [[ $(tc-arch) != mips ]] ; then
		myconf+=( --enable-default-hash-style=gnu )
	fi

	myconf+=(
		--prefix="${EPREFIX}"/usr
		--host=${CHOST}
		--target=${CTARGET}
		--datadir="${EPREFIX}"${DATAPATH}
		--datarootdir="${EPREFIX}"${DATAPATH}
		--infodir="${EPREFIX}"${DATAPATH}/info
		--mandir="${EPREFIX}"${DATAPATH}/man
		--bindir="${EPREFIX}"${BINPATH}
		--libdir="${EPREFIX}"${LIBPATH}
		--libexecdir="${EPREFIX}"${LIBPATH}
		--includedir="${EPREFIX}"${INCPATH}
		# portage's econf() does not detect presence of --d-d-t
		# because it greps only top-level ./configure. But not
		# libiberty's or bfd's configure.
		--disable-dependency-tracking
		--disable-silent-rules
		--enable-obsolete
		--enable-shared
		--enable-threads
		--enable-relro
		--enable-install-libiberty
		--enable-textrel-check=$(usex hardened error warning)
		# Things to think about
		#--enable-deterministic-archives
		--enable-new-dtags
		--disable-jansson
		--disable-werror
		--with-bugurl="$(toolchain-binutils_bugurl)"
		--with-pkgversion="$(toolchain-binutils_pkgversion)"
		$(use_enable static-libs static)
		$(use_with xxhash)
		$(use_with zstd)

		# Disable modules that are in a combined binutils/gdb tree, bug #490566
		--disable-{gdb,gdbserver,libbacktrace,libdecnumber,readline,sim}
		# Strip out broken static link flags: https://gcc.gnu.org/PR56750
		--without-stage1-ldflags
		# Change SONAME to avoid conflict across {native,cross}/binutils, binutils-libs. bug #666100
		--with-extra-soversion-suffix=gentoo-${CATEGORY}-${PN}-$(usex multitarget mt st)

		$(use_with debuginfod)

		# Avoid automagic dev-libs/msgpack dep, bug #865875
		--without-msgpack

		# Allow user to opt into CET for host libraries.
		# Ideally we would like automagic-or-disabled here.
		# But the check does not quite work on i686: bug #760926.
		$(use_enable cet)

		# We can enable this by default in future, but it's brand new
		# in 2.39 with several bugs:
		# - Doesn't build on musl (https://sourceware.org/PR29477)
		# - No man pages (https://sourceware.org/PR29521)
		# - Broken at runtime without Java (https://sourceware.org/PR29479)
		# - binutils-config (and this ebuild?) needs adaptation first (https://bugs.gentoo.org/865113)
		$(use_enable gprofng)

		# Enables colored disassembly by default (equivalent to passing
		# --disassembler-color=terminal to all objdump invocations).
		--enable-colored-disassembly
	)

	case ${CTARGET} in
		x86_64-*|aarch64*|arm64*|i[3456]*)
			# These hardening options are available from 2.39+ but
			# they unconditionally enable the behaviour even on arches
			# where e.g. execstacks can't be avoided.
			# See https://sourceware.org/PR29592.
			#
			# TODO: Get the logic for this fixed upstream so it doesn't
			# create impossible broken combinations on some arches, like mips.
			#
			# TODO: Get the logic for this fixed upstream so --disable-* works
			# as expected.
			myconf+=(
				--enable-warn-execstack=yes
				--enable-warn-rwx-segments=yes
			)

			if use hardened ; then
				myconf+=(
					# TODO: breaks glibc test suite
					#--enable-error-execstack=yes
					#--enable-error-rwx-segments=yes
					--enable-default-execstack=no
				)
			fi
			;;
		*)
			;;
	esac

	if use elibc_musl ; then
		# Override our earlier setting for musl, as textrels don't
		# work there at all. See bug #707660.
		myconf+=(
			--enable-textrel-check=error
		)
	fi

	if use test || { use pgo && tc-is-lto ; } ; then
		# -Wa,* needs to be consistent everywhere or lto-wrapper will complain
		filter-flags '-Wa,*'
	fi

	if ! is_cross ; then
		myconf+=( $(use_enable pgo pgo-build $(tc-is-lto && echo "lto" || echo "yes")) )

		if use pgo ; then
			# We let configure handle it for us because it has to run
			# the testsuite later on for profiling, and LTO isn't compatible
			# with the testsuite.
			filter-lto

			# bug #637066
			filter-flags -Wall -Wreturn-type

			export BUILD_CFLAGS="${CFLAGS}"
		fi
	fi

	ECONF_SOURCE="${S}" econf "${myconf[@]}"

	# Prevent makeinfo from running if doc is unset.
	if ! use doc ; then
		sed -i \
			-e '/^MAKEINFO/s:=.*:= true:' \
			Makefile || die
	fi
}

src_compile() {
	cd "${MY_BUILDDIR}" || die

	# see Note [tooldir hack for ldscripts]
	# see linker prefix patch
	emake \
		tooldir="${EPREFIX}${TOOLPATH}" \
		gentoo_prefix=$(usex prefix-guest "${EPREFIX}"/usr /usr) \
		all

	# only build info pages if the user wants them
	if use doc ; then
		emake info
	fi

	# we nuke the manpages when we're left with junk
	# (like when we bootstrap, no perl -> no manpages)
	find . -name '*.1' -a -size 0 -delete
}

src_test() {
	cd "${MY_BUILDDIR}" || die

	(
		# Tests don't expect LTO
		filter-lto

		# If we have e.g. -mfpmath=sse -march=pentium4 in CFLAGS,
		# we'll get lto1 warnings for some tests which cause
		# spurious failures because -mfpmath isn't passed at
		# link-time. Filter accordingly.
		#
		# Alternatively, we could pass C{C,XX}_FOR_TARGET with
		# some (ideally not all, surely would break some tests)
		# stuffed in.
		filter-flags '-mfpmath=*'

		# lto-wrapper warnings which confuse tests
		filter-flags '-Wa,*'

		# bug #637066
		filter-flags -Wall -Wreturn-type

		emake -k check \
			CFLAGS_FOR_TARGET="${CFLAGS_FOR_TARGET:-${CFLAGS}}" \
			CXXFLAGS_FOR_TARGET="${CXXFLAGS_FOR_TARGET:-${CXXFLAGS}}" \
			LDFLAGS_FOR_TARGET="${LDFLAGS_FOR_TARGET:-${LDFLAGS}}" \
			CFLAGS="${CFLAGS}" \
			CXXFLAGS="${CXXFLAGS}" \
			LDFLAGS="${LDFLAGS}"
	)
}

src_install() {
	local x d

	cd "${MY_BUILDDIR}" || die

	# see Note [tooldir hack for ldscripts]
	emake DESTDIR="${D}" tooldir="${EPREFIX}${LIBPATH}" install
	rm -rf "${ED}"/${LIBPATH}/bin || die
	use static-libs || find "${ED}" -name '*.la' -delete
	# Explicit "${ED}" as we need it to do things even w/ USE=-static-libs
	strip-lto-bytecode "${ED}"

	# Newer versions of binutils get fancy with ${LIBPATH}, bug #171905
	cd "${ED}"/${LIBPATH} || die
	for d in ../* ; do
		[[ ${d} == ../${PV} ]] && continue
		mv ${d}/* . || die
		rmdir ${d} || die
	done

	# Now we collect everything intp the proper SLOT-ed dirs
	# When something is built to cross-compile, it installs into
	# /usr/$CHOST/ by default ... we have to 'fix' that :)
	if is_cross ; then
		cd "${ED}"/${BINPATH} || die
		for x in * ; do
			mv ${x} ${x/${CTARGET}-} || die
		done

		if [[ -d ${ED}/usr/${CHOST}/${CTARGET} ]] ; then
			mv "${ED}"/usr/${CHOST}/${CTARGET}/include "${ED}"/${INCPATH}
			mv "${ED}"/usr/${CHOST}/${CTARGET}/lib/* "${ED}"/${LIBPATH}/
			rm -r "${ED}"/usr/${CHOST}/{include,lib}
		fi
	fi

	insinto ${INCPATH}
	local libiberty_headers=(
		# Not all the libiberty headers.  See libiberty/Makefile.in:install_to_libdir.
		demangle.h
		dyn-string.h
		fibheap.h
		hashtab.h
		libiberty.h
		objalloc.h
		splay-tree.h
	)
	doins "${libiberty_headers[@]/#/${S}/include/}"
	if [[ -d ${ED}/${LIBPATH}/lib ]] ; then
		mv "${ED}"/${LIBPATH}/lib/* "${ED}"/${LIBPATH}/ || die
		rm -r "${ED}"/${LIBPATH}/lib || die
	fi

	# Generate an env.d entry for this binutils
	insinto /etc/env.d/binutils
	cat <<-EOF > "${T}"/env.d
		TARGET="${CTARGET}"
		VER="${PV}"
		LIBPATH="${EPREFIX}${LIBPATH}"
	EOF
	newins "${T}"/env.d ${CTARGET}-${PV}

	# Handle documentation
	if ! is_cross ; then
		cd "${S}" || die
		dodoc README

		docinto bfd
		dodoc bfd/ChangeLog* bfd/README bfd/PORTING bfd/TODO

		docinto binutils
		dodoc binutils/ChangeLog binutils/NEWS binutils/README

		docinto gas
		dodoc gas/ChangeLog* gas/CONTRIBUTORS gas/NEWS gas/README*

		docinto gprof
		dodoc gprof/ChangeLog* gprof/TEST gprof/TODO gprof/bbconv.pl

		docinto ld
		dodoc ld/ChangeLog* ld/README ld/NEWS ld/TODO

		docinto libiberty
		dodoc libiberty/ChangeLog* libiberty/README

		docinto opcodes
		dodoc opcodes/ChangeLog*
	fi

	# Remove shared info pages
	rm -f "${ED}"/${DATAPATH}/info/{dir,configure.info,standards.info}

	docompress "${DATAPATH}"/{info,man}

	# Trim all empty dirs
	find "${ED}" -depth -type d -exec rmdir {} + 2>/dev/null
}

# Simple test to make sure our new binutils isn't completely broken.
# Skip if this binutils is a cross compiler.
#
# If coreutils is built with USE=multicall, some of these files
# will just be wrapper scripts, not actual ELFs we can test.
binutils_sanity_check() {
	pushd "${T}" >/dev/null

	einfo "Last-minute run tests with binutils in ${ED}${BINPATH} ..."

	cat <<-EOF > "${T}"/number.c
	int get_magic_number() {
		return 42;
	}
	EOF

	cat <<-EOF > "${T}"/test.c
	#include <stdio.h>
	int get_magic_number();

	int main() {
		printf("Hello Gentoo! Your magic number is: %d\n", get_magic_number());
	}
	EOF

	local -x LD_LIBRARY_PATH="${ED}${LIBPATH}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

	local opt opt2
	# TODO: test multilib variants?
	for opt in '' '-O2' ; do
		for opt2 in '-static' '-static-pie' '-fno-PIE -no-pie' ; do
			$(tc-getCC) ${opt} ${opt2} -B"${ED}${BINPATH}" "${T}"/number.c "${T}"/test.c -o "${T}"/test
			if "${T}"/test | grep -q "Hello Gentoo! Your magic number is: 42" ; then
				:;
			else
				die "Test with '${opt} ${opt2}' failed! Aborting to avoid broken binutils!"
			fi
		done
	done

	popd >/dev/null
}

pkg_preinst() {
	[[ -n ${ROOT} ]] && return 0
	[[ -d ${ED}${BINPATH} ]] || return 0
	[[ -n ${BOOTSTRAP_RAP} ]] || return 0
	is_cross && return 0
	binutils_sanity_check
}

pkg_postinst() {
	# Make sure this ${CTARGET} has a binutils version selected
	[[ -e ${EROOT}/etc/env.d/binutils/config-${CTARGET} ]] && return 0
	binutils-config ${CTARGET}-${PV} || eerror binutils-config returned an error
}

pkg_postrm() {
	local current_profile=$(binutils-config -c ${CTARGET})

	# If no other versions exist, then uninstall for this
	# target ... otherwise, switch to the newest version
	# Note: only do this if this version is unmerged.  We
	#       rerun binutils-config if this is a remerge, as
	#       we want the mtimes on the symlinks updated (if
	#       it is the same as the current selected profile)
	if [[ ! -e ${EPREFIX}${BINPATH}/ld ]] && [[ ${current_profile} == ${CTARGET}-${PV} ]] ; then
		local choice=$(binutils-config -l | grep ${CTARGET} | awk '{print $2}')
		choice=${choice//$'\n'/ }
		choice=${choice/* }
		if [[ -z ${choice} ]] ; then
			binutils-config -u ${CTARGET} || eerror binutils-config returned an error
		else
			binutils-config ${choice} || eerror binutils-config returned an error
		fi
	elif [[ $(CHOST=${CTARGET} binutils-config -c) == ${CTARGET}-${PV} ]] ; then
		binutils-config ${CTARGET}-${PV} || eerror binutils-config returned an error
	fi
}

# Note [slotting support]
# -----------------------
# Gentoo's layout for binutils files is non-standard as Gentoo
# supports slotted installation for binutils. Many tools
# still expect binutils to reside in known locations.
# binutils-config package restores symlinks into known locations,
# like:
#    /usr/bin/${CTARGET}-<tool>
#    /usr/bin/${CHOST}/${CTARGET}/lib/ldscrips
#    /usr/include/
#
# Note [tooldir hack for ldscripts]
# ---------------------------------
# Build system does not allow ./configure to tweak every location
# we need for slotting binutils hence all the shuffling in
# src_install(). This note is about SCRIPTDIR define handling.
#
# SCRIPTDIR defines 'ldscripts/' directory location. SCRIPTDIR value
# is set at build-time in ld/Makefile.am as: 'scriptdir = $(tooldir)/lib'
# and hardcoded as -DSCRIPTDIR='"$(scriptdir)"' at compile time.
# Thus we can't just move files around after compilation finished.
#
# Our goal is the following:
# - at build-time set scriptdir to point to symlinked location:
#   ${TOOLPATH}: /usr/${CHOST} (or /usr/${CHOST}/${CTARGET} for cross-case)
# - at install-time set scriptdir to point to slotted location:
#   ${LIBPATH}: /usr/$(get_libdir)/binutils/${CTARGET}/${PV}
