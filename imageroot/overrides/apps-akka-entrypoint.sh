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

# Accepted by isLocaleValid() when the subtitles language follows the participant's
# browser: navigator.language must appear here verbatim, or recognition never starts
# and nothing says why. Hence the regional variants and the bare codes.
BROWSER_LOCALES='["de-DE","de-AT","de-CH","de","en-US","en-GB","en-AU","en-CA","en-IN","en","es-ES","es-MX","es-AR","es","fr-FR","fr-CA","fr-BE","fr-CH","fr","hi-IN","hi","it-IT","it","ja-JP","ja","nl-NL","nl-BE","nl","pt-BR","pt-PT","pt","ru-RU","ru","zh-CN","zh-TW","zh"]'

# A failure here is a worse default, not a broken room.
if [ -f "$SETTINGS" ]; then
    if ! yq e -i ".public.layout.hidePresentationOnJoin = $hide" "$SETTINGS"; then
        echo "apps-akka: could not set hidePresentationOnJoin, keeping the image default" >&2
    fi

    if [ "${ENABLE_AUDIO_CAPTIONS:-false}" = "true" ]; then
        language="${AUDIO_CAPTIONS_LANGUAGE:-browserLanguage}"
        if [ "$language" = "browserLanguage" ]; then
            available="$BROWSER_LOCALES"
        else
            available="[\"$language\"]"
        fi

        # forceLocale hides the language selector, and the client renders it only when
        # that flag is off. Leaving it off would let a speaker set their locale back to
        # "disabled", which is precisely what a participant reading the subtitles
        # cannot afford.
        # alwaysVisible seeds the CC button state at client start. Left false, a
        # participant has to find the button before any subtitle shows up, which
        # is not what someone who cannot hear needs. They can still hide them.
        if ! yq e -i ".public.app.audioCaptions.enabled = true
                | .public.app.audioCaptions.alwaysVisible = true
                | .public.app.audioCaptions.language.forceLocale = true
                | .public.app.audioCaptions.language.locale = \"$language\"
                | .public.app.audioCaptions.language.available = $available" "$SETTINGS"; then
            echo "apps-akka: could not enable audio captions, keeping the image default" >&2
        fi
    elif ! yq e -i ".public.app.audioCaptions.enabled = false" "$SETTINGS"; then
        echo "apps-akka: could not disable audio captions, keeping the image default" >&2
    fi
fi

# Spelled out, not "$@": --entrypoint clears the image CMD, and a wrapper handed
# nothing exits 0, which Restart=always turns into a crash loop.
exec /entrypoint.sh
