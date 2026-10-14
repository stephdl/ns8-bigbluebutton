#!/bin/sh

#
# Replace the image's public Erlang cookie: on the host network, any local
# user knowing it could run code inside eturnal.
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
