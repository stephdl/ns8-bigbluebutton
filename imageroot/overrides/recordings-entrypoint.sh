#!/bin/sh -e

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker recordings image.
#
# The image ships a Ruby that removed File.exists?, which the pipeline still calls,
# so every recording dies and the room's list stays empty. Both scripts matter:
# patching only sanity.rb moves the failure one stage down.
#
# Patched in place, not copied: they change between releases, and the substitution
# matches nothing once upstream stops calling it.
#

for script in \
    /usr/local/bigbluebutton/core/scripts/sanity/sanity.rb \
    /usr/local/bigbluebutton/core/scripts/rap-process-worker.rb
do
    [ -f "$script" ] || continue
    sed -i -e 's/File\.exists?/File.exist?/g' -e 's/Dir\.exists?/Dir.exist?/g' "$script"
done

. /pod-trust-lib.sh

# The ready callback goes to Greenlight on the public name, so point it at the
# pod's own nginx: otherwise it dies on "certificate verify failed" and the
# recording never reaches a room's library.
pod_trust_add_host
pod_trust_refresh_ca "the ready callback may fail"

exec /entrypoint.sh
