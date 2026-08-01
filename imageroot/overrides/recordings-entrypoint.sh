#!/bin/sh -e

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps /entrypoint.sh from the bbb-docker recordings image.
#
# The image ships a Ruby newer than its own scripts. File.exists? was removed
# from Ruby, and the recording pipeline still calls it, so every recording dies
# at the first worker that touches it:
#
#   ERROR -- : error in sanity check: undefined method `exists?' for File:Class
#   .../core/scripts/sanity/sanity.rb:53:in `check_events_xml'
#
# The recording is archived, then the sanity worker leaves a .fail marker and
# nothing else in the chain ever picks it up. Nothing is published, nothing
# reaches getRecordings, and the room's recordings list stays empty with no
# error surfaced anywhere the administrator would look.
#
# Patching in place rather than shipping copies of the scripts: they are
# upstream code that changes between releases, and a rename that the language
# itself forced is the whole of the difference. Once the image ships scripts
# that no longer call it, these substitutions match nothing and cost nothing.
#
# rap-process-worker.rb matters as much as sanity.rb here. Fixing only the
# sanity check would move the failure one stage down the pipeline rather than
# clear it.
#

for script in \
    /usr/local/bigbluebutton/core/scripts/sanity/sanity.rb \
    /usr/local/bigbluebutton/core/scripts/rap-process-worker.rb
do
    [ -f "$script" ] || continue
    sed -i -e 's/File\.exists?/File.exist?/g' -e 's/Dir\.exists?/Dir.exist?/g' "$script"
done

exec /entrypoint.sh
