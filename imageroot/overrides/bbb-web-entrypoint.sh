#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from bigbluebutton/bbb-web.
#
# bbb-web fetches every room's first slide from the site's own public HTTPS name,
# so Java validates whatever certificate answers for it. The container resolves
# that name to 127.0.0.1, where this pod's nginx presents the certificate
# configure-module issued for exactly this name - trusted here, so the fetch
# validates whether or not Traefik holds a Let's Encrypt certificate.
#
# Upstream's alternative is IGNORE_TLS_CERT_ERRORS, which despite its name
# disables nothing in bbb-web: it only swings the presentation URL to
# raw.githubusercontent.com, trading the slide for an internet round trip on
# every meeting create. Trusting one certificate is both narrower and offline.
#
# Unlike Greenlight, update-ca-certificates is not enough here: this image has no
# ca-certificates-java and no /etc/ssl/certs/java/cacerts, so the JRE store has
# to be edited directly.
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
