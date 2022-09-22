# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
NEED_EMACS=25

inherit elisp

DESCRIPTION="A Git porcelain inside Emacs"
HOMEPAGE="https://magit.vc/"
if [[ ${PV} == 9999 ]] ; then
	EGIT_REPO_URI="https://github.com/magit/magit"
	inherit git-r3
else
	SRC_URI="https://github.com/magit/magit/archive/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~x86 ~amd64-linux ~x86-linux"
fi

LICENSE="GPL-3+"
SLOT="0"

S="${WORKDIR}/${P}/lisp"
SITEFILE="50${PN}-gentoo.el"
ELISP_TEXINFO="../docs/*.texi"
DOCS="../README.md ../docs/AUTHORS.md ../docs/RelNotes/*"

DEPEND="
	>=app-emacs/dash-2.19.1
	app-emacs/libegit2
	>=app-emacs/transient-0.3.6
	>=app-emacs/with-editor-3.0.5

	app-emacs/compat
"
RDEPEND="${DEPEND} >=dev-vcs/git-2.0.0"
DEPEND="${DEPEND} sys-apps/texinfo"

src_prepare() {
	default
	echo "(setq magit-version \"${PV}\")" > magit-version.el || die
}