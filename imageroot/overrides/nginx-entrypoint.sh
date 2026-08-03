#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /docker-entrypoint.sh from nginx.
#
# The HTML5 client ships settings.yml as 1200 lines of plain YAML with no
# templating of its own, so the one key we need is patched in place. Carrying a
# copy in this repository instead would mean re-diffing a 43 kB file against the
# image on every BigBlueButton bump, and silently losing any key upstream adds.
#

set -e

SETTINGS=/usr/share/bigbluebutton/html5-client/private/config/settings.yml

# Rooms open with the presentation collapsed. The default deck exists so the
# whiteboard has a surface when somebody asks for one, not so that it takes the
# screen the moment you join.
#
# Not fatal: a client that opens on the presentation is a worse default, not a
# broken room, and upstream renaming the key should not stop nginx from serving.
if [ -f "$SETTINGS" ]; then
    if ! sed -i 's/^\([[:space:]]*\)hidePresentationOnJoin:[[:space:]]*false[[:space:]]*$/\1hidePresentationOnJoin: true/' "$SETTINGS"; then
        echo "nginx: could not patch settings.yml, rooms will open on the presentation" >&2
    elif ! grep -q 'hidePresentationOnJoin: true' "$SETTINGS"; then
        echo "nginx: hidePresentationOnJoin not found in settings.yml, has it been renamed?" >&2
    fi
fi

# The image command is spelled out rather than forwarded as "$@": --entrypoint
# clears the image CMD, so the wrapper is handed nothing, and the nginx
# entrypoint would run its init and then exec an empty argument list - exiting 0
# a few milliseconds in, which Restart=always turns into a crash loop.
exec /docker-entrypoint.sh nginx -g 'daemon off;'
