#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Sourced by greenlight-entrypoint.sh and recordings-entrypoint.sh. Both call
# back into the public name from inside the pod and need the same two things
# before their upstream entrypoint runs, so the logic lives here once.
#

# Appended, never mounted over: replacing /etc/hosts drops the pod's --add-host
# names, and DNS can then answer for an internal name with a public address.
pod_trust_add_host() {
    if [ -n "$DOMAIN" ] && ! grep -q "[[:space:]]${DOMAIN}\$" /etc/hosts; then
        printf '127.0.0.1\t%s\n' "$DOMAIN" >> /etc/hosts
    fi
}

# $1: what to tell the reader breaks if the store is stale.
pod_trust_refresh_ca() {
    if [ -s /usr/local/share/ca-certificates/bigbluebutton-internal.crt ]; then
        update-ca-certificates >/dev/null 2>&1 || \
            echo "could not refresh the CA store, $1" >&2
    fi
}
