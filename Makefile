# NOTE: GNU Makefile syntax support may be expected by recipe code below.
# This file aims to automate building the FTY dependencies and components
# in correct order. System packaged dependencies are assumed to be present.
# Also note that the default recipes below make an accent on building and
# checking the project code quickly. Unrequired but time-consuming bits,
# such as generation and verification of docs, are skipped.
#
# It supports several actions on components (assumed to exist in same-named
# subdirectories if the workspace root where this Makefile exists), such as
# build/componentname or check/componentname. See the end of this file for
# a list of catch-all rule names.
#
# In addition to that, the Makefile also aids in source code management by
# providing simple rules to sync the current subcomponent workspace to its
# relevant upstream default branch, and to regenerate zproject-based source.
#
# Copyright (C) 2017-2019 by Eaton
# Authors: Jim Klimov <EvgenyKlimov@eaton.com>
#
# POC1 : manual naming and ordering
# POC2 : parse project.xml's to build an included Makefile

### NOTE: Each HELP_* entry is a double-quoted string (or chain of strings)
### that are eventually passed to a shell `echo` command
# Standalone keywords
HELP_BASETGT = "Common targets include :"
# "Percented" target patterns that act on components
HELP_COMPTGT = "The following pattern-targets can be called for each component, like" \
               "running a 'make rebuild/fty-rest' or 'make distcheck/fty-example':"
# Explanation of touch-files used in build
HELP_TOUCHFILES = "The following 'touch-files' are tracked under BUILD_OBJ_DIR for each" \
                  "component and chain by dependency order to check out, build and test." \
                  "This detail is primarily provided to clarify dependency tree for other targets:"
HELP_SPECIALDEVTGT = "The following (pattern-)targets are special for development activity in" \
                     "a workspace made with the FTY dispatcher repo:"
HELP_SPECIALTGT = "The following targets are special for maintenance of the workspace, etc:"
# The Makefile supports including additional ones to customize its behavior
# for non-default use-cases. Those files can add their help to this variable:
HELP_ADDONS =

# Details defined below
#.PHONY: all install clean
all: build-fty
HELP_BASETGT += "    all	Builds all stable fty components and their 3rd party deps"
install: install-fty
HELP_BASETGT += "    install	(Builds and) Installs all stable fty components"
uninstall: uninstall-all uninstall-fty-experimental
HELP_BASETGT += "    uninstall	Uninstalls all stable and experimental fty components"
clean: clean-all clean-fty-experimental
HELP_BASETGT += "    clean	Cleans all stable and experimental fty components and deps"
check: check-all
HELP_BASETGT += "    check	Checks all stable fty components and their 3rd party deps"
check-verbose: check-verbose-all
HELP_BASETGT += "    check-verbose	Checks all stable fty components and deps verbosely"
dist: dist-all
HELP_BASETGT += "    dist	Dist's all stable fty components and deps"
distclean: distclean-all
HELP_BASETGT += "    distclean	Distclean's all stable fty components and deps"
distcheck: distcheck-all
HELP_BASETGT += "    distcheck	Distcheck's all stable fty components and deps"
valgrind: memcheck
memcheck: memcheck-all
HELP_BASETGT += "    valgrind / memcheck	Checks all stable fty components and deps with valgrind"

experimental: build-fty-experimental
all-experimental: build-fty-experimental
HELP_BASETGT += "    (all-)experimental	Builds all experimental fty components (and deps)"

BIOS_LOG_LEVEL ?= LOG_DEBUG
export BIOS_LOG_LEVEL
BIOS_LOG_INIT_LEVEL ?= LOG_CRIT
export BIOS_LOG_INIT_LEVEL

OSIMAGE_DISTRO ?= $(shell if test -s /etc/update-rc3.d/image-os-type.conf ; then grep OSIMAGE_DISTRO= /etc/update-rc3.d/image-os-type.conf | sed -e 's,^.*=,,' -e 's,^"\(.*\)" *$$,\1,' -e "s,^'\(.*\)' *$$,\1,"; fi)

BUILD_ARCH ?= $(shell uname -m)
ARCH=$(BUILD_ARCH)
export ARCH

ifeq ($(OSIMAGE_DISTRO),Debian_10.0)
BUILD_OS ?= LinuxDeb10
else
ifeq ($(OSIMAGE_DISTRO),Debian_9.0)
BUILD_OS ?= LinuxDeb9
else
ifeq ($(OSIMAGE_DISTRO),Debian_8.0)
### Legacy compat for existing workspaces
ifeq ($(shell ls -1d .build/Linux-$(BUILD_ARCH)* .install/Linux-$(BUILD_ARCH)* .srcclone/Linux-$(BUILD_ARCH)* 2>/dev/null || true),)
BUILD_OS ?= LinuxDeb8
else
BUILD_OS ?= Linux
endif
else
BUILD_OS ?= $(shell uname -s)
endif
endif
endif

# Current legacy default, and something to have definite recipe behavior
ifeq ($(strip $(CI_CZMQ_VER)),)
CI_CZMQ_VER ?= 3
endif

# $(abs_srcdir) defaults to location of this Makefile (and accompanying sources)
# Can override on command-line if needed for any reason, for example
#   cd /tmp/bld-fty && make -f ~/FTY/Makefile abs_srcdir=~/FTY/ all
abs_srcdir:=$(strip $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST)))))
abs_builddir:=$(shell pwd)

# This is where real original sources reside (e.g. where to copy from,
# if it comes to that), directly where submodules are checked out into.
ORIGIN_SRC_DIR ?= $(abs_srcdir)

# This is the directory under which a clone of components' checked-out
# sources live, as a a wipable local git clone of those submodules to
# support the multi-host builds from same source checkout (autoreconf
# changes the source tree and so depends on tools available on the host).
BUILD_SRC_DIR ?= $(abs_builddir)/.srcclone/$(BUILD_OS)-$(BUILD_ARCH)-czmq_$(CI_CZMQ_VER)

# Subdirectory where out-of-tree builds happen (with a sub-dir per
# component where object files and other products are created). For a
# few components this is effectively used as their BUILD_SRC_DIR too
# (e.g. those that are not managed by autotools and so do not easily
# support out-of-tree builds).
BUILD_OBJ_DIR ?= $(abs_builddir)/.build/$(BUILD_OS)-$(BUILD_ARCH)-czmq_$(CI_CZMQ_VER)

# Root dir where tools are installed into (using their default paths inside)
# We also do use some of those tools (e.g. GSL) during further builds.
# Note that the value of INSTDIR may get compiled into libraries and other
# such stuff, so if you are building just a prototype area for packaging,
# consider setting an explicit PREFIX (not relative to DESTDIR or INSTDIR).
DESTDIR ?=
INSTDIR ?= $(abs_builddir)/.install/$(BUILD_OS)-$(BUILD_ARCH)-czmq_$(CI_CZMQ_VER)
# Note: DESTDIR is a common var that is normally added during "make install"
# but in out case this breaks dependencies written into the built libs if
# the build-products are used in-place. INSTDIR is effectively the expected
# run-time root for the built products (so when packaging, use empty INSTDIR
# and a temporary DESTDIR location to trap up the bins, instead).
PREFIX = $(INSTDIR)/usr
PREFIX_ETCDIR = $(INSTDIR)/etc

PATH:=/usr/lib/ccache:$(DESTDIR)$(PREFIX)/libexec/fty:$(DESTDIR)$(PREFIX)/libexec/bios:$(DESTDIR)$(PREFIX)/share/fty/scripts:$(DESTDIR)$(PREFIX)/share/bios/scripts:$(DESTDIR)$(PREFIX)/local/bin:$(DESTDIR)$(PREFIX)/bin:/usr/libexec/fty:/usr/libexec/bios:/usr/share/fty/scripts:/usr/share/bios/scripts:/usr/local/bin:/usr/bin:${PATH}
export PATH
export DESTDIR

# TOOLS used below
MKDIR=/bin/mkdir -p
RMDIR=/bin/rm -rf
RMFILE=/bin/rm -f
RM=$(RMFILE)
MV=/bin/mv -f
GNU_CP=/bin/cp
CP=$(GNU_CP) -pf
TOUCH=/bin/touch
FIND=find
SED=sed
GPATCH=patch
# We need `tar` with support for `--exclude=...` - e.g. a GNU tar
GTAR=tar
LN=ln
LN_S=$(GNU_LN) -s -f
# GNU ln with relative support
GNU_LN=$(LN)
LN_S_R=$(GNU_LN) -s -f -r
# GNU Make required (overridable via includes below)
GMAKE=make
MAKE=$(GMAKE)

# Our current codebase works with at least gcc-4.8 for most components,
# but some require gcc-4.9+ for C++11 regex support, among other things.
# However at this time there are warnings for newer compilers (gcc-5+),
# so we do not build for them by default either.
# Note that newer distros marched on, so to build in them use e.g.
#   GCC_VERSION=8 BUILD_OS=LinuxDeb10
ifeq ($(OSIMAGE_DISTRO),Debian_10.0)
GCC_VERSION?=8
else
ifeq ($(OSIMAGE_DISTRO),Debian_8.0)
GCC_VERSION?=4.9
endif
endif

ifeq ($(strip $(GCC_VERSION)),)
GCC_VERSION_SUFFIX=
else
GCC_VERSION_SUFFIX=-$(GCC_VERSION)
endif
CC=gcc$(GCC_VERSION_SUFFIX)
CXX=g++$(GCC_VERSION_SUFFIX)

export CC
export CXX

LDFLAGS ?=
ifeq ($(OSIMAGE_DISTRO),Debian_10.0)
# Avoid setting RUNPATH instead of older preference of RPATH - it confuses the
# libtool into generating an explicit LD_LIBRARY_PATH into the wrapper scripts
LDFLAGS += -Wl,--disable-new-dtags
export LDFLAGS
endif

# "ALL" are the components tracked by this makefile, even if not required
# for an FTY build (e.g. gsl and zproject are not an always used codepath)
COMPONENTS_ALL =
# "FTY" are components in "fty-*" submodules and the dependencies they pull
COMPONENTS_FTY =
# "FTY_EXPERIMENTAL" are components in "fty-*" submodules which are not yet
# mainstream (e.g. added recently and builds are expected to fail) and the
# dependencies they pull
COMPONENTS_FTY_EXPERIMENTAL =

# https://www.gnu.org/software/make/manual/html_node/Force-Targets.html
.PHONY: FORCE
FORCE:
	@true

# Dependencies on touch-files are calculated by caller
# If the *_sub is called - it must do its work
# Tell GMake to keep any secondary files such as:
# */.prepped */.autogened */.configured */.built */.installed
# NOTE/TODO: Get this to work with explicit list of patterns to filenames
.SECONDARY:
#.PRECIOUS: %/.prep-newestfetch %/.prep-builtgitindex %/.prep-builtcommit %/.prepped %/.autogened %/.configured %/.built %/.installed %/.checked %/.checked-verbose %/.distchecked %/.disted %/.memchecked

# TODO : add a mode to check that a workspace has changed (dev work, git
# checked out another branch, etc.) to trigger rebuilds of a project.
# Otherwise it trusts the .prepped and other state flag-files.
# Maybe find all files newer than exiting .prepped ?

# Note: per http://lists.busybox.net/pipermail/buildroot/2013-May/072556.html
# the autogen, autoreconf and equivalents mangle the source tree
define autogen_sub
	( ( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone) \
	        cd "$(ORIGIN_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" || exit ;; \
	    xclone*-obj) \
	        cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" || exit ;; \
	    xclone*-src|*) \
	        cd "$(BUILD_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" || exit ;; \
	  esac && \
	    ( if [ -x ./autogen.sh ]; then \
	        ./autogen.sh  || exit ; \
	      elif [ -x ./buildconf ]; then \
	        ./buildconf || exit ; \
	      elif [ -f configure.ac ]; then \
	        autoreconf -fiv || exit ; \
	      elif [ -f CMakeLists.txt ]; then \
	        echo "WARNING: Only CMakeLists.txt found for $(1)" ; \
	        printf '#!/bin/sh\ncmake "$(BUILD_SRC_DIR)/$(1)" -DCMAKE_SOURCE_DIR="$(BUILD_SRC_DIR)/$(1)" -DCMAKE_INSTALL_PREFIX="$(DESTDIR)$(PREFIX)" -DCMAKE_PREFIX_PATH="$(DESTDIR)$(PREFIX)" -DPKG_CONFIG_USE_CMAKE_PREFIX_PATH=true $(CONFIG_OPTS_$(1))\n' \
	        > configure && chmod +x configure || exit ; \
	      else echo "FATAL: Unsupported source project type" >&2 ; exit 2 ; \
	      fi ) && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)"/.autogened && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.autogen-failed ) || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)"/.autogen-failed ; exit 1; } \
	)
endef

# Note: this requires that "configure" has already been created in the sources
# If custom "CONFIG_OPTS_$(1)" were defined, they are appended to configuration
# Note that depending on this component's PREP_TYPE (or lack thereof) there is
# a different possible location for the generated configure script and sources,
# while for different "make" rules afterwards the working directory is always
# under BUILD_OBJ_DIR.
define configure_sub
	( ( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)     CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" \
	                "$(ORIGIN_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))/configure" \
	                    $(CONFIG_OPTS) $(CONFIG_OPTS_$(1)) || exit ;; \
	    xclone*-obj) CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" \
	                "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))/configure" \
	                    $(CONFIG_OPTS) $(CONFIG_OPTS_$(1)) || exit ;; \
	    xclone*-src|*) CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" \
	                "$(BUILD_SRC_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))/configure" \
	                    $(CONFIG_OPTS) $(CONFIG_OPTS_$(1)) || exit ;; \
	  esac && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".configured && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.configure-failed ) || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".configure-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define build_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) $(MAKE_COMMON_ARGS_$(1)) $(MAKE_ALL_ARGS_$(1)) all && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".built && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.build-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".build-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define install_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) DESTDIR="$(DESTDIR)" \
	    $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) install && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".installed && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.install-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".install-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define check_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  if [ -n "$(MAKE_CHECK_TARGET_$(1))" ] ; then CHECK_TARGET="$(MAKE_CHECK_TARGET_$(1))" ; else CHECK_TARGET=check ; fi && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) DESTDIR="$(DESTDIR)" \
	    $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) $$CHECK_TARGET && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".checked && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.check-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".check-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
# This is just an additional option flag in zproject generated makefiles,
# to run the selftest programs in verbose mode. Note that non-zeromq
# ecosystem projects can lack this recipe and might fail due to that.
define check_verbose_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  if [ -n "$(MAKE_CHECK_TARGET_$(1))" ] ; then CHECK_TARGET="$(MAKE_CHECK_TARGET_$(1))" ; else CHECK_TARGET=check-verbose ; fi && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) DESTDIR="$(DESTDIR)" \
	    $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) $$CHECK_TARGET && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".checked-verbose && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.check-verbose-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".check-verbose-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
# Unfortunately, one may have to be careful about passing CONFIG_OPTS
# values with spaces; note that values inside CONFIG_OPTS may be quoted.
# Also it seems that both envvar and makefile-arg settings are needed :\
#	    DISTCHECK_CONFIGURE_FLAGS='$(CONFIG_OPTS) $(CONFIG_OPTS_$(1))' 
define distcheck_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) \
	    DISTCHECK_CONFIGURE_FLAGS='$(CONFIG_OPTS) $(CONFIG_OPTS_$(1))' \
	    distcheck && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".distchecked && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.distcheck-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".distcheck-failed ; exit 1; } \
	)
endef

define dist_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  if [ -n "$(MAKE_DIST_TARGET_$(1))" ] ; then DIST_TARGET="$(MAKE_DIST_TARGET_$(1))" ; else DIST_TARGET=check-verbose ; fi && \
	  $(MAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) \
	    $$DIST_TARGET && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".disted && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.dist-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".dist-failed ; exit 1; } \
	)
endef

# This assumes that the Makefile is present in submodule's build-dir
define memcheck_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  $(MAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) \
	    memcheck && \
	  $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".memchecked && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.memcheck-failed || \
	  { $(TOUCH) "$(BUILD_OBJ_DIR)/$(1)/".memcheck-failed ; exit 1; } \
	)
endef

# NOTE: This was not implemented in GSL Makefile so usual methods errored out.
# Note that we can have removed source/build dir for a component (rebuild/*)
# but have it installed... so we do try to uninstall. But if that fails on
# e.g. missing directories and we have no record of installing it - it's fine.
define uninstall_sub
	( $(MKDIR) "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" $(DESTDIR) $(INSTDIR) && \
	  cd "$(BUILD_OBJ_DIR)/$(1)/$(BUILD_SUB_DIR_$(1))" && \
	  case "x$(PREP_TYPE_$(1))" in \
	    xnone)          CCACHE_BASEDIR="$(ORIGIN_SRC_DIR)/$(1)" ;; \
	    xclone*-obj)    CCACHE_BASEDIR="$(BUILD_OBJ_DIR)/$(1)" ;; \
	    xclone*-src|*)  CCACHE_BASEDIR="$(BUILD_SRC_DIR)/$(1)" ;; \
	  esac && \
	  export CCACHE_BASEDIR && \
	  case "x$(1)" in \
	    xgsl) $(RMFILE) $(DESTDIR_$(1))/bin/gsl ;; \
	    *)    $(MAKE) DESTDIR="$(DESTDIR)" $(MAKE_COMMON_ARGS_$(1)) $(MAKE_INSTALL_ARGS_$(1)) \
	            uninstall || { \
	            if test -f "$(BUILD_OBJ_DIR)/$(1)"/.installed || \
	               test -f "$(BUILD_OBJ_DIR)/$(1)"/.install-failed ; then \
	                echo "FAILED to uninstall the previously built component $(1)" >&2 ; false ; \
	            else echo "IGNORE failure to uninstall the component $(1) we did not build yet" >&2 ; true ; fi ; } ;; \
	  esac && \
	  $(RMFILE) "$(BUILD_OBJ_DIR)/$(1)"/.installed "$(BUILD_OBJ_DIR)/$(1)"/.install-failed \
	)
endef

# Wrap uninstall_sub() in a way that should not break "make" even if it failed
# TODO: One problem is we do not calculate reverse-dependencies, to specify in
# which order can submodules be un-installed (recipe needs them configured to
# know which paths to remove, and lack of czmq removed early breaks everyone).
define uninstall_lax_sub
	( $(call uninstall_sub,$(1)) || echo "FAILED TO UNINSTALL $(@D), this can cause [make] Error messages later" >&2 )
endef

# This clones directory $1 into $2 recursively, making real new dirs
# and populating with (relative) symlinks to original data.
# For safety, use absolute paths...
define clone_ln
	( if test x"$(1)" = x"$(2)" ; then exit ; fi && \
	  $(RMDIR) "$(2)" && $(MKDIR) "$(2)" && \
	  SRC="`cd "$(1)" && pwd`" && DST="`cd "$(2)" && pwd`" && \
	  cd "$$SRC" && \
	    $(FIND) . -type d -exec $(MKDIR) "$$DST"/'{}' \; && \
	    $(FIND) . \! -type d \! -type l -exec $(LN_S_R) "$$SRC"/'{}' "$$DST"/'{}' \; && \
	    $(FIND) . -type l -exec $(CP) -P "$$SRC"/'{}' "$$DST"/'{}' \; && \
	  if test -s "$$DST"/configure && test -s "$$DST"/configure.ac ; then \
	    $(RM) "$$DST"/configure; \
	  else true ; fi \
	)
endef

# Some projects (e.g. libmagic) are picky about file types, so symlinks
# would break them. So we support copying as files too.
define clone_tar
	( if test x"$(1)" = x"$(2)" ; then exit ; fi && \
	  $(RMDIR) "$(2)" && $(MKDIR) "$(2)" && \
	  SRC="`cd "$(1)" && pwd`" && DST="`cd "$(2)" && pwd`" && \
	  ( cd "$$SRC" && $(GTAR) -c --exclude=.git -f - ./ ) | \
	    ( cd "$$DST" && $(GTAR) xf - ) \
	)
endef

# Update existing clone, using newer files from source dir
# Assumes GNU cp or compatible
define clone_cp_update
	( if test x"$(1)" = x"$(2)" ; then exit ; fi && \
	  $(MKDIR) "$(2)" && \
	  SRC="`cd "$(1)" && pwd`" && DST="`cd "$(2)" && pwd`" && \
	  if test -h "$$DST/.git" ; then $(RM) "$$DST/.git" ; fi && \
	  ( cd "$$SRC" && $(CP) -Ppurd ./ "$$DST"/ ) \
	)
endef

# Reports a no-op for certain recipes
define echo_noop
	( echo "  NOOP    Generally recipe for $@ has nothing to do" ; $(TOUCH) $@ )
endef

define echo_noop_pkg
	( echo "  NOOP    Generally recipe for $@ has nothing to do because dependency is used pre-packaged" ; $(MKDIR) $(@D); $(TOUCH) $@ )
endef

# Helper for "make .autodeps" using a fake project.xml in CMake-only components
define fake_projectxml
	( \
	if [ ! -s "$(1)/CMakeLists.txt" ]; then echo "FATAL: No '$(1)/CMakeLists.txt' was found" >&2 ; exit 1; fi; \
	printf '<project name="$(1)">\n' > "$(1)/project-fake.xml" ; \
	grep -w find_package "$(1)/CMakeLists.txt" \
	    | sed 's,^.*find_package[ \t]*([ \t]*\([a-zA-Z0-9_-]*\)[^a-zA-Z0-9_-].*$$,\1,' \
	    | ( while read P ; do case "$$P" in \
	    "") ;; Doxygen) ;; \
	    *find_package*) echo "WARNING: Could not parse CMake dependency line, got: $$P" >&2 ;; \
	    *) if [ -d "$(ORIGIN_SRC_DIR)/$$P" ]; then printf '    <use project="$$P" />\n' ; \
	        else echo "WARNING: CMake dependency '$$P' is not in local workspace under '$(ORIGIN_SRC_DIR)'" >&2 ; \
	       fi ;; \
	esac ; done ; echo '</project>' ) >> "$(1)/project-fake.xml" ; \
	ln -sf "./project-fake.xml" "$(1)/project.xml" ; \
	)
endef

# TODO: Find a way to populate this list from FTY_COMPONENTS*
# automatically, via some shell magic
# NOTE: Catch2 is not really a CMake dependency, but our new
# components generally need it for unit tests. And CMake too.
COMPONENTS_CMAKE_ONLY =
define ADD_CMAKE_ONLY
$(eval COMPONENTS_CMAKE_ONLY += $(1) )
$(eval MAKE_CHECK_TARGET_$(1) ?= test )
$(eval MAKE_DIST_TARGET_$(1) ?= package_source )

$(BUILD_OBJ_DIR)/$(1)/.configured: $(BUILD_OBJ_DIR)/Catch2/.installed

$(1)/project.xml: $(1)/CMakeLists.txt
	@echo "GENERATE FAKE $$@ from $$< for autodeps listing"
	@$$(call fake_projectxml,$(1))

endef


CFLAGS ?=
CPPFLAGS ?=
CXXFLAGS ?=
LDFLAGS ?=

CFLAGS += -I$(DESTDIR)$(PREFIX)/include
CPPFLAGS += -I$(DESTDIR)$(PREFIX)/include
CXXFLAGS += -I$(DESTDIR)$(PREFIX)/include
LDFLAGS += -L$(DESTDIR)$(PREFIX)/lib

PKG_CONFIG_DIR ?= $(DESTDIR)$(PREFIX)/lib/pkgconfig
PKG_CONFIG_PATH ?= $(PKG_CONFIG_DIR):/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/pkgconfig:/lib/pkgconfig
export PKG_CONFIG_PATH

CONFIG_OPTS  = --prefix="$(PREFIX)"
CONFIG_OPTS += --sysconfdir="$(DESTDIR)$(PREFIX_ETCDIR)"
CONFIG_OPTS += LDFLAGS="$(LDFLAGS)"
CONFIG_OPTS += CFLAGS="$(CFLAGS)"
CONFIG_OPTS += CXXFLAGS="$(CXXFLAGS)"
CONFIG_OPTS += CPPFLAGS="$(CPPFLAGS)"
CONFIG_OPTS += PKG_CONFIG_PATH="$(PKG_CONFIG_PATH)"
CONFIG_OPTS += --with-pkgconfdir="$(PKG_CONFIG_DIR)"
CONFIG_OPTS += --with-docs=no --without-docs
CONFIG_OPTS += --with-doc=no --without-doc
CONFIG_OPTS += --with-systemd-units=yes
CONFIG_OPTS += --with-systemdtmpfilesdir="$(DESTDIR)$(PREFIX)/lib/tmpfiles.d"
CONFIG_OPTS += --with-systemdsystempresetdir="$(DESTDIR)$(PREFIX)/lib/systemd/system-preset"
CONFIG_OPTS += --with-systemdsystemunitdir="$(DESTDIR)$(PREFIX)/lib/systemd/system"
CONFIG_OPTS += --with-systemdshutdowndir="$(DESTDIR)$(PREFIX)/lib/systemd/system-shutdown"
CONFIG_OPTS += --quiet
# For projects from around the zeromq community, use stable APIs by default
ifeq ($(strip $(CZMQ_BUILD_DRAFT_API)),yes)
CONFIG_OPTS += --enable-drafts=yes
else
CONFIG_OPTS += --enable-drafts=no
endif

# The value of "enabled" is shared with zeromq and migh be opted
# out of in some component recipes below.
# The "enforced" setting is not opted out of, reserved for tests
# that might fail but be true (and help debug why that fails).
ifeq ($(strip $(ADDRESS_SANITIZER)),enabled)
CONFIG_OPTS += --enable-address-sanitizer=yes
else
ifeq ($(strip $(ADDRESS_SANITIZER)),enforced)
CONFIG_OPTS += --enable-address-sanitizer=yes
else
endif
endif

# optional overrides of config above, etc.
sinclude Makefile-local.mk
sinclude Makefile-local-$(BUILD_OS).mk
sinclude Makefile-local-$(BUILD_OS)-$(BUILD_ARCH).mk

# Catch empty expansions
$(BUILD_OBJ_DIR)//.prep-newestfetch $(BUILD_OBJ_DIR)//.prep-builtgitindex $(BUILD_OBJ_DIR)//.prep-builtcommit $(BUILD_OBJ_DIR)//.prepped $(BUILD_OBJ_DIR)//.autogened $(BUILD_OBJ_DIR)//.configured $(BUILD_OBJ_DIR)//.built $(BUILD_OBJ_DIR)//.installed $(BUILD_OBJ_DIR)//.checked $(BUILD_OBJ_DIR)//.checked-verbose $(BUILD_OBJ_DIR)//.distchecked $(BUILD_OBJ_DIR)//.disted $(BUILD_OBJ_DIR)//.memchecked:
	@echo "Error in recipe expansion, can not build $@ : component part is empty" ; exit 1

########################### GSL and LIBCIDR ###############################
# This is built in-tree, and without autoconf, so is trickier to handle
COMPONENTS_ALL += gsl
#BUILD_SUB_DIR_gsl=src/
PREFIX_gsl=$(PREFIX)/local
ifeq ($strip $(MAKE_COMMON_ARGS_gsl),)
MAKE_COMMON_ARGS_gsl=DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX_gsl)"
else
MAKE_COMMON_ARGS_gsl+=DESTDIR="$(DESTDIR)" PREFIX="$(PREFIX_gsl)"
endif
PREP_TYPE_gsl = cloneln-obj

# These are no-ops for GSL:
$(BUILD_OBJ_DIR)/gsl/.autogened: $(BUILD_OBJ_DIR)/gsl/.prepped
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/gsl/.configured: $(BUILD_OBJ_DIR)/gsl/.autogened
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/gsl/.checked $(BUILD_OBJ_DIR)/gsl/.checked-verbose $(BUILD_OBJ_DIR)/gsl/.distchecked $(BUILD_OBJ_DIR)/gsl/.memchecked $(BUILD_OBJ_DIR)/gsl/.disted: $(BUILD_OBJ_DIR)/gsl/.built
	@$(call echo_noop,$@)

#$(BUILD_OBJ_DIR)/gsl/.built: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)
#$(BUILD_OBJ_DIR)/gsl/.installed: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)


### Rinse and repeat for libcidr, but there's less to customize
COMPONENTS_FTY += libcidr
# With the weird build system that libcidr uses, we'd better hide from it
# that it is in a sub-make - or it goes crazy trying to communicate back
MAKE_COMMON_ARGS_libcidr ?= MAKELEVEL="" MAKEFLAGS="" -j1
PREP_TYPE_libcidr = cloneln-obj

$(BUILD_OBJ_DIR)/libcidr/.autogened: $(BUILD_OBJ_DIR)/libcidr/.prepped
	@$(call echo_noop,$@)

#$(BUILD_OBJ_DIR)/libcidr/.built: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)
#$(BUILD_OBJ_DIR)/libcidr/.installed: BUILD_SRC_DIR=$(BUILD_OBJ_DIR)

$(BUILD_OBJ_DIR)/libcidr/.checked $(BUILD_OBJ_DIR)/libcidr/.checked-verbose $(BUILD_OBJ_DIR)/libcidr/.distchecked $(BUILD_OBJ_DIR)/libcidr/.memchecked $(BUILD_OBJ_DIR)/libcidr/.disted: $(BUILD_OBJ_DIR)/libcidr/.built
	@$(call echo_noop,$@)

# Note: Catch2 goes with capital "C":
COMPONENTS_ALL += Catch2
CONFIG_OPTS_Catch2 ?= -DBUILD_TESTING=OFF
#PREP_TYPE_Catch2 = cloneln-obj

#$(BUILD_OBJ_DIR)/Catch2/.autogened: $(BUILD_OBJ_DIR)/Catch2/.prepped
#	@$(call echo_noop,$@)

# cmake -Bbuild -H. -DBUILD_TESTING=OFF
# sudo cmake --build build/ --target install

######################## Other components ##################################
# Note: for rebuilds with a ccache in place, the biggest time-consumers are
# recreation of configure script (autogen or autoreconf) and running it.
# Documentation processing can also take a while, but it is off by default.
# So to take advantage of parallelization we define dependencies from the
# earliest stage a build pipeline might have.

COMPONENTS_ALL += zproto
$(BUILD_OBJ_DIR)/zproto/.configured: $(BUILD_OBJ_DIR)/gsl/.installed

$(BUILD_OBJ_DIR)/zproto/.memchecked: $(BUILD_OBJ_DIR)/zproto/.built
	@$(call echo_noop,$@)

COMPONENTS_ALL += zproject
$(BUILD_OBJ_DIR)/zproject/.autogened: $(BUILD_OBJ_DIR)/gsl/.installed

$(BUILD_OBJ_DIR)/zproject/.checked $(BUILD_OBJ_DIR)/zproject/.checked-verbose $(BUILD_OBJ_DIR)/zproject/.disted $(BUILD_OBJ_DIR)/zproject/.distchecked $(BUILD_OBJ_DIR)/zproject/.memchecked: $(BUILD_OBJ_DIR)/zproject/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += cxxtools
MAKE_COMMON_ARGS_cxxtools=-j1
PREP_TYPE_cxxtools = cloneln-obj

$(BUILD_OBJ_DIR)/cxxtools/.memchecked: $(BUILD_OBJ_DIR)/cxxtools/.built
	@$(call echo_noop,$@)

# This requires dev packages (or equivalent) of mysql/mariadb
# Make sure the workspace is (based on) branch "1.3"
COMPONENTS_FTY += tntdb
MAKE_COMMON_ARGS_tntdb=-j1
BUILD_SUB_DIR_tntdb=tntdb/
CONFIG_OPTS_tntdb ?=
CONFIG_OPTS_tntdb += --without-postgresql
CONFIG_OPTS_tntdb += --without-sqlite
$(BUILD_OBJ_DIR)/tntdb/.configured: $(BUILD_OBJ_DIR)/cxxtools/.installed
$(BUILD_OBJ_DIR)/tntdb/.memchecked: $(BUILD_OBJ_DIR)/tntdb/.built
	@$(call echo_noop,$@)

### We do not link to this(???) - just use at runtime
# Make sure the workspace is (based on) branch "2.2"
COMPONENTS_FTY += tntnet
CONFIG_OPTS_tntnet ?=
CONFIG_OPTS_tntnet += --with-sdk
CONFIG_OPTS_tntnet += --without-demos
$(BUILD_OBJ_DIR)/tntnet/.configured: $(BUILD_OBJ_DIR)/cxxtools/.installed
$(BUILD_OBJ_DIR)/tntnet/.memchecked: $(BUILD_OBJ_DIR)/tntnet/.built
	@$(call echo_noop,$@)

COMPONENTS_FTY += libmagic
PREP_TYPE_libmagic = clonetar-src
$(BUILD_OBJ_DIR)/libmagic/.memchecked: $(BUILD_OBJ_DIR)/libmagic/.built
	@$(call echo_noop,$@)


ifeq ($(strip $(CI_CZMQ_VER)),pkg)
#    COMPONENTS_FTY += libsodium
#    COMPONENTS_FTY += libzmq
#    COMPONENTS_FTY += czmq
#    COMPONENTS_FTY += malamute

    # In case of "pkg" which stands for using the upstream packages we
    # have nothing to build - the env (e.g. Travis) should provide them
    # pre-installed in system areas. If they mismatch our expectations,
    # this means the env is obsolete... or too far in the future ;)

COMPONENT_LIBSODIUM=libsodium
COMPONENT_CZMQ=czmq
COMPONENT_LIBZMQ=libzmq
COMPONENT_MLM=malamute

$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prep-newestfetch $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prep-builtgitindex $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prep-builtcommit $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.autogened $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.configured \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.built $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.installed \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.distchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.disted $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.memchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prep-newestfetch $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prep-builtgitindex $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prep-builtcommit $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.autogened $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.configured \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.built $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.installed \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.distchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.disted $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.memchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prep-newestfetch $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prep-builtgitindex $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prep-builtcommit $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.autogened $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.configured \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.built $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.installed \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.distchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.disted $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.memchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prep-newestfetch $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prep-builtgitindex $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prep-builtcommit $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.prepped \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.autogened $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.configured \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.built $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.installed \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.distchecked \
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.disted $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.memchecked :
	@$(call echo_noop_pkg,$@)

else
    # CI_CZMQ_VER not specified, or "3" (or "4" quietly)

ifeq ($(strip $(CI_CZMQ_VER)),3)

    COMPONENT_LIBSODIUM=libsodium-v1.0.5

    COMPONENT_CZMQ=czmq-v3.0.2

    CONFIG_OPTS_$(COMPONENT_CZMQ) ?= CFLAGS="$(CFLAGS) -Wno-deprecated-declarations" CXXFLAGS="$(CXXFLAGS) -Wno-deprecated-declarations" CPPFLAGS="$(CPPFLAGS) -Wno-deprecated-declarations"

# Make sure the workspace is (based on) branch "v3.0.2" at this time
# That version of czmq autogen.sh requires a "libtool" while debian has
# only "libtoolize", so fall back if needed.
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.autogened: $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.prepped
	+$(call autogen_sub,$(notdir $(@D))) || \
	 ( cd "$(BUILD_SRC_DIR)/$(notdir $(@D))/$(BUILD_SUB_DIR_$(notdir $(@D)))" \
	   && autoreconf -fiv )
	$(TOUCH) $@

# Note: czmq3 seems to fail *check, disable it for now
# FYI: hangs in zauth tests, e.g.
#   ^C czmq_selftest: ../../src/zauth_v2.c:733: zauth_v2_test: Assertion `success' failed.
$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.distchecked $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.memchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.built
	@$(call echo_noop,$@)

    COMPONENT_LIBZMQ=libzmq-v4.2.0

    COMPONENT_MLM=malamute-v1.0
#    COMPONENT_MLM=malamute

$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.memchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.built
	@$(call echo_noop,$@)

# NOTE: Something must have broken recently...
#   lt-mlm_selftest: ../../../.srcclone/Linux-x86_64-czmq_3/malamute-v1.0/src/mlm_client.c:443: mlm_stream_api_test: Assertion `rc == 0' failed.
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.checked $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.distchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.built
	@$(call echo_noop,$@)

else
    # Note: this currently assumes that "CI_CZMQ_VER=4" means upstream/master of the whole stack
    COMPONENT_LIBSODIUM=libsodium-master

    COMPONENT_CZMQ=czmq-master

    COMPONENT_LIBZMQ=libzmq-master

    COMPONENT_MLM=malamute-master

endif

    COMPONENTS_FTY += $(COMPONENT_LIBSODIUM)
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.memchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.built
	@$(call echo_noop,$@)

    COMPONENTS_FTY += $(COMPONENT_LIBZMQ)
    PREP_TYPE_$(COMPONENT_LIBZMQ) = clonetar-src
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.configured: \
    $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.installed
# TODO: It was called "make check-valgrind-memcheck" back then
$(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.memchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.built
	@$(call echo_noop,$@)

# There is something fishy at this time when running code against libzmq.so
# built with ASAN (unresolved symbols are reported).
CONFIG_OPTS_$(COMPONENT_LIBZMQ) ?=
ifeq ($(strip $(ADDRESS_SANITIZER)),enabled)
CONFIG_OPTS_$(COMPONENT_LIBZMQ) += --enable-address-sanitizer=no
endif

    COMPONENTS_FTY += $(COMPONENT_CZMQ)
    PREP_TYPE_$(COMPONENT_CZMQ) = cloneln-src

# There is something fishy at this time when running code against libczmq.so
# built with ASAN (unresolved symbols are reported).
CONFIG_OPTS_libczmq ?=
ifeq ($(strip $(ADDRESS_SANITIZER)),enabled)
CONFIG_OPTS_libczmq += --enable-address-sanitizer=no
endif

$(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.configured: \
    $(BUILD_OBJ_DIR)/$(COMPONENT_LIBZMQ)/.installed

ifneq ($strip($(COMPONENT_CZMQ)),czmq)
    PREP_TYPE_czmq = $(PREP_TYPE_$(COMPONENT_CZMQ))

# Compatibility aliases

devel/czmq build/czmq rebuild/czmq prep/czmq configure/czmq autogen/czmq uninstall/czmq install/czmq check/czmq memcheck/czmq distcheck/czmq distclean/czmq dist/czmq:
	@$(MAKE) $(@D)/$(COMPONENT_CZMQ)

#%/czmq: $(ORIGIN_SRC_DIR)/$(COMPONENT_CZMQ)
#	$(MAKE) $(@D)/$(COMPONENT_CZMQ)

#$(BUILD_OBJ_DIR)/czmq/%: $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/%

#$(BUILD_OBJ_DIR)/czmq/*: $(COMPONENT_CZMQ)/
#	$(MAKE) $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/$(@F)
#	@true

endif
# ENDIF czmq is not verbatim "czmq"

    COMPONENTS_FTY += $(COMPONENT_MLM)
$(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.configured: \
    $(BUILD_OBJ_DIR)/$(COMPONENT_CZMQ)/.installed \
    $(BUILD_OBJ_DIR)/$(COMPONENT_LIBSODIUM)/.installed

endif

COMPONENT_LOG4CPLUS = log4cplus-v1.1.2
COMPONENTS_FTY += $(COMPONENT_LOG4CPLUS)
$(BUILD_OBJ_DIR)/$(COMPONENT_LOG4CPLUS)/.memchecked: $(BUILD_OBJ_DIR)/$(COMPONENT_LOG4CPLUS)/.built
	@$(call echo_noop,$@)

# Our fork of Google protobuf with constrained OBS recipe to build just
# the C/C++ libraries package and protoc tool... and some auto_ptr fixes.
COMPONENTS_FTY += protobuf
#CONFIG_OPTS_protobuf ?=
#CONFIG_OPTS_protobuf += ...

COMPONENTS_FTY += nut
CONFIG_OPTS_nut ?=
CONFIG_OPTS_nut += --with-doc=skip
CONFIG_OPTS_nut += --with-dev
CONFIG_OPTS_nut += --with-neon
CONFIG_OPTS_nut += --with-snmp
CONFIG_OPTS_nut += --with-dmf
CONFIG_OPTS_nut += --with-libltdl
CONFIG_OPTS_nut += --with-augeas-lenses-dir="$(DESTDIR)$(PREFIX)/share/augeas/lenses/dist"
#CONFIG_OPTS_nut += --sysconfdir="$(DESTDIR)$(PREFIX_ETCDIR)/nut"
CONFIG_OPTS_nut += --with-udev-dir="$(DESTDIR)$(PREFIX_ETCDIR)/udev"
CONFIG_OPTS_nut += --with-devd-dir="$(DESTDIR)$(PREFIX_ETCDIR)/devd"
CONFIG_OPTS_nut += --with-hotplug-dir="$(DESTDIR)$(PREFIX_ETCDIR)/hotplug"

# Note: more and more core is a collection of scripts, so should need less deps
# Also note it is not zproject'ized so we list them here
COMPONENTS_FTY += fty-core
PREP_TYPE_fty-core = clonetar-src
$(BUILD_OBJ_DIR)/fty-core/.configured: \
    $(BUILD_OBJ_DIR)/$(COMPONENT_MLM)/.installed \
    $(BUILD_OBJ_DIR)/tntdb/.installed \
    $(BUILD_OBJ_DIR)/tntnet/.installed \
    $(BUILD_OBJ_DIR)/libcidr/.installed
$(BUILD_OBJ_DIR)/fty-core/.memchecked: $(BUILD_OBJ_DIR)/fty-core/.built
	@$(call echo_noop,$@)

$(BUILD_OBJ_DIR)/fty-core/.configured: $(BUILD_OBJ_DIR)/fty-core/.git $(BUILD_SRC_DIR)/fty-core/.git

$(BUILD_OBJ_DIR)/fty-core/.git: $(BUILD_OBJ_DIR)/fty-core/.prepped $(BUILD_OBJ_DIR)/.git
	$(LN_S_R) $(ORIGIN_SRC_DIR)/fty-core/.git $(BUILD_OBJ_DIR)/fty-core/

$(BUILD_SRC_DIR)/fty-core/.git: $(BUILD_OBJ_DIR)/fty-core/.prepped $(BUILD_SRC_DIR)/.git
	$(LN_S_R) $(ORIGIN_SRC_DIR)/fty-core/.git $(BUILD_SRC_DIR)/fty-core/

### 3rd party bit
COMPONENTS_FTY += spdlog

# Note: over early 2018, the old big fty-rest is breaking up into smaller,
# better reusable components. Much of the shareable payload goes into the
# fty-common project and a number of thematic components, to be linked as
# a shared library for the benefit of other REST API implementations and
# other components. The new fty-rest will then be one of such consumers.

COMPONENTS_FTY += fty-common-logging

COMPONENTS_FTY += fty-common

COMPONENTS_FTY += fty-common-mlm

COMPONENTS_FTY += fty-common-db

COMPONENTS_FTY += fty-common-rest

# Used for trusted direct Unix-socket communications
# between secured components running on same host
COMPONENTS_FTY += fty-common-socket

COMPONENTS_FTY += fty-common-messagebus

COMPONENTS_FTY += fty-common-messagebus2

COMPONENTS_FTY += fty-common-dto

COMPONENTS_FTY += fty-proto

# Beside MQ, much data is now published via SHM FS more quickly
COMPONENTS_FTY += fty-shm

# Library to report service health, and one of implementation plugins
COMPONENTS_FTY_EXPERIMENTAL += fty-service-status
COMPONENTS_FTY_EXPERIMENTAL += fty-service-status-systemd

COMPONENTS_FTY += fty-rest
PREP_TYPE_fty-rest = clonetar-src
# Note: This definition of dependencies is added to below
$(BUILD_OBJ_DIR)/fty-rest/.configured: $(BUILD_OBJ_DIR)/fty-rest/.git $(BUILD_SRC_DIR)/fty-rest/.git

$(BUILD_OBJ_DIR)/fty-rest/.git: $(BUILD_OBJ_DIR)/fty-rest/.prepped $(BUILD_OBJ_DIR)/.git
	$(LN_S_R) $(ORIGIN_SRC_DIR)/fty-rest/.git $(BUILD_OBJ_DIR)/fty-rest/

$(BUILD_SRC_DIR)/fty-rest/.git: $(BUILD_OBJ_DIR)/fty-rest/.prepped $(BUILD_SRC_DIR)/.git
	$(LN_S_R) $(ORIGIN_SRC_DIR)/fty-rest/.git $(BUILD_SRC_DIR)/fty-rest/

$(BUILD_OBJ_DIR)/.git $(BUILD_SRC_DIR)/.git: $(ORIGIN_SRC_DIR)/.git
	$(MKDIR) $(@D)
	$(LN_S_R) $< $@

# No -llsan on Travis
CONFIG_OPTS_fty-rest ?=
ifneq ($(strip $(BUILD_TYPE)),)
CONFIG_OPTS_fty-rest += --enable-leak-sanitizer=no
endif

# For now the fty-rest memchecked target program is unreliable at best, and
# documented so in the component's Makefile. So we do not call it for now.
# TODO: Make it somehow an experimental-build toggle?
$(BUILD_OBJ_DIR)/fty-rest/.memchecked: $(BUILD_OBJ_DIR)/fty-rest/.built
	@$(call echo_noop,$@)

# Note: the "web-test" and "web-test-bios" recipes run "tntnet"
# from PATH which should prioritize our build-product
web-test web-test-deps: $(BUILD_OBJ_DIR)/fty-rest/.built
	cd $(<D) && $(MAKE) $@

# The web-test-bios recipe and its contributing steps defined below
# require special configuration on developer's workstation, allowing
# the "sudo" and preparing the database schema, credentials, configs etc.
# It is intended to run in copies of the "fty-devel" image otherwise
# configured and ready to run the production code.
# Requiring the config file is one way to lock this recipe from running
# on arbitrary unprepared environments (especially with root privileges).
# And also we do need it to match the freshly-built server with OS setup.
# TODO: Support some merge of data from these files, to use new tntnet.xml
# configurations for developed servlets, etc.

$(BUILD_OBJ_DIR)/fty-rest/tntnet.xml: web-test-deps
	@true

# We depend on built tntnet.xml to ensure presence of a recent build of
# fty-rest right now, and to maybe use that file's contents later.
TNTNET_BIOS_XML =	/etc/tntnet/bios.xml
TNTNET_BIOS_UNIT =	/etc/systemd/system/bios.target.wants/tntnet@bios.service
TNTNET_BIOS_ENV =	/run/tntnet-bios.env
FTY_COMMON_ENV =	/run/fty-envvars.env

# Note: our custom configuration should still refer to system-provided
# (or product bundled) and FTY "install" paths for REST API bits that
# are implemented by other components: we do not have just one servlet
# shared object anymore. We just prefer our build to be used first.
$(BUILD_OBJ_DIR)/fty-rest/bios.xml: $(BUILD_OBJ_DIR)/fty-rest/.built $(BUILD_OBJ_DIR)/fty-rest/tntnet.xml $(TNTNET_BIOS_XML)
	@echo "CUSTOMIZING tntnet configuration from system-provided bios.xml..." >&2 && \
	 $(RM) "$@" "$@.tmp" && \
	 cd $(<D) && \
	    $(SED) -e 's|^\(.*<compPath>\)\(.*\)$$|\1\n<entry>$(BUILD_OBJ_DIR)/fty-rest/src/.libs</entry>\n<entry>$(BUILD_OBJ_DIR)/fty-rest/.libs</entry>\n<entry>$(DESTDIR)$(PREFIX)/lib</entry>\n\2|' \
	        < $(TNTNET_BIOS_XML) > "$@.tmp" && \
	    $(MV) "$@.tmp" "$@"

# Execute always, files referenced from config can change
# Also this recipe tries to use a file that might not always be present
# Note that this "make" recipe runs unprivileged and might not see all files,
# so it relies on "sudo" allowing ALL (or enough) actions to "cat" them.
$(BUILD_OBJ_DIR)/fty-rest/bios.env: $(TNTNET_BIOS_UNIT) FORCE
	@echo "STASHING aside some ennvars that configure systemd service tntnet@bios..." >&2 && \
	    $(RM) "$@" "$@.tmp" && touch "$@.tmp" && \
	    { if test -s $(TNTNET_BIOS_UNIT) ; then \
	        while read LINE ; do case "$$LINE" in EnvironmentFile=*) \
	            F="`echo "$$LINE" | $(SED) -s 's,^EnvironmentFile=\-*,,'`" && [ -n "$$F" ] && \
	            echo "### $$F" && sudo grep = "$$F" || true ;; \
	        esac; done < $(TNTNET_BIOS_UNIT) ; \
	      fi; } >> "$@.tmp" && \
	    { if test -s $(TNTNET_BIOS_ENV) ; then \
	        echo "### $(TNTNET_BIOS_ENV)" && sudo grep = $(TNTNET_BIOS_ENV) ; \
	      fi; } >> "$@.tmp" && \
	    { if test -s $(FTY_COMMON_ENV) ; then \
	        echo "### $(FTY_COMMON_ENV)" && sudo grep = $(FTY_COMMON_ENV) ; \
	      fi; } >> "$@.tmp" && \
	    echo 'PATH="$(PATH)"' >> "$@.tmp" && \
	    $(MV) "$@.tmp" "$@"

# Make sure the web-server user can "sudo" to scripts it wants, perhaps in
# the private directory.
# TODO: Rather than allowing ALL, adapt the
#     $(BUILD_OBJ_DIR)/fty-core/docs/examples/sudoers.d/fty_00_base
#   but take care to rename the CMDNAME macros inside, and the file.
$(BUILD_OBJ_DIR)/fty-rest/90make-web-test-bios-sudoers: $(BUILD_OBJ_DIR)/fty-rest/bios.xml  $(BUILD_OBJ_DIR)/fty-core/.installed
	@U="`grep '<user>' "$<" | head -1 | grep -v '<!--' | sed 's,^.*>\([^\<\>\t ]*\)<.*$$,\1,'`" ; \
	 if [ -n "$$U" ] ; then \
	    echo "$$U   ALL=(ALL:ALL) NOPASSWD: ALL" ; \
	 fi > "$@"

# Rule out builds done as root, with shared libs for tntnet servlets placed
# in locations not accessible to runtime account. Note this still requires
# that the current user (running the build) may elevate to do anything here.
web-test-bios-rights: $(BUILD_OBJ_DIR)/fty-rest/bios.xml
	@WWW_USER="`grep '<user>' "$<" | sed 's,^[\t ]*<user>\([^\<]*\)<\/.*,\1,' | egrep -v '^$$' | head -1`" || WWW_USER="" ; \
	 if test -n "$$WWW_USER" ; then \
	    sudo sudo -u "$$WWW_USER" ls -la $< >/dev/null && \
	    if test -d $(DESTDIR)$(PREFIX)/lib/ ; then sudo sudo -u "$$WWW_USER" ls -la $(DESTDIR)$(PREFIX)/lib/ >/dev/null && exit 0 ; else exit 0; fi; \
	    echo "FAILED: The web-server run-time account '$$WWW_USER' determined from $< FAILED sanity check $@ : this account can not access locations with files from this tested build" >&2 ; \
	 else \
	    echo "WARNING: Could not determine web-server run-time account from $<, SKIPPED sanity check $@" >&2 ; \
	 fi

web-test-bios-deps: $(BUILD_OBJ_DIR)/fty-rest/.installed web-test-deps $(BUILD_OBJ_DIR)/fty-rest/bios.xml $(BUILD_OBJ_DIR)/fty-rest/bios.env $(BUILD_OBJ_DIR)/fty-rest/90make-web-test-bios-sudoers web-test-bios-rights
	@true

HELP_BASETGT += "    web-test-bios-deps	Create files needed for development web-test"
HELP_BASETGT += "    web-test-bios	Run a development web-test by starting tntnet" \
                "        with as similar settings as possible for current system's" \
                "        BIOS env and using a freshly compiled fty-rest library"

web-test-bios: web-test-bios-deps
	@cd $(<D) && \
	    echo "TRYING TO STOP tntnet@bios systemd service to avoid conflicts..." >&2 && \
	    { sudo systemctl stop tntnet@bios.service || echo "FAILED TO STOP tntnet@bios systemd service, maybe it is already down?" >&2 ; } && \
	    if ! test -e /var/lib/bios/license && ! test -e /var/lib/fty/license && \
	       ! test -e /var/lib/fty/fty-eula/license ; then \
	        echo "WARNING: Starting $@ while the FTY license is not accepted yet" >&2 ; \
	    fi && \
	    if ! test -e /var/run/fty-db-ready ; then \
	        echo "WARNING: Starting $@ while the FTY database is not in a known-ready state" >&2 ; \
	    fi && \
	    echo "STARTING custom tntnet daemon with custom fty-rest and adapted system bios.xml..." >&2 && \
	    sudo /bin/sh -c "\
	    cp $(BUILD_OBJ_DIR)/fty-rest/90make-web-test-bios-sudoers /etc/sudoers.d && \
	    chown 0:0 /etc/sudoers.d/90make-web-test-bios-sudoers && \
	    chmod 644 /etc/sudoers.d/90make-web-test-bios-sudoers && \
	    { if test -s $(BUILD_OBJ_DIR)/fty-rest/bios.env ; then \
	        echo 'READING envvars that configure systemd service tntnet@bios...' >&2 && \
	        . $(BUILD_OBJ_DIR)/fty-rest/bios.env && \
	        while IFS='=' read K V ; do case \"\$$K\" in \#*) ;; *) echo \"===== export \$$K = \$$V\" >&2; \
	            eval export \$$K ; esac; \
	        done < $(BUILD_OBJ_DIR)/fty-rest/bios.env || exit ; \
	       fi; } && tntnet $(BUILD_OBJ_DIR)/fty-rest/bios.xml"

### TODO: As work on fty-common-* repos is completed, revise carefully which
### components need which dependencies. While fty-common-logging is likely
### to be needed everywhere, some others would need -mlm or -db or the plain
### fty-common, and some would not. Reasonably all directly used dependencies
### should be in project.xml top-level <use> tags.
COMPONENTS_FTY += fty-warranty

COMPONENTS_FTY += fty-nut

COMPONENTS_FTY += fty-asset

COMPONENTS_FTY += fty-asset-rest

COMPONENTS_FTY += fty-alert-stats

COMPONENTS_FTY += fty-metric-tpower

COMPONENTS_FTY += fty-metric-store

COMPONENTS_FTY += fty-metric-composite

COMPONENTS_FTY += fty-email

COMPONENTS_FTY += fty-alert-engine

COMPONENTS_FTY += fty-alert-list

COMPONENTS_FTY += fty-kpi-power-uptime

COMPONENTS_FTY += fty-metric-ambient-location

COMPONENTS_FTY += fty-metric-compute

COMPONENTS_FTY += fty-outage

COMPONENTS_FTY += fty-sensor-env

COMPONENTS_FTY += fty-example

COMPONENTS_FTY += fty-alert-flexible

COMPONENTS_FTY += fty-info

COMPONENTS_FTY += fty-mdns-sd

COMPONENTS_FTY += fty-discovery

COMPONENTS_FTY += fty-sensor-gpio

COMPONENTS_FTY += fty-common-translation

COMPONENTS_FTY += fty-scripts-rest

COMPONENTS_FTY += fty-security-wallet

COMPONENTS_FTY += fty-security-wallet-rest

COMPONENTS_FTY += fty-asset-mapping-rest

COMPONENTS_FTY += fty-common-nut

COMPONENTS_FTY += fty-asset-activator

COMPONENTS_FTY += fty-lib-certificate

COMPONENTS_FTY += fty-config

COMPONENTS_FTY += fty-certificate-generator

COMPONENTS_FTY += fty-certificate-generator-rest

COMPONENTS_FTY += fty-srr

COMPONENTS_FTY += fty-srr-rest

### Note: The following components are experimental recent additions,
### and in their current state they break FTY builds (and they do not
### yet do anything useful). So while this Makefile supports a basic
### config for them, it does not count them as part of the team yet.
### Not built by default... but if we do - it's covered
COMPONENTS_FTY_EXPERIMENTAL += fty-metric-snmp

### TODO: does this need prometheus? what dependency pkgs is it in?
COMPONENTS_FTY_EXPERIMENTAL += fty-prometheus-rest

### Heading to obsoletion; now fty-metric-ambient-location
### is becoming part of replacement for fty-metric-cache
COMPONENTS_FTY_EXPERIMENTAL += fty-metric-cache

# Not yet buildable
#COMPONENTS_FTY_EXPERIMENTAL += fty-protoc
### TODO: Make way to parse CMakeLists.txt :: find_package() to pick dependencies
$(BUILD_OBJ_DIR)/fty-protoc/.configured: \
    $(BUILD_OBJ_DIR)/protobuf/.installed

#$(BUILD_OBJ_DIR)/fty-protoc/.configured: \
#    $(BUILD_OBJ_DIR)/raven-cmake/.installed

# Not in systems as old as Debian 8...
#COMPONENTS_FTY_EXPERIMENTAL += raven-cmake

# Quiesce sanity-checker in sync-repos.sh
# COMPONENTS_NOBUILD += JSON.sh
# COMPONENTS_NOBUILD += fty-lib-jenkins
# COMPONENTS_NOBUILD += fty-template
# COMPONENTS_NOBUILD += fty-template-rest

#COMPONENTS_FTY_EXPERIMENTAL += fty-alert-srr
#COMPONENTS_FTY_EXPERIMENTAL += fty-discovery-ng

#COMPONENTS_FTY_EXPERIMENTAL += dlopen-test
#COMPONENTS_FTY_EXPERIMENTAL += fty-automatic-group

#COMPONENTS_FTY_EXPERIMENTAL += fty-cmake
#COMPONENTS_FTY_EXPERIMENTAL += fty-cmake-rest
#COMPONENTS_FTY_EXPERIMENTAL += fty-cmake-example
#COMPONENTS_FTY_EXPERIMENTAL += fty-pack
#COMPONENTS_FTY_EXPERIMENTAL += fty-utils

### Maybe this one should later be "built" to deliver the pkgconfig file if needed
# COMPONENTS_NOBUILD += libpam0g-dev-pkgconfig

COMPONENTS_ALL += $(COMPONENTS_FTY)

# TODO: Find a way to automate this further
###  raven-cmake
$(foreach C,fty-service-status fty-service-status-systemd fty-protoc, \
    $(eval $(call ADD_CMAKE_ONLY,$(C))))

# Note that our PATH includes INSTDIR and DESTDIR for built AND installed tools
ifeq ($(AUTODEPS_NOT_REQUIRED), true)
.autodeps.fty-stable .autodeps.fty-experimental:
	@echo "SKIP : $@ is not required for this run"

else

.autodeps.fty-stable: make-FTY-deps.gsl .gitmodules Makefile $(addsuffix /project.xml,$(sort $(filter-out fty-core,$(filter fty-%,$(COMPONENTS_FTY)))))
	@PATH="$(BUILD_OBJ_DIR)/gsl/src:$(PATH)"; export PATH; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "NOTE : No 'gsl' in PATH, so making ours ..." >&2; $(MAKE) AUTODEPS_NOT_REQUIRED=true build/gsl || exit ; fi ; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "FATAL : Can not find executable GSL" >&2 ; exit 1 ; fi ; \
	 rm -f $@ ; \
	 gsl "-script:$<" "-make_depfile_name:$@" "-make_depfile_mode:a" "-dot_depfile_mode:skip" $(filter %.xml,$^)
	@echo "GENERATED $@"

.autodeps.fty-experimental: make-FTY-deps.gsl .gitmodules Makefile $(addsuffix /project.xml,$(sort $(filter fty-%,$(COMPONENTS_FTY_EXPERIMENTAL))))
	@PATH="$(BUILD_OBJ_DIR)/gsl/src:$(PATH)"; export PATH; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "NOTE : No 'gsl' in PATH, so making ours ..." >&2; $(MAKE) AUTODEPS_NOT_REQUIRED=true build/gsl || exit ; fi ; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "FATAL : Can not find executable GSL" >&2 ; exit 1 ; fi ; \
	 rm -f $@ ; \
	 gsl "-script:$<" "-make_depfile_name:$@" "-make_depfile_mode:a" "-dot_depfile_mode:skip" $(filter %.xml,$^)
	@echo "GENERATED $@"

endif

.autodeps: .autodeps.fty-stable .autodeps.fty-experimental

# Make a DOT-format graph of dependencies for imaging
# TODO: Mark the time/branch/commit/...?
42ity-deps.dot: make-FTY-deps.gsl .gitmodules Makefile $(addsuffix /project.xml,$(sort $(filter-out fty-core,$(filter fty-%,$(COMPONENTS_FTY_EXPERIMENTAL) $(COMPONENTS_FTY)))))
	@PATH="$(BUILD_OBJ_DIR)/gsl/src:$(PATH)"; export PATH; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "NOTE : No 'gsl' in PATH, so making ours ..." >&2; $(MAKE) AUTODEPS_NOT_REQUIRED=true build/gsl || exit ; fi ; \
	 if ! ( which gsl 2>/dev/null >/dev/null) ; then echo "FATAL : Can not find executable GSL" >&2 ; exit 1 ; fi ; \
	 rm -f $@ && \
	 echo 'digraph FTY_Dependencies {' > $@ && \
	 gsl "-script:$<" "-dot_depfile_name:$@" "-dot_depfile_mode:a" "-make_depfile_mode:skip" $(filter %.xml,$^) && \
	 echo '}' >> $@
	@echo "GENERATED $@"

dot: 42ity-deps.dot

42ity-deps.svg: 42ity-deps.dot
	dot -Tsvg -o$@ < $<

42ity-deps.pdf: 42ity-deps.dot
	dot -Tpdf -o$@ < $<

svg: 42ity-deps.svg

# Make sure to (re)generate dependency rules before building code
# The generated files are included at the end of this Makefile
$(COMPONENTS_FTY_EXPERIMENTAL) $(COMPONENTS_FTY) : .autodeps

############################# Common route ##################################
# The prep step handles preparation of source directory (unpack, patch etc.)
# At a later stage this cound "git clone" a workspace for host-arch build

# So far prepping is no-op for most of our components
# Note that these rules fire if the git FETCH_HEAD file is "newer"
# (according to filesystem timestamp) than the last .prepped flag-file.
# This does not necessarily mean that rebuild should be done (e.g. the
# stashed build area might be older than a git checkout of the workspace
# with same commit hash), so we verify that the commit-id also differs or
# is missing in the prep flag-file, and only then uninstall the old build,
# if any, and reprep the working area. If the .prepped and FETCH_HEAD file
# contents are the same (and note that FETCH_HEAD is a list of the tracked
# branches' last known HEAD commits - not necessarily just the one current
# branch, though this case is likely on persistent/stashed automated build
# checkouts), try to touch FETCH_HEAD's timestamp back to (older) .prepped
# file so the rule does not cause rebuilds in case you e.g. switched from
# one (built) branch to another and then back again - effectively causing
# no changes to codebase in workspace. Conversely, the rule does not fire
# and none of the recipe logic is executed if the FETCH_HEAD file is
# initially not-newer than the .prepped timestamp.
# Also support optional patching of sources while prepping (e.g. for
# alternate OSes with their non-SCMed tweaks).

# Note: this fetches current info from remotes (in particular to get the
# FETCH_HEAD file), but does not necessarily update the local workspace
# with checked-out sources, nor picks a branch. By default codebase stays
# at the commit-id pointed to by git submodule for each component.
HELP_TOUCHFILES += "    .git/modules/%/FETCH_HEAD .git/modules/%/index %/.git" \
                   "        files in current workspace(s) under ORIGIN_SRC_DIR" \
                   "        that are updated by a git pull with new commits"
$(ORIGIN_SRC_DIR)/.git/modules/%/FETCH_HEAD $(ORIGIN_SRC_DIR)/.git/modules/%/index $(ORIGIN_SRC_DIR)/%/.git:
	@if [ ! -s "$@" ] ; then \
	    echo "FETCHING component '$(notdir $(@D))' from Git"; \
	    git submodule init $(notdir $(@D)) && \
	    git submodule update $(notdir $(@D)) && \
	    ( cd $(ORIGIN_SRC_DIR)/$(notdir $(@D)) && git fetch --all ) ; \
	 fi


# Note use of $< : we change the touch-file if FETCH_HEAD is different,
# otherwise we fix up the timestamp of the git metadata files in $^
HELP_TOUCHFILES += "    %/.prep-newestfetch	Single timestamp file for 'make' to compare" \
                   "        that we have new code fetched since last build"
$(BUILD_OBJ_DIR)/%/.prep-newestfetch: $(ORIGIN_SRC_DIR)/.git/modules/%/FETCH_HEAD $(ORIGIN_SRC_DIR)/.git/modules/%/index
	@$(MKDIR) "$(@D)"
	@if test -s "$@" && test -s "$<" && diff "$@" "$<" >/dev/null 2>&1 ; then \
	    echo "ROLLBACK TIMESTAMP of $< to that of existing $@ because this commit is already prepped" ; \
	    $(TOUCH) -r "$@" $^ || true ; \
	 else \
	    echo "Seems a NEW COMMIT of $(notdir $(@D)) has landed (compared to last build), updating $@" ; \
	    cat "$<" > "$@" ; \
	 fi


# Note: second layer of insulation for git metadata vs make touch-files
HELP_TOUCHFILES += "    %/.prep-builtgitindex	Second layer of touch-files for 'make'" \
                   "        to compare that we have built latest checked-out code or not"
$(BUILD_OBJ_DIR)/%/.prep-builtgitindex: $(BUILD_OBJ_DIR)/%/.prep-newestfetch
	@$(MKDIR) "$(@D)"
	@if test -s "$@" && test -s "$<" && diff "$@" "$<" >/dev/null 2>&1 ; then \
	    echo "ROLLBACK TIMESTAMP of $< to that of existing $@ because this commit is already prepped" ; \
	    $(TOUCH) -r "$@" "$<" || true ; \
	 else \
	    echo "Seems a NEW COMMIT of $(notdir $(@D)) has landed (compared to last build), updating $@" ; \
	    cat "$<" > "$@" ; \
	 fi


# Make sure to both run after the .git directory is available,
# and to force evaluation of this recipe every time
HELP_TOUCHFILES += "    %/.prep-builtcommit	Single timestamp+content file for 'make' to" \
                   "        verify that we have last built this particular commit or not"
$(BUILD_OBJ_DIR)/%/.prep-builtcommit: $(BUILD_OBJ_DIR)/%/.prep-builtgitindex FORCE
	@$(MKDIR) "$(@D)"
	@cd "$(@D)" && \
	    CURRENT_COMMIT_DATA="`cd $(ORIGIN_SRC_DIR)/$(notdir $(@D)) && git rev-parse --verify HEAD && git status -s | sort -n`" && \
	    [ -n "$$CURRENT_COMMIT_DATA" ] && \
	    if test -s "$@" ; then \
	        SAVED_COMMIT_DATA="`cat "$@"`" && \
	        if test x"$$CURRENT_COMMIT_DATA" = x"$$SAVED_COMMIT_DATA" ; then \
	            exit 0 ; \
	        else \
	            echo "Seems a NEW COMMIT of $(notdir $(@D)) has landed (compared to last build), updating $@" ; echo "NEW: $$CURRENT_COMMIT_DATA"; echo "OLD: $$SAVED_COMMIT_DATA"; \
	            echo "$$CURRENT_COMMIT_DATA" > "$@" ; \
	        fi || exit 1 ; \
	    else \
	        echo "Seems a NEW COMMIT of $(notdir $(@D)) has landed (compared to last build), creating $@" ; echo "NEW: $$CURRENT_COMMIT_DATA"; \
	        echo "$$CURRENT_COMMIT_DATA" > "$@" ; \
	    fi || exit 1


# Note: during prepping, we generally remove and recreate the OBJ_DIR
# which contains the input files. So we stash and recreate them mid-way.
HELP_TOUCHFILES += "    %/.prepped	Clones sources of the checked-out component from" \
                   "        ORIGIN_SRC_DIR to BUILD_OBJ_DIR, and applies patches if told" \
                   "        to (if required by some target OS per .hacks directory and/or" \
                   "        additional includable Makefiles)"
$(BUILD_OBJ_DIR)/%/.prepped: $(BUILD_OBJ_DIR)/%/.prep-newestfetch $(BUILD_OBJ_DIR)/%/.prep-builtcommit $(BUILD_OBJ_DIR)/%/.prep-builtgitindex $(ORIGIN_SRC_DIR)/%/.git
	@$(MKDIR) "$(@D)"
	@if test ! -s "$@" || ! diff "$@" "$<" > /dev/null 2>&1 ; then \
	  if test -f "$(@D)/.installed" || test -f "$(@D)/.install-failed" ; then \
	    echo "UNINSTALL old build of $(notdir $(@D)) while prepping anew..." ; \
	    $(call uninstall_lax_sub,$(notdir $(@D))) ; else true ; \
	  fi; \
	 fi
	@$(RMFILE) "$(@D)"/.*-failed
	@$(RMDIR) "$(@D).tmp"
	@$(MKDIR) "$(@D).tmp"
	@for F in $^ ; do case "$$F" in "$(@D)/".prep*) $(MV) "$$F" "$(@D).tmp/" || exit ;; esac ; done
	@case "x$(PREP_TYPE_$(notdir $(@D)))" in \
	 xnone) \
	    echo "Nothing special to prep for $(notdir $(@D))..." ;; \
	 xcloneln-obj) \
	    echo "CLONE sources of $(notdir $(@D)) as symlinks under BUILD_OBJ_DIR while prepping..." ; \
	    $(call clone_ln,$(ORIGIN_SRC_DIR)/$(notdir $(@D)),$(BUILD_OBJ_DIR)/$(notdir $(@D))) ;; \
	 xcloneln-src) \
	    echo "CLONE sources of $(notdir $(@D)) as symlinks under common BUILD_SRC_DIR while prepping..." ; \
	    $(call clone_ln,$(ORIGIN_SRC_DIR)/$(notdir $(@D)),$(BUILD_SRC_DIR)/$(notdir $(@D))) ;; \
	 xclonetar-obj) \
	    echo "CLONE sources of $(notdir $(@D)) via tarballs under BUILD_OBJ_DIR while prepping..." ; \
	    $(call clone_tar,$(ORIGIN_SRC_DIR)/$(notdir $(@D)),$(BUILD_OBJ_DIR)/$(notdir $(@D))) ;; \
	 xclonetar-src|*) \
	    echo "CLONE sources of $(notdir $(@D)) via tarballs under common BUILD_SRC_DIR while prepping..." ; \
	    $(call clone_tar,$(ORIGIN_SRC_DIR)/$(notdir $(@D)),$(BUILD_SRC_DIR)/$(notdir $(@D))) ;; \
	 esac
	@$(MV) "$(@D).tmp/".prep* "$(@D)"
	@$(RMDIR) "$(@D).tmp"
	@if test -n "$(PREP_ACTION_BEFORE_PATCHING_$(notdir $(@D)))" ; then \
	    case "x$(PREP_TYPE_$(notdir $(@D)))" in \
	     xnone) echo "SKIP PREP_ACTION_BEFORE_PATCHING sources for $(notdir $(@D))..." ; exit 0 ;; \
	     xclone*-obj)   cd $(BUILD_OBJ_DIR)/$(notdir $(@D)) || exit ;; \
	     xclone*-src|*) cd $(BUILD_SRC_DIR)/$(notdir $(@D)) || exit ;; \
	    esac && \
	    ( true ; $(PREP_ACTION_BEFORE_PATCHING_$(notdir $(@D))) ) ; \
	 fi
	@if test -n "$(PATCH_LIST_$(notdir $(@D)))" ; then \
	    case "x$(PREP_TYPE_$(notdir $(@D)))" in \
	     xnone) echo "SKIP PATCHING sources for $(notdir $(@D))..." ; exit 0 ;; \
	     xclone*-obj)   cd $(BUILD_OBJ_DIR)/$(notdir $(@D)) || exit ;; \
	     xclone*-src|*) cd $(BUILD_SRC_DIR)/$(notdir $(@D)) || exit ;; \
	    esac && \
	    for P in $(PATCH_LIST_$(notdir $(@D))) ; do \
	        echo "PATCH sources in `pwd` with $$P" ; \
	        $(GPATCH) $(PATCH_OPTS_$(notdir $(@D))) --merge --forward --batch < "$$P" || exit ; \
	    done ; \
	 fi
	@cat "$<" > "$@"


HELP_TOUCHFILES += "    %/.autogened	After prepping, calls autogen.sh or equivalent to" \
                   "        generate target-dependent files in the cloned source directory"
$(BUILD_OBJ_DIR)/%/.autogened: $(BUILD_OBJ_DIR)/%/.prepped
	+$(call autogen_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.configured	After autogen, calls configure or equivalent to" \
                   "        get ready for building the objects (in object dir)"
$(BUILD_OBJ_DIR)/%/.configured: $(BUILD_OBJ_DIR)/%/.autogened
	+$(call configure_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.built	After configure, builds the sources (usually 'make all')"
$(BUILD_OBJ_DIR)/%/.built: $(BUILD_OBJ_DIR)/%/.configured
	+$(call build_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.disted	After configure, makes a distribution (make dist)"
$(BUILD_OBJ_DIR)/%/.disted: $(BUILD_OBJ_DIR)/%/.configured
	+$(call dist_sub,$(notdir $(@D)))


# Technically, build and install may pursue different targets
# so maybe this should depend on just .configured
HELP_TOUCHFILES += "    %/.installed	After build, installs to common proto area"
$(BUILD_OBJ_DIR)/%/.installed: $(BUILD_OBJ_DIR)/%/.built
	+$(call install_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.checked	After build, runs self-tests (make check)"
$(BUILD_OBJ_DIR)/%/.checked: $(BUILD_OBJ_DIR)/%/.built
	+$(call check_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.checked-verbose	After build, runs verbose self-tests"
$(BUILD_OBJ_DIR)/%/.checked-verbose: $(BUILD_OBJ_DIR)/%/.built
	+$(call check_verbose_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.distchecked	After build, runs dist, sub-build and the" \
                   "        self-tests in that copy of codebase (make distcheck)"
$(BUILD_OBJ_DIR)/%/.distchecked: $(BUILD_OBJ_DIR)/%/.built
	+$(call distcheck_sub,$(notdir $(@D)))


HELP_TOUCHFILES += "    %/.memchecked	After build, runs self-tests under valgrind"
$(BUILD_OBJ_DIR)/%/.memchecked: $(BUILD_OBJ_DIR)/%/.built
	+$(call memcheck_sub,$(notdir $(@D)))


# Phony targets to make or clean up a build of components
# Also note rules must be not empty to actually run something
# NOTE: The use of $(@F) in the rules assumes submodules are not nested
#       otherwise text conversions are needed to chomp until first slash
HELP_COMPTGT += "    clean-obj/%	Remove the built-object directory for component"
clean-obj/%:
	@if test -d "$(BUILD_OBJ_DIR)" && \
	   test x"$(BUILD_OBJ_DIR)" != x"$(ORIGIN_SRC_DIR)" ; then\
	    chmod -R u+w $(BUILD_OBJ_DIR)/$(@F) || true; \
	    $(RMDIR) $(BUILD_OBJ_DIR)/$(@F); \
	 else \
	    echo "  NOOP    Generally $@ has nothing to do for now"; \
	 fi

HELP_COMPTGT += "    clean-src/%	Remove the source-replica directory for component"
clean-src/%:
	@if test -d "$(BUILD_SRC_DIR)" && \
	   test x"$(BUILD_SRC_DIR)" != x"$(ORIGIN_SRC_DIR)" ; then\
	    chmod -R u+w $(BUILD_SRC_DIR)/$(@F) || true; \
	    $(RMDIR) $(BUILD_SRC_DIR)/$(@F); \
	 else \
	    echo "  NOOP    Generally $@ has nothing to do for now"; \
	 fi
	@if test x"$(@F)" = x"czmq" && test -L "$(ORIGIN_SRC_DIR)/$(@F)" ; then \
	    $(RM) "$(ORIGIN_SRC_DIR)/$(@F)" ; \
	 else true; fi

HELP_COMPTGT += "    (dist)clean/%	Run clean-obj and clean-src (above) on the component"
distclean/% clean/%:
	$(MAKE) clean-obj/$(@F)
	$(MAKE) clean-src/$(@F)

HELP_COMPTGT += "    prep/%	Prep the component (create a %/.prepped for it)"
prep/%: $(BUILD_OBJ_DIR)/%/.prepped
	@true

HELP_COMPTGT += "    autogen/%	Generate files for the component (create a" \
                "       %/.autogened for it)"
autogen/%: $(BUILD_OBJ_DIR)/%/.autogened
	@true

HELP_COMPTGT += "    configure/%	Configure sources to build the component" \
                "       (create a %/.configured for it)"
configure/%: $(BUILD_OBJ_DIR)/%/.configured
	@true

HELP_COMPTGT += "    build/%	Build the configured component (%/.built)"
build/%: $(BUILD_OBJ_DIR)/%/.built
	@true

# Fake the updated sources to build just the recently changed code
# Requires cloneln-src to be in effect for the component
# Can not guarantee consistency of codebase in automated builds -
# this option is here only to speed up manual development iterations.
HELP_SPECIALDEVTGT += "    devel/%	Special rule for building the configured component" \
                      "       during development cycles, bringing edited source files into" \
                      "       the source-replica and remaking just whatever depends on them"
devel/%:
	@case "x$(PREP_TYPE_$(@F))" in \
	 xcloneln-*) ;; \
	 xclonetar-obj) \
	    if test -d "$(BUILD_OBJ_DIR)/$(@F)" ; then \
	        echo "UPDATING sources-clone in BUILD_OBJ_DIR/$(@F)..." ; \
	        $(call clone_cp_update,$(ORIGIN_SRC_DIR)/$(@F),$(BUILD_OBJ_DIR)/$(@F)) ; \
	    fi ;; \
	 xclonetar-src|x) \
	    if test -d "$(BUILD_SRC_DIR)/$(@F)" ; then \
	        echo "UPDATING sources-clone in BUILD_SRC_DIR/$(@F)..." ; \
	        $(call clone_cp_update,$(ORIGIN_SRC_DIR)/$(@F),$(BUILD_SRC_DIR)/$(@F)) ; \
	    fi ;; \
	 *) echo "REBUILDING component $(@F) because its PREP_TYPE='$(PREP_TYPE_$(@F))' is not 'cloneln-*'..." ; \
	    $(MAKE) rebuild/$(@F) ; exit ;; \
	 esac && \
	    echo "LOOKING AT '$(BUILD_OBJ_DIR)/$(@F)/.configured'" && \
	    if test -f $(BUILD_OBJ_DIR)/$(@F)/.configured ; then \
	        echo "UPDATING last build of component $(@F) which was already configured..." ; \
	        $(TOUCH) $(BUILD_OBJ_DIR)/$(@F)/.configured ; \
	    else \
	        echo "UPDATING last build of component $(@F) starting by re-configuring it..." ; \
	        $(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.configured ; \
	    fi && \
	    $(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.built

HELP_COMPTGT += "    install/%	Install the configured component (%/.installed)"
install/%: $(BUILD_OBJ_DIR)/%/.installed
	@true

HELP_COMPTGT += "    check/%	'make check' the component (%/.checked)"
check/%: $(BUILD_OBJ_DIR)/%/.checked
	@true

HELP_COMPTGT += "    check-verbose/%	Verbosely 'make check' the component" \
                "       (%/.checked-verbose)"
check-verbose/%: $(BUILD_OBJ_DIR)/%/.checked-verbose
	@true

HELP_COMPTGT += "    distcheck/%	'make distcheck' the component (%/.distchecked)"
distcheck/%: $(BUILD_OBJ_DIR)/%/.distchecked
	@true

HELP_COMPTGT += "    dist/%	'make dist' the component (%/.disted)"
dist/%: $(BUILD_OBJ_DIR)/%/.disted
	@true

HELP_COMPTGT += "    redist/%	'make clean' and then dist the component (%/.disted)"
redist/%:
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.disted

HELP_COMPTGT += "    valgrind/% or memcheck/%	Run 'make check' under valgrind" \
                "       for the component (%/.memchecked)"
valgrind/% memcheck/%: $(BUILD_OBJ_DIR)/%/.memchecked
	@true

# This is a sort of torture test for components that fail, but not
# consistently (e.g. due to race conditions, phase of moon, etc.)
# Run the memcheck for the component indefinitely, until it fails.
HELP_SPECIALDEVTGT += "    valgrind-loop/% or memcheck-loop/%	Special stress-testing target" \
                      "       to run the memcheck in an infinite loop until it fails for the" \
                      "       previously checked component"
valgrind-loop/% memcheck-loop/%: $(BUILD_OBJ_DIR)/%/.checked
	@echo "Looping indefinitely until memcheck of $(@F) fails..."
	+N=1; while $(call memcheck_sub,$(@F)) ; do \
	    echo "The $$N run of memcheck of $(@F) succeeded, retrying..." ; \
	    N="`expr $$N + 1`" || true ; \
	    sleep 1; \
	 done ; \
	 RES=$$? ; \
	 echo "The $$N run of memcheck of $(@F) FAILED with code $$RES" >&2 ; \
	 exit $$RES

HELP_SPECIALDEVTGT += "    assume/%	Special target to claim that development dependency files" \
                      "       provided by this component are available somehow outside this" \
                      "       dispatcher repo, so it should not be rebuit (creates %/.installed)." \
                      "       Note that subsequent git-pull updates can override this touchfile"
assume/%:
	@echo "ASSUMING that $(@F) is available through means other than building from sources"
	@$(MKDIR) $(BUILD_OBJ_DIR)/$(@F)
	@$(TOUCH) $(BUILD_OBJ_DIR)/$(@F)/.installed

HELP_SPECIALDEVTGT += "    nowarn/%	Special target to build with -Wall -Werror (%/.built)"
nowarn/%:
	$(MAKE) clean/$(@F)
	$(MAKE) CFLAGS="$(CFLAGS) -Wall -Werror" CPPFLAGS="$(CPPFLAGS) -Wall -Werror" CXXFLAGS="$(CXXFLAGS) -Wall -Werror" $(BUILD_OBJ_DIR)/$(@F)/.built

HELP_COMPTGT += "    rebuild/%	'make clean' and then build the component (%/.built)"
rebuild/%:
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.built

HELP_COMPTGT += "    recheck/%	'make clean' and then check the component (%/.checked)"
recheck/%:
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.checked

HELP_COMPTGT += "    recheck-verbose/%	'make clean' and then check-verbose the component"
recheck-verbose/%:
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.checked-verbose

HELP_COMPTGT += "    redistcheck/%	'make clean' and then distcheck the component"
redistcheck/%:
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.distchecked

HELP_COMPTGT += "    reinstall/%	Uninstall (if needed), 'make clean' and then install" \
                "       the component (%/.installed)"
reinstall/%:
	if test -f $(BUILD_OBJ_DIR)/$(@F)/.installed ; then $(call uninstall_lax_sub,$(@F)) ; fi
	$(MAKE) clean/$(@F)
	$(MAKE) $(BUILD_OBJ_DIR)/$(@F)/.installed

### Use currently developed zproject to regenerate a project
HELP_SPECIALDEVTGT += "    regenerate/%	Special target to regenerate zproject files per" \
                      "       project.xml and start 'git difftool -y' to put back customizations" \
                      "       See also ./ProjectXML for smarter activity about this subject"
regenerate/%: $(BUILD_OBJ_DIR)/zproject/.installed
	@( cd "$(ORIGIN_SRC_DIR)/$(@F)" && \
	    echo "REGENERATING ZPROJECT for $(@F)..." && \
	    echo "    See also ./ProjectXML for smarter activity about this subject" && \
	    gsl project.xml && \
	    ./autogen.sh && \
	    case "$(@F)" in \
	        */fty-*) echo "REMOVING CMAKE files from fty-* component sources..." ; \
	            rm -f CMake* *.cmake builds/cmake/ci_build.sh || true ;; \
	    esac && \
	    git difftool -y || \
	    { echo "FAILED to regenerate zproject for $(@F)!" >&2; exit 1; } )

### Resync current checkout to upstream/master
### The "auto" mode is intended for rebuilds, so it quietly
### follows the configured default branch. Simple "git-resync"
### stays in developer's current branch and merges it with
### changes trickling down from upstream default branch.
HELP_SPECIALTGT += "    git-resync/%	Special target to pull newest code from remote git" \
                   "       and rebase the currently checked-out branch over the default" \
                   "       master/release/... branch as configured by git submodules in" \
                   "       this branch of the FTY dispatcher repo"
HELP_SPECIALTGT += "    git-resync-auto/%	Special target to pull newest code from remote git" \
                   "       and force-checkout the default master/release/... branch (see above)"
git-resync/% git-resync-auto/%: $(ORIGIN_SRC_DIR)/%/.git
	@( BASEBRANCH="`git config -f $(ORIGIN_SRC_DIR)/.gitmodules submodule.$(@F).branch`" || BASEBRANCH="" ; \
	  test -n "$$BASEBRANCH" || BASEBRANCH=master ; \
	  cd "$(ORIGIN_SRC_DIR)/$(@F)" && \
	    { git remote -v | grep upstream && BASEREPO="upstream" || BASEREPO="origin" ; } && \
	    case "$@" in \
	      *git-resync-auto/*) git checkout -f "$$BASEBRANCH" ;; \
	      *) true ;; \
	    esac && \
	    git pull --all && \
	    ( git pull --tags || git fetch --tags ) && \
	    git merge "$$BASEREPO/$$BASEBRANCH" && \
	    case "$@" in \
	      *git-resync-auto/*) true ;; \
	      *) git rebase -i "$$BASEREPO/$$BASEBRANCH" ;; \
	    esac; \
	)

# Note this one would trigger a (re)build run
HELP_COMPTGT += "    uninstall/%	Uninstall the previously configured component" \
                "       (might trigger a rebuild to get the Makefiles available)"
uninstall/%: $(BUILD_OBJ_DIR)/%/.configured
	$(call uninstall_sub,$(@F))

HELP_COMPTGT += "    uninstall_lax/%	Relaxed uninstall (do not fail this 'make'" \
                "       if the uninstall activity does not succeed)"
uninstall_lax/%:
	$(call uninstall_lax_sub,$(@F))

# Rule-them-all rules! e.g. build-all install-all uninstall-all clean-all
HELP_BASETGT += "    rebuild-all	Cleans and builds all components"
rebuild-all:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_ALL))
	$(MAKE) $(addprefix build/,$(COMPONENTS_ALL))

HELP_BASETGT += "    rebuild-fty	Cleans and builds FTY components"
rebuild-fty:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_FTY))
	$(MAKE) $(addprefix build/,$(COMPONENTS_FTY))

HELP_BASETGT += "    rebuild-fty-experimental	Cleans and builds FTY-experimental components"
rebuild-fty-experimental:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_FTY_EXPERIMENTAL))
	$(MAKE) $(addprefix build/,$(COMPONENTS_FTY_EXPERIMENTAL))

HELP_BASETGT += "    reinstall-all	Cleans and installs all components"
reinstall-all:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_ALL))
	$(MAKE) $(addprefix install/,$(COMPONENTS_ALL))

HELP_BASETGT += "    reinstall-fty	Cleans and installs FTY components"
reinstall-fty:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_FTY))
	$(MAKE) $(addprefix install/,$(COMPONENTS_FTY))

HELP_BASETGT += "    reinstall-fty-experimental	Cleans and installs FTY-experimental components"
reinstall-fty-experimental:
	$(MAKE) $(addprefix clean/,$(COMPONENTS_FTY_EXPERIMENTAL))
	$(MAKE) $(addprefix install/,$(COMPONENTS_FTY_EXPERIMENTAL))

HELP_BASETGT += "    %-all	Does the '%' action for all components"
%-all: $(addprefix %/,$(COMPONENTS_ALL))
	@echo "COMPLETED $@ : made '$^'"

HELP_BASETGT += "    %-fty	Does the '%' action for FTY components"
%-fty: $(addprefix %/,$(COMPONENTS_FTY))
	@echo "COMPLETED $@ : made '$^'"

HELP_BASETGT += "    %-fty-experimental	Does the '%' action for FTY-experimental components"
%-fty-experimental: $(addprefix %/,$(COMPONENTS_FTY_EXPERIMENTAL))
	@echo "COMPLETED $@ : made '$^'"

HELP_SPECIALTGT += "    wipe / mrproper	Remove all build workspaces and intermediate" \
                   "       source locations (leave git checkouts in place) to start anew"
wipe mrproper:
	if [ -d $(BUILD_SRC_DIR) ] ; then chmod -R u+w $(BUILD_SRC_DIR) || true ; fi
	if [ -d $(BUILD_OBJ_DIR) ] ; then chmod -R u+w $(BUILD_OBJ_DIR) || true ; fi
	$(RMDIR) $(BUILD_SRC_DIR) $(BUILD_OBJ_DIR)
	case "$(INSTDIR)" in \
	    $(abs_builddir)/.install/*)  $(RMDIR) $(INSTDIR) ;; \
	esac


# Speak BSDisch?
HELP_SPECIALTGT += "    emerge	Does a 'make git-resync-auto-all' to (forcefully!) checkout" \
                   "        the default branches as configured by git submodules in this" \
                   "        branch of the FTY dispatcher repo and update to newest remote" \
                   "        codebases from GitHub"
emerge: git-resync-auto-all
	@echo "COMPLETED $@ : made '$^'"

HELP_SPECIALTGT += "    rebase	Does a 'make git-resync-all' to pull newest remote codebases" \
                   "        from GitHub and interactively rebase the developer's currently" \
                   "        checked out branch over the default branch as configured by git" \
                   "        submodules in this branch of the FTY dispatcher, for each component"
rebase: git-resync-all
	@echo "COMPLETED $@ : made '$^'"

HELP_SPECIALDEVTGT += "    world	Does an 'emerge' and then 'install-all install-fty-experimental'" \
                      "        so you have the whole ecosystem built and ready to develop in as" \
                      "        far as development dependencies go, all by one simple command"
world:
	$(MAKE) AUTODEPS_NOT_REQUIRED=true -j8 emerge \
	    || $(MAKE) AUTODEPS_NOT_REQUIRED=true emerge
	$(MAKE) install-all install-fty-experimental

HELP_LIST_COMPONENTS ?= no
help:
	@echo "This Makefile automates the FTY dispatcher repository builds for multiple" ; \
	 echo "use-cases in the same development cycle (editing sources in one place)." ; \
	 echo "See https://github.com/42ity/FTY.git and the README for more details." ; \
	 echo ""; for LINE in $(HELP_BASETGT) ; do echo "$$LINE"; done ; \
	 echo ""; for LINE in $(HELP_TOUCHFILES) ; do echo "$$LINE"; done; \
	 echo ""; for LINE in $(HELP_SPECIALTGT) ; do echo "$$LINE"; done ; \
	 echo ""; for LINE in $(HELP_COMPTGT) ; do echo "$$LINE"; done ; \
	 echo ""; for LINE in $(HELP_SPECIALDEVTGT) ; do echo "$$LINE"; done ; \
	 echo ""; if [ "$(HELP_LIST_COMPONENTS)" = yes ] ; then \
	    echo "The following component lists (referenced by some rules above) are now known:"; \
	    echo "    COMPONENTS_ALL = $(COMPONENTS_ALL)" ; \
	    echo "    COMPONENTS_FTY = $(COMPONENTS_FTY)" ; \
	    echo "    COMPONENTS_FTY_EXPERIMENTAL = $(COMPONENTS_FTY_EXPERIMENTAL)" ; \
	  else echo "Use 'make help HELP_LIST_COMPONENTS=yes' to also detail the component lists"; fi; \
	 if [ -n "$(HELP_ADDONS)" ] ; then echo ""; for LINE in $(HELP_ADDONS) ; do echo "$$LINE"; done ; fi; \
	 echo ""; echo "Again, see https://github.com/42ity/FTY.git and the README for more details."

# Note: these come in last, so we can "make emerge"
# to have the needed project.xml's and generate these
sinclude .autodeps.fty-stable
sinclude .autodeps.fty-experimental
