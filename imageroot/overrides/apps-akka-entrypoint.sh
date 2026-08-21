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
# and nothing says why -- and forceLocale leaves the participant no selector to
# recover with. Hence the regional variants, the bare codes, and erring wide: an
# entry no browser reports costs nothing, a missing one costs the subtitles.
BROWSER_LOCALES='["ar-SA","bg-BG","ca-ES","cs-CZ","da-DK","de-AT","de-CH","de-DE","el-GR","en-AU","en-CA","en-GB","en-IE","en-IN","en-NZ","en-US","en-ZA","es-419","es-AR","es-CL","es-CO","es-ES","es-MX","et-EE","eu-ES","fi-FI","fr-BE","fr-CA","fr-CH","fr-FR","gl-ES","he-IL","hi-IN","hr-HR","hu-HU","id-ID","it-IT","ja-JP","ko-KR","lt-LT","lv-LV","nb-NO","nl-BE","nl-NL","pl-PL","pt-BR","pt-PT","ro-RO","ru-RU","sk-SK","sl-SI","sr-RS","sv-SE","th-TH","tr-TR","uk-UA","vi-VN","zh-CN","zh-HK","zh-TW","ar","bg","ca","cs","da","de","el","en","es","et","eu","fi","fr","gl","he","hi","hr","hu","id","it","ja","ko","lt","lv","nb","nl","pl","pt","ro","ru","sk","sl","sr","sv","th","tr","uk","vi","zh"]'

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
        # audioCaptions.alwaysVisible is deliberately left alone: in 3.0.23 it only
        # writes a Session key nothing reads any more, while the CC button state
        # comes from useAudioCaptionEnable, hardcoded to false. Each reader has to
        # turn the display on, once per join.
        if ! yq e -i ".public.app.audioCaptions.enabled = true
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
