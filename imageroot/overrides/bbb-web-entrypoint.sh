#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from bigbluebutton/bbb-web.
#
# bbb-web fetches every room's first slide over the site's public name, so Java
# validates whatever certificate answers. The container resolves that name to
# 127.0.0.1 and is shown the internal certificate, never Traefik's, so trusting
# that one here works with or without Let's Encrypt.
#
# update-ca-certificates is not enough: this image has no ca-certificates-java
# and no /etc/ssl/certs/java/cacerts, so the JRE store is edited directly.
#

set -e

CRT=/usr/local/share/ca-certificates/bigbluebutton-internal.crt
STORE="${JAVA_HOME:-/opt/java/openjdk}/lib/security/cacerts"

if [ -s "$CRT" ] && [ -w "$STORE" ]; then
    # changeit is the JRE's stock store password, unchanged in this image.
    keytool -delete -alias bigbluebutton-internal -keystore "$STORE" \
        -storepass changeit >/dev/null 2>&1 || true
    if ! keytool -importcert -noprompt -trustcacerts \
            -alias bigbluebutton-internal -file "$CRT" \
            -keystore "$STORE" -storepass changeit >/dev/null 2>&1; then
        # Not fatal: rooms still open, they just open without the default slide.
        echo "bbb-web: could not trust the internal certificate, the default" \
             "presentation will fail to download" >&2
    fi
else
    echo "bbb-web: no internal certificate to trust at $CRT" >&2
fi

exec /entrypoint.sh
