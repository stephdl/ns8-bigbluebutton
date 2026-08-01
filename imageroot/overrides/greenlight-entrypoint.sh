#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps ./bin/start from bigbluebutton/greenlight.
#
# Greenlight calls the BigBlueButton API over the site's public HTTPS name --
# it has to, because the same value becomes the join URL it hands to the
# browser, and a loopback address there is useless. Ruby therefore has to trust
# whatever certificate Traefik serves, which on a node without a publicly
# issued certificate is self-signed and rejected.
#
# configure-module drops that certificate next to this script. Trusting it is a
# no-op when Traefik already serves a publicly trusted one.
#

set -e

if [ -s /usr/local/share/ca-certificates/traefik.crt ]; then
    update-ca-certificates >/dev/null 2>&1 || \
        echo "greenlight: could not refresh the CA store, API calls may fail" >&2
fi

exec ./bin/start
