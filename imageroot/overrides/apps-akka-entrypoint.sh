#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker apps-akka image.
#
# This container owns the HTML5 client's settings, which is not obvious: nginx
# serves the client bundle and carries its own copy of settings.yml, but nothing
# reads it. apps-akka is what clientSettingsFilePath points at, and what fills
# meeting_clientSettings for Hasura to serve.
#

set -e

SETTINGS=/usr/share/bigbluebutton/html5-client/private/config/settings.yml

# Rooms open with the presentation collapsed: the default deck is there to give
# the whiteboard a surface, not to take the screen on join. Not fatal if it
# fails -- a worse default, not a broken room.
if [ -f "$SETTINGS" ]; then
    if ! yq e -i '.public.layout.hidePresentationOnJoin = true' "$SETTINGS"; then
        echo "apps-akka: could not set hidePresentationOnJoin, rooms will open on the presentation" >&2
    fi
fi

# Spelled out rather than forwarded as "$@": --entrypoint clears the image CMD,
# so a wrapper handed nothing execs an empty argument list and exits 0 -- which
# Restart=always turns into a crash loop.
exec /entrypoint.sh
