#!/bin/sh -e

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker recordings image.
#
# The image ships a Ruby newer than its own scripts: File.exists? was removed from
# the language and the recording pipeline still calls it, so every recording dies
# in the sanity worker, leaves a .fail marker, and never reaches getRecordings --
# the room's recordings list just stays empty.
#
# Patched in place rather than shipping copies: these are upstream scripts that
# change between releases, and once they stop calling it the substitutions match
# nothing. rap-process-worker.rb matters as much as sanity.rb -- fixing only the
# sanity check moves the failure one stage down instead of clearing it.
#

for script in \
    /usr/local/bigbluebutton/core/scripts/sanity/sanity.rb \
    /usr/local/bigbluebutton/core/scripts/rap-process-worker.rb
do
    [ -f "$script" ] || continue
    sed -i -e 's/File\.exists?/File.exist?/g' -e 's/Dir\.exists?/Dir.exist?/g' "$script"
done

# The publish stage posts a recording-ready callback to Greenlight on the site's
# public name, taken from the recording's own metadata. Send it to the pod's own
# nginx and trust the certificate it serves there. Without this the callback
# dies on "certificate verify failed" and the recording never reaches a room's
# library, even though it published correctly.
#
# Appended, never mounted over: podman generates this file with the pod's
# --add-host names, and replacing it drops them. The resolver then falls
# through to DNS, where a search domain and a wildcard record answered for
# "redis" with a public address and the resque queue timed out reaching it.
if [ -n "$DOMAIN" ] && ! grep -q "[[:space:]]${DOMAIN}\$" /etc/hosts; then
    printf '127.0.0.1\t%s\n' "$DOMAIN" >> /etc/hosts
fi

if [ -s /usr/local/share/ca-certificates/bigbluebutton-internal.crt ]; then
    update-ca-certificates >/dev/null 2>&1 || \
        echo "recordings: could not refresh the CA store, the ready callback may fail" >&2
fi

exec /entrypoint.sh
