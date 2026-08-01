#!/bin/bash -e

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Replaces /entrypoint.sh from alangecker/bbb-docker-freeswitch.
#
# Two differences from upstream, both required to run rootless inside a pod:
#
# 1. The upstream entrypoint opens with an iptables block that flushes and
#    re-adds INPUT rules for SIP port 5060. It cannot run here: the script is
#    `bash -e`, so a failing iptables aborts before FreeSWITCH starts, and the
#    rules would apply to the whole shared pod network namespace rather than to
#    FreeSWITCH alone. SIP dial-in is out of scope for this module, so the block
#    is dead code and is simply gone.
#
# 2. Two config values are patched in place rather than shipped as full file
#    copies, so upstream changes to those files are still picked up:
#      - vars.xml.tmpl pins local_ip_v4 to the compose bridge address 10.7.7.10;
#        here webrtc-sfu shares this namespace and reaches us on loopback.
#      - switch.conf.xml defaults the RTP range to 16384-24576, which overlaps
#        the NS8 port allocator span and is far wider than the
#        SFU<->FreeSWITCH audio leg needs.
#
# 3. The external-dialin SIP profile is removed. It binds port 5060, which on
#    the host network namespace would collide with ns8-nethvoice-proxy on the
#    same node. SIP dial-in is out of scope for this module, so the profile has
#    no purpose here. The external profile, which carries the
#    SIP-over-WebSocket transport the SFU actually uses, is left alone.
#
# The sounds-package logic below is kept verbatim from upstream.
#

# Point FreeSWITCH at loopback: webrtc-sfu shares this network namespace and is
# the only peer that reaches FreeSWITCH over the network.
sed -i 's|data="local_ip_v4=[0-9.]*"|data="local_ip_v4=127.0.0.1"|' \
    /etc/freeswitch/vars.xml.tmpl

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

# install freeswitch sounds if missing
SOUNDS_DIR=/opt/freeswitch/share/freeswitch/sounds
if [ "$SOUNDS_LANGUAGE" == "en-us-callie" ]; then
    # default, is already installed
    echo ""
elif [ "$SOUNDS_LANGUAGE" == "de-de-daedalus3" ]; then
    if [ ! -d "$SOUNDS_DIR/de/de/daedalus3" ]; then
        echo "sounds package for de-de-daedalus3 not installed yet"
        wget -O /tmp/freeswitch-german-soundfiles.zip https://github.com/Daedalus3/freeswitch-german-soundfiles/archive/master.zip
        mkdir -p $SOUNDS_DIR/de/de/daedalus3
        unzip /tmp/freeswitch-german-soundfiles.zip -d /tmp/
        mv /tmp/freeswitch-german-soundfiles-master $SOUNDS_DIR/de/de/daedalus3/conference

        # symlink other folders
        for folder in "digits" "ivr" "misc"; do
            ln -s $SOUNDS_DIR/en/us/callie/$folder $SOUNDS_DIR/de/de/daedalus3/$folder
        done

    fi
else
    if [ ! -f $SOUNDS_DIR/$SOUNDS_LANGUAGE.installed ]; then
        echo "sounds package for $SOUNDS_LANGUAGE not installed yet"

        # get filename of latest release for this sound package
        FILENAME=$(curl -s https://files.freeswitch.org/releases/sounds/ | grep -i $SOUNDS_LANGUAGE 2> /dev/null | awk -F'\"' '{print $8}' | grep -E '\-48000-.*\.gz$' | sort -V | tail -n 1)

        if [ "$FILENAME" = "" ]; then
            echo "Error: could not find sounds for language '$SOUNDS_LANGUAGE'"
            echo "make sure to specify a value for SOUNDS_LANGUAGE which exists on https://files.freeswitch.org/releases/sounds/"
            exit 1
        fi
        for bitrate in 8000 16000 32000 48000; do
            URL=https://files.freeswitch.org/releases/sounds/$(echo $FILENAME | sed "s/48000/$bitrate/")
            wget -O /tmp/sounds.tar.gz $URL
            tar xvfz /tmp/sounds.tar.gz -C $SOUNDS_DIR
        done

        touch $SOUNDS_DIR/$SOUNDS_LANGUAGE.installed
    fi
fi


export SOUNDS_PATH=$SOUNDS_DIR/$(echo "$SOUNDS_LANGUAGE" | sed 's|-|/|g')

dockerize \
    -template /etc/freeswitch/vars.xml.tmpl:/etc/freeswitch/vars.xml \
    -template /etc/freeswitch/autoload_configs/conference.conf.xml.tmpl:/etc/freeswitch/autoload_configs/conference.conf.xml \
    /opt/freeswitch/bin/freeswitch -u freeswitch -g daemon -nonat -nf
