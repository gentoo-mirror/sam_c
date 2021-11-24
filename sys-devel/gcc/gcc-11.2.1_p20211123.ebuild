# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="7"

inherit toolchain

GIT_COMMIT="78225f05ce28321ddb8418174f4fe1e28ba08047"
SRC_URI="https://github.com/gcc-mirror/gcc/archive/${GIT_COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${PN}-${GIT_COMMIT}"

#KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ia64 ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"

BDEPEND="${CATEGORY}/binutils"

src_prepare() {
	toolchain_src_prepare

	if is_crosscompile ; then
		# bug #803371
		eapply "${FILESDIR}"/gcc-11.2.0-cross-compile-include.patch
	fi

	eapply_user
}
