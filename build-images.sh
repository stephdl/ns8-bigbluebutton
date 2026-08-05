#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/nethserver}"
# Configure the image name
reponame="bigbluebutton"

#
# Image references, pinned. Keep them fully qualified: Renovate reads the
# org.nethserver.images label to open update PRs, and a floating tag gives it
# nothing to compare against.
#
# The alangecker/* tags come from bigbluebutton/docker repos/tags at ref d38784b
# (BigBlueButton 3.0.23). Bump them as a set: mixing BBB component versions is
# not supported upstream.
#
BBB_IMAGES=(
    "docker.io/alangecker/bbb-docker-web:v3.0.23"
    "docker.io/alangecker/bbb-docker-freeswitch:v1.10.12-v3.0.23"
    "docker.io/alangecker/bbb-docker-nginx:v3.0.23-v5.4.4-1.29"
    "docker.io/alangecker/bbb-docker-etherpad:2.4.2-s8328b77-p88f3f6b"
    "docker.io/alangecker/bbb-docker-pads:v1.5.8"
    "docker.io/alangecker/bbb-docker-bbb-export-annotations:v3.0.23"
    "docker.io/alangecker/bbb-docker-webrtc-sfu:v2.22.0"
    "docker.io/alangecker/bbb-docker-webrtc-recorder:v0.14.0"
    "docker.io/alangecker/bbb-docker-fsesl-akka:v3.0.23"
    "docker.io/alangecker/bbb-docker-apps-akka:v3.0.23"
    "docker.io/alangecker/bbb-docker-graphql-server:v3.0.23"
    "docker.io/alangecker/bbb-docker-graphql-actions:v3.0.23"
    "docker.io/alangecker/bbb-docker-graphql-middleware:v3.0.23"
    "docker.io/alangecker/bbb-docker-recordings:v3.0.23"
    "docker.io/bigbluebutton/greenlight:v3.8.2"
    "docker.io/library/postgres:16.14-alpine"
    "docker.io/library/redis:8.10.0-alpine"
)

# Create a new empty container image
container=$(buildah from scratch)

# Reuse existing nodebuilder-bigbluebutton container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-bigbluebutton; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-bigbluebutton -v "${PWD}:/usr/src:Z" docker.io/library/node:lts
fi

echo "Build static UI files with node..."
buildah run \
    --workingdir=/usr/src/ui \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    nodebuilder-bigbluebutton \
    sh -c "corepack enable && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui

#
# Port demands
#
# TCP (2): the only two ports the pod publishes to the node loopback -- nginx
# 48087 for Traefik, and Redis for the three host-network containers.
# FreeSWITCH's own ESL (8021) and SIP-over-WebSocket (5066) are NOT here: it
# runs in the host namespace and keeps those defaults, which sit below 20000,
# outside the allocator span.
#
# UDP (9216): one contiguous range, split at create time into
#   - the first 8192 ports  -> mediasoup RTC (public, declared in the firewall)
#   - the last  1024 ports  -> FreeSWITCH RTP (bound on the host, not public)
# FreeSWITCH upstream defaults to 16384-24576 (8193 ports), which overlaps the
# core allocator span 20000-45000 and is far more than the SFU<->FreeSWITCH
# audio leg needs: that leg uses one port per audio participant, not per stream.
# 1024 is provisional, see docs/packaging-analysis.md section 5 blocker 2.
#
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=node:fwadm traefik@node:routeadm" \
    --label="org.nethserver.tcp-ports-demand=2" \
    --label="org.nethserver.udp-ports-demand=9216" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.max-per-node=1" \
    --label="org.nethserver.volumes=bigbluebutton postgres-data greenlight" \
    --label="org.nethserver.min-core=3.20.1" \
    --label="org.nethserver.images=${BBB_IMAGES[*]}" \
    "${container}"

# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
