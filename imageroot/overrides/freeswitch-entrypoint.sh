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

# Install the sound pack, unless the image already ships it.
#
# In a function so a failure here cannot take FreeSWITCH down with it: the script
# runs under bash -e, and a pack that will not download is a worse announcement,
# not a reason to leave a conference without an audio mixer.
#
# Every download says || return 1 for itself: bash suspends -e inside the
# condition of an if, so a silent failure would otherwise be reported as success.
SOUNDS_DIR=/opt/freeswitch/share/freeswitch/sounds

install_sounds() {
    case "$SOUNDS_LANGUAGE" in
    en-us-callie)
        return 0
        ;;
    de-de-daedalus3)
        [ -f "$SOUNDS_DIR/de-de-daedalus3.installed" ] && return 0
        echo "sounds package for de-de-daedalus3 not installed yet"
        # GitHub's tarball, not its zip: this image has no unzip.
        mkdir -p "$SOUNDS_DIR/de/de/daedalus3/conference" || return 1
        curl -fsSL "https://github.com/Daedalus3/freeswitch-german-soundfiles/archive/refs/heads/master.tar.gz" \
            | tar -xz --strip-components=1 -C "$SOUNDS_DIR/de/de/daedalus3/conference" \
            || return 1
        # This pack carries the conference prompts only.
        for folder in digits ivr misc; do
            ln -sfn "$SOUNDS_DIR/en/us/callie/$folder" "$SOUNDS_DIR/de/de/daedalus3/$folder"
        done
        touch "$SOUNDS_DIR/de-de-daedalus3.installed"
        ;;
    *)
        [ -f "$SOUNDS_DIR/$SOUNDS_LANGUAGE.installed" ] && return 0
        echo "sounds package for $SOUNDS_LANGUAGE not installed yet"

        # get filename of latest release for this sound package
        FILENAME=$(curl -s https://files.freeswitch.org/releases/sounds/ | grep -i $SOUNDS_LANGUAGE 2> /dev/null | awk -F'"' '{print $8}' | grep -E '\-48000-.*\.gz$' | sort -V | tail -n 1)

        if [ "$FILENAME" = "" ]; then
            echo "no sounds published for '$SOUNDS_LANGUAGE' on https://files.freeswitch.org/releases/sounds/" >&2
            return 1
        fi
        for bitrate in 8000 16000 32000 48000; do
            URL=https://files.freeswitch.org/releases/sounds/$(echo $FILENAME | sed "s/48000/$bitrate/")
            curl -fsSL "$URL" | tar -xz -C "$SOUNDS_DIR" || return 1
        done

        touch "$SOUNDS_DIR/$SOUNDS_LANGUAGE.installed"
        ;;
    esac
}

if install_sounds; then
    SOUNDS_PATH=$SOUNDS_DIR/$(echo "$SOUNDS_LANGUAGE" | sed 's|-|/|g')
else
    echo "keeping the English prompts the image ships" >&2
    SOUNDS_PATH=$SOUNDS_DIR/en/us/callie
fi

export SOUNDS_PATH

dockerize \
    -template /etc/freeswitch/vars.xml.tmpl:/etc/freeswitch/vars.xml \
    -template /etc/freeswitch/autoload_configs/conference.conf.xml.tmpl:/etc/freeswitch/autoload_configs/conference.conf.xml \
    /opt/freeswitch/bin/freeswitch -u freeswitch -g daemon -nonat -nf
