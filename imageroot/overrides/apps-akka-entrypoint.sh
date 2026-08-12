#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker apps-akka image.
#
# This container owns the HTML5 client's settings, not nginx: the copy of
# settings.yml shipped there is never read.
#

set -e

SETTINGS=/usr/share/bigbluebutton/html5-client/private/config/settings.yml

# Unset on an install older than the setting, and podman turns an unset variable
# into an empty one, so fall back to upstream's value.
if [ "${SHOW_PRESENTATION_ON_JOIN:-true}" = "false" ]; then
    hide=true
else
    hide=false
fi

# A failure here is a worse default, not a broken room.
if [ -f "$SETTINGS" ]; then
    if ! yq e -i ".public.layout.hidePresentationOnJoin = $hide" "$SETTINGS"; then
        echo "apps-akka: could not set hidePresentationOnJoin, keeping the image default" >&2
    fi
fi

# Spelled out, not "$@": --entrypoint clears the image CMD, and a wrapper handed
# nothing exits 0, which Restart=always turns into a crash loop.
exec /entrypoint.sh
