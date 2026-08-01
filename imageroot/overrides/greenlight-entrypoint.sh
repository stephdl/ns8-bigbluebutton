#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps ./bin/start from bigbluebutton/greenlight.
#
# Greenlight calls the BigBlueButton API over the site's public HTTPS name --
# it has to, because the same value becomes the join URL it hands to the
# browser, and a loopback address there is useless. Ruby therefore validates
# the certificate answering for that name.
#
# The container resolves that name to 127.0.0.1, so the answer comes from this
# pod's own nginx, presenting a certificate configure-module issued for exactly
# this name. Trust it here and both the name and the issuer check out, whether
# or not Traefik has a Let's Encrypt certificate for the site.
#

set -e

if [ -s /usr/local/share/ca-certificates/bigbluebutton-internal.crt ]; then
    update-ca-certificates >/dev/null 2>&1 || \
        echo "greenlight: could not refresh the CA store, API calls may fail" >&2
fi

exec ./bin/start
