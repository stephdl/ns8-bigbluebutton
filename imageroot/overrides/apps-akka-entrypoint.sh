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

# The default deck exists to give the whiteboard a surface, not to take the screen
# on join. A failure here is a worse default, not a broken room.
if [ -f "$SETTINGS" ]; then
    if ! yq e -i '.public.layout.hidePresentationOnJoin = true' "$SETTINGS"; then
        echo "apps-akka: could not set hidePresentationOnJoin, rooms will open on the presentation" >&2
    fi
fi

# Spelled out, not "$@": --entrypoint clears the image CMD, and a wrapper handed
# nothing exits 0, which Restart=always turns into a crash loop.
exec /entrypoint.sh
