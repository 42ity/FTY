#!/usr/bin/env bash

################################################################################
# This file is based on a template used by zproject, but isn't auto-generated. #
# Building of dependencies (our components and forks of third-party projects)  #
# in correct order is buried into the Makefile.                                #
################################################################################

set -e

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

case "$BUILD_TYPE" in
default|"default-tgt:"*)
    LANG=C
    LC_ALL=C
    export LANG LC_ALL

    # Build and check this project; note that zprojects always have an autogen.sh
    [ -z "$CI_TIME" ] || echo "`date`: Starting build of currently tested project..."

    BUILD_TGT=all
    case "$BUILD_TYPE" in
        default-tgt:*) # Hook for matrix of custom distchecks primarily
            BUILD_TGT="`echo "$BUILD_TYPE" | sed 's,^default-tgt:,,'`" ;;
    esac

    if [ x"$CI_WIPE_FIRST" = xyes ]; then
        echo "`date`: First wiping stashed workspace directories..."
        $CI_TIME make wipe
    fi

    ( echo "`date`: Starting the quiet parallel build attempt..."
#      case "$BUILD_TYPE" in
#        default-tgt:*check*)
#            echo "`date`: First fully build and install some components that are picky to sub-make during checks..."
#            $CI_TIME make VERBOSE=0 V=0 -j1 install/libcidr install/libzmq install/czmq install/tntdb || exit
#            echo "`date`: Proceed with general build..."
#            ;;
#      esac
      BLDRES=$?
      $CI_TIME make VERBOSE=0 V=0 -k -j4 "$BUILD_TGT" &
      PID_MAKE=$!
      ( minutes=0
        limit=29
        while kill -0 ${PID_MAKE} >/dev/null 2>&1 ; do
          printf ' \b' # Hidden print to keep the logs ticking
          if [ "$minutes" -ge "$limit" ]; then
            echo "`date`: Parallel build timed out over $limit minutes" >&2
            kill -15 ${PID_MAKE}
            sleep 5
            exit 1
          fi
          minutes="$(expr $minutes + 1)"
          sleep 60
        done
        echo "`date`: Parallel build attempt seems done" ) &
      PID_SLEEPER=$!
      RES=0
      wait ${PID_MAKE} || RES=$?
      wait ${PID_SLEEPER} || RES=$?
      exit $RES
    ) || \
    ( echo "==================== PARALLEL ATTEMPT FAILED ($?) =========="
      echo "`date`: Starting the sequential build attempt..."
      # Avoiding travis_wait() and build timeouts during tests
      # thanks to comments in Travis-CI issue #4190
      $CI_TIME make VERBOSE=1 "$BUILD_TGT" &
      PID_MAKE=$!
      ( minutes=0
        limit=29
        while kill -0 ${PID_MAKE} >/dev/null 2>&1 ; do
          printf ' \b' # Hidden print to keep the logs ticking
          if [ "$minutes" -ge "$limit" ]; then
            echo "`date`: Sequential build timed out over $limit minutes" >&2
            kill -15 ${PID_MAKE}
            sleep 5
            exit 1
          fi
          minutes="$(expr $minutes + 1)"
          sleep 60
        done
        echo "`date`: Sequential build attempt seems done" ) &
      PID_SLEEPER=$!
      RES=0
      wait ${PID_MAKE} || RES=$?
      wait ${PID_SLEEPER} || RES=$?
      exit $RES
    ) || \
    BLDRES=$?
    echo "=== `date`: BUILDS FINISHED ($BLDRES)"

    echo "=== `date`: Are GitIgnores good after 'make $BUILD_TGT'? (should have no output below)"
    git status -s || git status || true
    echo "==="
    if [ "$HAVE_CCACHE" = yes ]; then
        echo "CCache stats after build:"
        ccache -s
    fi
    [ "$BLDRES" = 0 ] && \
    echo "=== `date`: Exiting after the custom-build target 'make $BUILD_TGT' succeeded OK" || \
    echo "=== `date`: Exiting after the custom-build target 'make $BUILD_TGT' FAILED with code $BLDRES" >&2
    exit $BLDRES
    ;;
bindings)
    pushd "./bindings/${BINDING}" && ./ci_build.sh
    ;;
*)
    pushd "./builds/${BUILD_TYPE}" && REPO_DIR="$(dirs -l +1)" ./ci_build.sh
    ;;
esac
