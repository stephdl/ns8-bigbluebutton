#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker apps-akka image.
#
# This container owns the HTML5 client's settings, which is not obvious: nginx
# serves the client bundle and carries its own copy of settings.yml, but that
# copy is inert. apps-akka reads the file named by clientSettingsFilePath in
# /bbb-apps-akka/conf/application.conf and writes the result per meeting into
# meeting_clientSettings in the bbb_graphql database, which Hasura then serves to
# the client at /api/rest/meetingStaticData. Editing nginx's copy changes nothing
# that anybody reads -- its wsUrl is still the literal "HOST" placeholder while
# the database row carries the substituted one.
#
# The one key patched here is also why the image's own settings.yml is edited in
# place rather than a copy carried in this repository: that file is 1200 lines of
# plain YAML with no templating, and it changes with every BigBlueButton release.
#

set -e

SETTINGS=/usr/share/bigbluebutton/html5-client/private/config/settings.yml

# Rooms open with the presentation collapsed. The default deck exists so the
# whiteboard has a surface when somebody asks for one, not so that it takes the
# screen the moment you join.
#
# Not fatal: a room that opens on the presentation is a worse default, not a
# broken room, and upstream renaming the key should not stop the stack from
# starting.
if [ -f "$SETTINGS" ]; then
    if ! yq e -i '.public.layout.hidePresentationOnJoin = true' "$SETTINGS"; then
        echo "apps-akka: could not set hidePresentationOnJoin, rooms will open on the presentation" >&2
    fi
fi

# The image entrypoint runs its own yq over the same file, for wsUrl and
# pads.url. Different keys, so the order between the two passes is irrelevant,
# and --replace recreates this container from the image on every start: the file
# is pristine each time and each pass applies exactly once.
#
# The command is spelled out rather than forwarded as "$@". The image entrypoint
# is `/bin/sh -c /entrypoint.sh` with an empty CMD, and --entrypoint clears the
# image CMD, so a wrapper forwarding "$@" would exec an empty argument list and
# exit 0 milliseconds in -- which Restart=always turns into a crash loop.
exec /entrypoint.sh
