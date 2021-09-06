#!/bin/sh

cat << EOF
This helper script allows developers to update their workspaces
with same contents of "main branch" (usually named "master",
but for release/featureimage it may differ) of each FTY component
they track.

See sync-update-origin.sh for a similar activity script that would
also push the current master (equivalent) to your GitHub "origin"
forks.

Note this script WILL CHANGE CURRENT BRANCH in your checkouts!
(Sleeping 5 sec so you can Ctrl+C)
EOF

# See sync.sh for authoritative copy
default_branches() {
    git submodule foreach -q --recursive \
    'git checkout $(git config -f $toplevel/.gitmodules submodule.$name.branch || for B in master main devel ; do git branch | grep -w "$B" >/dev/null && echo "$B" && exit ; done )'
}

sleep 5

default_branches \
&& gmake emerge -j -k \
|| { echo 'FAILED' >&2 ; exit 1; }

