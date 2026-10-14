#!/bin/sh

#
# The image's cookie is public: on the host network it would let anyone in.
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
