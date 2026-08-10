#!/bin/bash
set -e -o pipefail

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Replaces /entrypoint.sh from alangecker/bbb-docker-freeswitch.
#
# Three differences from upstream, all needed to run rootless in a pod:
#
# 1. The iptables block for SIP 5060 is gone. Under `bash -e` a failing iptables
#    aborts before FreeSWITCH starts, and the rules would apply to the whole pod
#    namespace. SIP dial-in is out of scope, so it is dead code.
#
# 2. local_ip_v4 and the RTP range are patched in place rather than shipped as
#    file copies, so upstream changes still land. Upstream pins the compose bridge
#    address; the RTP default 16384-24576 overlaps the NS8 allocator span.
#
# 3. The external-dialin profile is removed: it binds 5060, which on the host
#    namespace collides with ns8-nethvoice-proxy. The external profile, which
#    carries the SIP-over-WebSocket transport the SFU uses, is left alone.
#

# Point FreeSWITCH at loopback: webrtc-sfu shares this network namespace and is
# the only peer that reaches FreeSWITCH over the network.
sed -i 's|data="local_ip_v4=[0-9.]*"|data="local_ip_v4=127.0.0.1"|' \
    /etc/freeswitch/vars.xml.tmpl

# The event socket binds loopback (see the local_ip_v4 rewrite above), but the
# stock inbound ACL is rfc1918.auto and 127.0.0.0/8 is not RFC1918 space, so
# every ESL client would be refused: fsesl-akka, webrtc-sfu and the maintenance
# timer alike, which silently breaks all conference audio. Upstream never hits
# this because its ESL listens on 10.7.7.10, which is RFC1918.
sed -i 's|"apply-inbound-acl" value="rfc1918.auto"|"apply-inbound-acl" value="loopback.auto"|' \
    /etc/freeswitch/autoload_configs/event_socket.conf.xml

# Never bind 5060: no SIP dial-in, and the port is contended on the host.
rm -f /etc/freeswitch/sip_profiles/external-dialin.xml
rm -rf /etc/freeswitch/sip_profiles/external-dialin

# Bind the RTP range the NS8 allocator reserved for us, instead of FreeSWITCH's
# default, which would overlap the allocator span and collide with other
# modules on this node.
if [ -n "$FS_RTP_MIN_PORT" ] && [ -n "$FS_RTP_MAX_PORT" ]; then
    sed -i \
        -e "s|<param name=\"rtp-start-port\" value=\"[0-9]*\"/>|<param name=\"rtp-start-port\" value=\"${FS_RTP_MIN_PORT}\"/>|" \
        -e "s|<param name=\"rtp-end-port\" value=\"[0-9]*\"/>|<param name=\"rtp-end-port\" value=\"${FS_RTP_MAX_PORT}\"/>|" \
        /etc/freeswitch/autoload_configs/switch.conf.xml
fi

mkdir -p /var/freeswitch/meetings
chown -R freeswitch:daemon /var/freeswitch/meetings
chmod 777 /var/freeswitch/meetings
chown -R freeswitch:daemon /opt/freeswitch/var
chown -R freeswitch:daemon /opt/freeswitch/etc
chmod -R g-rwx,o-rwx /opt/freeswitch/etc

# Resolve the sound pack, unless the image already ships it.
#
# In a function so a failure here cannot take FreeSWITCH down with it: the script
# runs under bash -e, and a pack that will not download is a worse announcement,
# not a reason to leave a conference without an audio mixer.
#
# Every download says || return 1 for itself: bash suspends -e inside the
# condition of an if, so a silent failure would otherwise be reported as success.
#
# Each branch sets SOUNDS_PATH itself: the German and French packs ship in the
# module image, the downloaded ones live in a volume, and the two roots differ.
SOUNDS_DIR=/opt/freeswitch/share/freeswitch/sounds
# Named volume. Without it a pack would be fetched again at every start: the unit
# runs podman run --replace with rm -f on stop, so the writable layer -- and the
# marker file that used to guard the download -- never survives a restart.
CACHE_DIR=/var/lib/freeswitch-sounds
SOUNDS_INDEX=https://files.freeswitch.org/releases/sounds/

# Neither vendored pack carries digits, ivr or misc. Borrowing the English ones is
# upstream's own compromise for German, kept here for both.
link_english_folders() {
    local root=$1 folder
    for folder in digits ivr misc; do
        ln -sfn "$SOUNDS_DIR/en/us/callie/$folder" "$root/$folder"
    done
}

# Unpack aside, then swap: a transfer cut halfway would otherwise leave truncated
# files where working prompts used to be. The caller keeps the old pack when this
# fails, so nothing here may touch the target before the last download lands.
download_pack() {
    local filename=$1 lang_path=$2 root=$3 bitrate url
    rm -rf "$CACHE_DIR/.staging"
    mkdir -p "$CACHE_DIR/.staging" || return 1
    for bitrate in 8000 16000 32000 48000; do
        url=$SOUNDS_INDEX$(echo "$filename" | sed "s/48000/$bitrate/")
        curl -fsSL "$url" | tar -xz -C "$CACHE_DIR/.staging" || return 1
    done
    mkdir -p "$(dirname "$root")" || return 1
    rm -rf "$root"
    mv "$CACHE_DIR/.staging/$lang_path" "$root" || return 1
    rm -rf "$CACHE_DIR/.staging"
    # FreeSWITCH itself runs as the freeswitch user, whatever modes the tarballs
    # carry.
    chmod -R a+rX "$root"
}

install_sounds() {
    local lang_path root version cached filename
    lang_path=$(echo "$SOUNDS_LANGUAGE" | sed 's|-|/|g')

    case "$SOUNDS_LANGUAGE" in
    en-us-callie)
        SOUNDS_PATH=$SOUNDS_DIR/en/us/callie
        return 0
        ;;
    de-de-daedalus3|fr-fr-sibylle)
        # Vendored in imageroot/sounds, bind-mounted read-only. The mount covers
        # conference/ alone so this directory stays writable for the symlinks.
        root=$SOUNDS_DIR/$lang_path
        if [ -z "$(ls -A "$root/conference" 2>/dev/null)" ]; then
            echo "no vendored sound pack mounted at $root/conference" >&2
            return 1
        fi
        link_english_folders "$root"
        SOUNDS_PATH=$root
        return 0
        ;;
    *)
        root=$CACHE_DIR/$lang_path
        SOUNDS_PATH=$root

        # The index costs ~200 kB against ~160 MB of tarballs, so read it at every
        # start and download only when upstream published a new version.
        filename=$(curl -fsS "$SOUNDS_INDEX" | grep -i "$SOUNDS_LANGUAGE" | awk -F'"' '{print $8}' | grep -E '\-48000-.*\.gz$' | sort -V | tail -n 1) || filename=""
        version=$(echo "$filename" | sed -E 's/.*-48000-(.*)\.tar\.gz$/\1/')
        cached=$(cat "$CACHE_DIR/.version-$SOUNDS_LANGUAGE" 2>/dev/null) || cached=""

        if [ -z "$filename" ]; then
            # A slightly stale pack beats dropping the configured language because
            # the index was briefly unreachable.
            if [ -d "$root" ]; then
                echo "sounds index unreachable, keeping the cached $SOUNDS_LANGUAGE pack ($cached)" >&2
                return 0
            fi
            echo "no sounds published for '$SOUNDS_LANGUAGE' on $SOUNDS_INDEX" >&2
            return 1
        fi

        [ "$version" = "$cached" ] && [ -d "$root" ] && return 0

        echo "installing sound pack $SOUNDS_LANGUAGE $version"
        if download_pack "$filename" "$lang_path" "$root"; then
            echo "$version" > "$CACHE_DIR/.version-$SOUNDS_LANGUAGE"
            # One language at a time: each pack runs to ~160 MB.
            find "$CACHE_DIR" -mindepth 3 -maxdepth 3 -type d ! -path "$root" -exec rm -rf {} +
            find "$CACHE_DIR" -mindepth 1 -maxdepth 2 -type d -empty -delete
            find "$CACHE_DIR" -maxdepth 1 -type f -name '.version-*' ! -name ".version-$SOUNDS_LANGUAGE" -delete
            return 0
        fi
        # Leave nothing half-downloaded behind: staging can hold ~160 MB.
        rm -rf "$CACHE_DIR/.staging"
        # A version bump that fails is no reason to lose a pack that still works.
        if [ -d "$root" ]; then
            echo "cannot install $SOUNDS_LANGUAGE $version, keeping the cached pack ($cached)" >&2
            return 0
        fi
        return 1
        ;;
    esac
}

if ! install_sounds; then
    echo "keeping the English prompts the image ships" >&2
    SOUNDS_PATH=$SOUNDS_DIR/en/us/callie
fi

export SOUNDS_PATH

dockerize \
    -template /etc/freeswitch/vars.xml.tmpl:/etc/freeswitch/vars.xml \
    -template /etc/freeswitch/autoload_configs/conference.conf.xml.tmpl:/etc/freeswitch/autoload_configs/conference.conf.xml \
    /opt/freeswitch/bin/freeswitch -u freeswitch -g daemon -nonat -nf
