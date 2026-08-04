#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps ./bin/start from bigbluebutton/greenlight.
#
# Greenlight calls the API over the public name, so Ruby validates whatever answers.
# Pointing that name at the pod and trusting its certificate works with or without
# Let's Encrypt.
#

set -e

# Appended, never mounted over: replacing this file drops the pod's --add-host
# names, and DNS can then answer for an internal name with a public address.
if [ -n "$DOMAIN" ] && ! grep -q "[[:space:]]${DOMAIN}\$" /etc/hosts; then
    printf '127.0.0.1\t%s\n' "$DOMAIN" >> /etc/hosts
fi

if [ -s /usr/local/share/ca-certificates/bigbluebutton-internal.crt ]; then
    update-ca-certificates >/dev/null 2>&1 || \
        echo "greenlight: could not refresh the CA store, API calls may fail" >&2
fi

exec ./bin/start
