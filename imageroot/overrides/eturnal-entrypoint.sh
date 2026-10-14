#!/bin/sh

#
# The image appends a fixed "-setcookie eturnal" to vm.args, and the Erlang
# distribution listens on 127.0.0.1. With --network=host, any local user who
# knows that public cookie could run code inside eturnal. Swap in our own,
# from state/eturnal.env.
#

set -eu

umask 077
src=$(find /opt/eturnal/releases -name vm.args | head -n 1)
[ -n "$src" ] || { echo "eturnal: no vm.args in the image" >&2; exit 1; }
grep -v '^-setcookie' "$src" > /tmp/vm.args
printf -- '-setcookie %s\n' "$ETURNAL_COOKIE" >> /tmp/vm.args

export VMARGS_PATH=/tmp/vm.args
export RELX_COOKIE="$ETURNAL_COOKIE"
unset ETURNAL_COOKIE

exec /usr/local/bin/run.sh
