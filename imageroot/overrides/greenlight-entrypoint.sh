#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps ./bin/start from bigbluebutton/greenlight.
#
# Greenlight calls the API over the site's public name -- the same value becomes
# the join URL handed to the browser, so a loopback address is useless -- and Ruby
# validates whatever certificate answers. The container resolves that name to
# 127.0.0.1 and is shown the internal certificate, so trusting it here works with
# or without Let's Encrypt.
#

set -e

# Appended, never mounted over: podman generates this file with the pod's
# --add-host names, and replacing it sends the resolver to DNS, where a wildcard
# record can answer for an internal name with a public address.
if [ -n "$DOMAIN" ] && ! grep -q "[[:space:]]${DOMAIN}\$" /etc/hosts; then
    printf '127.0.0.1\t%s\n' "$DOMAIN" >> /etc/hosts
fi

if [ -s /usr/local/share/ca-certificates/bigbluebutton-internal.crt ]; then
    update-ca-certificates >/dev/null 2>&1 || \
        echo "greenlight: could not refresh the CA store, API calls may fail" >&2
fi

exec ./bin/start
