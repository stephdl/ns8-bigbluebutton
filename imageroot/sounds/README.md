# Vendored FreeSWITCH sound packs

German and French conference prompts, carried in the module image and bind-mounted
read-only into the FreeSWITCH container. Refresh them with
`dev/update-sound-packs.sh`, which records the pinned sources.

Only `conference/` is here: it holds every prompt `conference.conf.xml.tmpl` names.
Every other category is symlinked to the English pack at start time, by
`link_missing_folders` in the entrypoint — which does the same for the downloaded
packs, four of which carry no conference prompts at all.

`en/us/callie` is the reference set. Every other pack, vendored or downloaded, is a
partial recording, and a missing file plays as silence rather than as an error an
admin would notice.

| Pack | Voice | Licence | Source |
|---|---|---|---|
| `de/de/daedalus3` | — | MIT, see `LICENSE` | [Daedalus3/freeswitch-german-soundfiles](https://github.com/Daedalus3/freeswitch-german-soundfiles) at commit `1cd3083` |
| `fr/fr/sibylle` | Sibylle Luperce | CC BY-SA 3.0, see `COPYRIGHT` | [FrenchAudioFilesForFreeswitch](https://archive.org/details/FrenchAudioFilesForFreeswitch) 0.1.3, masters at [shimaore/fr-sounds](https://github.com/shimaore/fr-sounds) |

They are vendored rather than downloaded at run time because neither is safe to
depend on live: the German repository has no tag, so the entrypoint used to pull a
moving branch, and the French pack is published at 16/32/48 kHz on archive.org
alone. `files.freeswitch.org` has no European French at all.

`SHA256SUMS` covers the WAV files, not the upstream archives: codeload recompresses
tarballs on its own schedule, so an archive digest would churn while the recordings
stay byte-identical.

The other languages the module offers come from `files.freeswitch.org` and are
downloaded once into the `freeswitch-sounds` volume.
