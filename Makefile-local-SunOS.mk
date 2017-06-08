# CUSTOM OPTIONS FOR SOLARIS/ILLUMOS (developed on OpenIndiana Hipster)

# For consistency, Sun LD is very much preferable on SunOS platforms
LD=/usr/ccs/bin/ld
#LD=/usr/gnu/bin/ld
export LD

# Solaris/illumos native LD has a feature to exec into another instead
#LD_ALTEXEC=/usr/gnu/bin/ld
#export LD_ALTEXEC

#LD_ALTEXEC=/usr/ccs/bin/ld
#export LD_ALTEXEC

CONFIG_OPTS += --without-gnu-ld --with-ld=/usr/ccs/bin/ld LD=$(LD)

GNU_LN=/usr/gnu/bin/ln
FIND=/usr/gnu/bin/find
GMAKE=/usr/bin/gmake
GPATCH=gpatch
GTAR=gtar

# Common tweaks: no GNU ld => no GCC private libs, including stack-smash protector
CFLAGS += -fno-stack-protector
CPPFLAGS += -fno-stack-protector
CXXFLAGS += -fno-stack-protector

# Custom options for libsodium
# * enforce equivalent of -fno-stack-protector via configure script
CONFIG_OPTS_libsodium = --disable-ssp

# Custom options for gsl
MAKE_INSTALL_ARGS_gsl = INSTALL="/usr/bin/ginstall -c"

# Custom options and patching for libcidr
MAKE_INSTALL_ARGS_libcidr = INSTALL="/usr/bin/ginstall -c" LN="$(GNU_LN)"
PREP_ACTION_BEFORE_PATCHING_libcidr = ( \
	for F in src/Makefile.inc src/GNUmakefile.inc Makefile.inc GNUmakefile.inc ; do \
		$(MV) $$F $$F.bak && \
		$(CP) $$F.bak $$F || exit ; \
	done ; )
PATCH_LIST_libcidr = $(ORIGIN_SRC_DIR)/.hacks/SunOS/libcidr-SunOS-01-shlib.patch
PATCH_OPTS_libcidr = -p1

PREP_ACTION_BEFORE_PATCHING_fty-rest = ( \
	  test -x /usr/lib/libsasl.so && \
	    $(CP) $(ORIGIN_SRC_DIR)/.hacks/SunOS/libsasl2.pc $(PKG_CONFIG_DIR)/ ; \
	)
