#!/bin/sh

# Initially fetch or subsequently update the components
# referred to as "git submodule"'s
# Can also run from Travis CI context, hence support for its vars
# Copyright (C) 2017 by Jim Klimov <EvgenyKlimov@eaton.com>

# See also
# https://git-scm.com/book/en/v2/Git-Tools-Submodules
# http://stackoverflow.com/questions/5828324/update-git-submodule-to-latest-commit-on-origin
# http://stackoverflow.com/questions/1979167/git-submodule-update/1979194#1979194

set -e
unset GREP_OPTIONS

# Set this to enable verbose profiling
[ -n "${CI_TIME-}" ] || CI_TIME=""
case "$CI_TIME" in
    [Yy][Ee][Ss]|[Oo][Nn]|[Tt][Rr][Uu][Ee])
        CI_TIME="time -p " ;;
    [Nn][Oo]|[Oo][Ff][Ff]|[Ff][Aa][Ll][Ss][Ee])
        CI_TIME="" ;;
esac

# Set this to enable verbose tracing
[ -n "${CI_TRACE-}" ] || CI_TRACE="no"
case "$CI_TRACE" in
    [Nn][Oo]|[Oo][Ff][Ff]|[Ff][Aa][Ll][Ss][Ee])
        set +x ;;
    [Yy][Ee][Ss]|[Oo][Nn]|[Tt][Rr][Uu][Ee])
        set -x ;;
esac

default_branches() {
    $CI_TIME git submodule foreach -q --recursive \
    'git checkout $(git config -f $toplevel/.gitmodules submodule.$name.branch || for B in master main devel ; do git branch | grep -w "$B" >/dev/null && echo "$B" && exit ; done )'
}

# Update dispatcher repo
$CI_TIME git pull --all

# Update component repos
# NOTE: sync is toxic to established workspaces, as it "resyncs the URL" and
# so overwrites locally defined "origin" URL (e.g. pointing to a developers'
# fork) back to the upstream project URL. For daily usage, "update" suffices.
# The "init" is a no-op if things are already set up.
# The next line causes submodules to track the branch they are set up to use
# via .gitmodules file, or the "master" one. Note that each "submodule update"
# checks out a specified SHA1 and stops tracking any specific branch.
# git submodule init --recursive && \
# git submodule sync --recursive && \
### The "submodule init" line may be needed when massively adding new modules,
### but toxic otherwise (resets to HEAD and breaks later recurse-submodules):
### $CI_TIME git submodule init && \
### $CI_TIME git submodule foreach "git submodule init" && \
$CI_TIME git submodule init && \
$CI_TIME git submodule foreach "git submodule init" && \
default_branches && \
$CI_TIME git submodule foreach "git pull --recurse-submodules" && \
$CI_TIME git pull --recurse-submodules && \
default_branches && \
$CI_TIME git submodule update --recursive --remote --merge && \
default_branches && \
$CI_TIME git submodule foreach "git pull --all" && \
$CI_TIME git submodule foreach "git pull --tags" && \
$CI_TIME git status -s \
|| exit $?

if [ x"${DO_BUMP-}" = xno ] ; then
    git status -s
    echo "Skip Adding changed objects to git commit (envvar DO_BUMP=no was pre-set)"
else
    DO_BUMP=no
    # Let shell cut off indentations and other whitespace
    git status -s | ( while read STATUS OBJNAME ; do
        if [ -n "$OBJNAME" ]; then
            case "$STATUS" in
                M) exit 0 ;;
            esac
        fi
      done
      exit 1
    ) && DO_BUMP=yes
fi

if [ x"${DO_BUMP-}" = xyes ]; then
    echo "Adding changed objects to git commit (pre-set envvar DO_BUMP=no to avoid this)..."
    $CI_TIME git commit -a -m 'Updated references to git submodule HEADs at '"`date -u`"
fi
