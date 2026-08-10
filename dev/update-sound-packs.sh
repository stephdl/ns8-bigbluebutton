#!/bin/bash

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

#
# Refreshes the FreeSWITCH sound packs vendored under imageroot/sounds/. This
# script is a maintainer tool and is not shipped in the module image -- the WAV
# files it writes are.
#
# Neither upstream publishes a tag or a release, so Renovate has nothing to
# follow: running this script, reviewing the diff and committing is the update
# path for both languages.
#
# German is pinned to a commit because the upstream entrypoint pulled a moving
# branch, whose content could change with no signal.
#
# French exists nowhere else: the 16/32/48 kHz tarballs are hosted only on
# archive.org, and Alpine packages the 8000 one alone. If archive.org ever goes,
# rebuild the rates from the 96 kHz masters in
# https://github.com/shimaore/fr-sounds -- its wav/build.sh resamples all four
# with sox.
#

set -e -o pipefail

DE_COMMIT=1cd3083ece30e6d3726b91b8cde03e6247a32113
FR_VERSION=0.1.3
RATES=(8000 16000 32000 48000)

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
sounds_dir="${repo_dir}/imageroot/sounds"
work_dir=$(mktemp -d)
trap 'rm -rf "${work_dir}"' EXIT

#
# Only conference/ is vendored, for both packs: it holds every prompt this
# image's conference.conf.xml.tmpl names. The entrypoint symlinks digits, ivr
# and misc to the English pack, as upstream already did for German.
#

echo "Fetching de-de-daedalus3 at ${DE_COMMIT}"
curl -fsSL "https://github.com/Daedalus3/freeswitch-german-soundfiles/archive/${DE_COMMIT}.tar.gz" \
    | tar -xz -C "${work_dir}"
de_src="${work_dir}/freeswitch-german-soundfiles-${DE_COMMIT}"
de_dst="${sounds_dir}/de/de/daedalus3"
rm -rf "${de_dst}"
# Upstream keeps the rate directories at the archive root; FreeSWITCH resolves
# them below conference/.
for rate in "${RATES[@]}"; do
    mkdir -p "${de_dst}/conference/${rate}"
    cp "${de_src}/${rate}"/*.wav "${de_dst}/conference/${rate}/"
done
cp "${de_src}/LICENSE" "${de_dst}/LICENSE"

echo "Fetching fr-fr-sibylle ${FR_VERSION}"
fr_dst="${sounds_dir}/fr/fr/sibylle"
rm -rf "${fr_dst}"
mkdir -p "${fr_dst}"
for rate in "${RATES[@]}"; do
    # One tarball per rate, each carrying the whole tree: ask tar for the
    # conference directory alone rather than unpacking ~120 MB into /tmp.
    curl -fsSL "https://archive.org/download/FrenchAudioFilesForFreeswitch/freeswitch-sounds-fr-fr-sibylle-${rate}-${FR_VERSION}.tar.gz" \
        | tar -xz -C "${work_dir}" --wildcards "fr/fr/sibylle/conference/${rate}/*.wav"
    mkdir -p "${fr_dst}/conference/${rate}"
    cp "${work_dir}/fr/fr/sibylle/conference/${rate}"/*.wav "${fr_dst}/conference/${rate}/"
done
# CC BY-SA 3.0: the attribution and licence text travel with the recordings.
curl -fsSL "https://archive.org/download/FrenchAudioFilesForFreeswitch/freeswitch-sounds-fr-fr-sibylle-48000-${FR_VERSION}.tar.gz" \
    | tar -xz -C "${work_dir}" "fr/fr/sibylle/README" "fr/fr/sibylle/COPYRIGHT"
cp "${work_dir}/fr/fr/sibylle/README" "${work_dir}/fr/fr/sibylle/COPYRIGHT" "${fr_dst}/"

# Checksums of the vendored files, not of the archives: codeload recompresses
# tarballs on its own schedule, so an archive digest would churn while the
# recordings stay identical.
( cd "${sounds_dir}" && find . -name '*.wav' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS )

chmod 0644 "${sounds_dir}/SHA256SUMS"
find "${sounds_dir}" -type f -name '*.wav' -exec chmod 0644 {} +
find "${sounds_dir}" -type d -exec chmod 0755 {} +

printf 'Vendored %s WAV files\n' "$(grep -c '' "${sounds_dir}/SHA256SUMS")"
du -sh "${de_dst}" "${fr_dst}"
