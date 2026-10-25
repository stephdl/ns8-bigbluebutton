# Moving to BigBlueButton 4

Status: analysis only, October 2026. Nothing here is implemented yet.

## In short

BigBlueButton 4.0.0 came out on 14 October 2026. We are not ready to ship it.

The module runs the container images built by the bigbluebutton/docker project. That project has a `bbb4` branch, but it only started on 21 October 2026. No 4.0 image is published on Docker Hub yet, and the media service it uses is still a beta. We wait for those images first.

The big change in 4.0 is the media server. LiveKit now carries audio, cameras and screen sharing. FreeSWITCH and mediasoup are gone from the docker images. Shared notes also change: Etherpad is removed and replaced by a new notes service.

For us, this means four services go away and two new ones come in. The UDP port layout changes, one TCP port is added, and a few settings in the UI no longer make sense.

An in-place update from 3.x is possible. Users do not need to reinstall. Greenlight data, the database and old recordings stay as they are. What is lost on update is small: notes of meetings running at that moment, and the FreeSWITCH sound announcement options.

The update script is the largest piece of work. It must be tested from a real 3.x install before we propose anything.

## What changes upstream

LiveKit is the new default media server. The official packages keep FreeSWITCH and mediasoup as an option, but the docker images do not ship them anymore.

Etherpad and bbb-pads are removed. Shared notes now run on `bbb-shared-notes-server`, which stores notes in Postgres. Old Etherpad pads are not converted.

A few things are removed from the API and the config: the `/api/rest/clientSettings` endpoint, `sharedNotesEditor`, `notes_endpoint` in the recording config, and the old layouts (`CUSTOM_LAYOUT`, `SMART_LAYOUT` and so on).

## What we must change in the module

Images. Drop freeswitch, fsesl-akka, etherpad and pads. Add `livekit/livekit-server` and `alangecker/bbb-shared-notes-server`. Bump everything else to the 4.0 tags as one set.

Services. Remove the four matching systemd units. Add a LiveKit unit on the host network, like webrtc-sfu, and a shared notes unit inside the pod.

Ports. Keep the same 9216 UDP ports, so existing installs keep their range. Split them as 8192 for LiveKit and 1024 for the eturnal relay. LiveKit also needs one TCP port for its signaling, so `tcp-ports-demand` goes from 2 to 3.

TURN. The upstream LiveKit config sets no TURN server. We must point LiveKit to our eturnal, or users behind strict firewalls lose audio and video.

Settings. The sound language and the "muted" and "alone" announcements belong to FreeSWITCH. With LiveKit only the mute alert remains, and it lives in the browser client. The UI and the configure action must change, but the action must still accept the old fields so restores of 3.x backups keep working.

Update script. It must create the new LiveKit secret, recompute the ports, clean Etherpad keys from Redis and drop old environment variables.

## Open questions

Can NS8 give one more TCP port to a module that is already installed, when the demand goes from 2 to 3? If not, LiveKit signaling must share one of the two existing ports.

Does LiveKit accept a TURN REST shared secret, as eturnal uses, or only fixed credentials?

Is Greenlight 3.9 fully compatible with BigBlueButton 4.0? Probably yes, but not checked.

## Suggested order

First, build or wait for the 4.0 images. Then wire LiveKit, webrtc-sfu, nginx and the ports, and test calls on a lab node. Then switch shared notes. Then remove FreeSWITCH and clean the UI. Write the update script last, and test it from an installed 3.x.

## Details

### Sources

- bigbluebutton/docker, branch `bbb4`, commit `74c67d2` (21 October 2026), compared with tag `v3.0.39`.
- bigbluebutton/bigbluebutton tag `v4.0.0`, files `docs/docs/new-features.md`, `docs/docs/administration/configure-firewall.md` and `docs/docs/administration/customize.md`.
- Docker Hub tags of `alangecker/*` checked on 25 October 2026. The newest is v3.0.39 and no v4 tag exists.

### Upstream versions in `bbb4` (`repos/tags`)

```
repos/bbb-playback v5.4.7
repos/bbb-webhooks v3.7.0
repos/bbb-webrtc-recorder v0.14.0
repos/bbb-webrtc-sfu v2.25.0-beta.2
repos/bigbluebutton v4.0.0
repos/freeswitch v1.11.3
```

The compose file uses `livekit/livekit-server:v1.13.10` and `redis:8.10-alpine`.

### Upstream compose changes (v3.0.39 to bbb4)

- `freeswitch` and `fsesl-akka` services removed.
- `etherpad` and `bbb-pads` removed, along with the `USE_INSECURE_ETHERPAD` switch.
- `livekit` added with `network_mode: host`, config in `mod/livekit/livekit.yaml` and `LIVEKIT_KEYS: "bbb: ${LIVEKIT_SECRET}"`.
- `webrtc-sfu` gets `LIVEKIT_SECRET` and `MEDIA_SERVER_ADAPTERS: "[]"`. It loses `ESL_PASSWORD`, `MS_WEBRTC_LISTEN_IPS`, host networking and the io_uring settings.
- `bbb-shared-notes-server` uses the image `alangecker/bbb-shared-notes-server:${TAG_BBB}` and depends on redis, postgres and bbb-web.
- Env: `ETHERPAD_API_KEY`, `FSESL_PASSWORD`, `SOUNDS_LANGUAGE`, `DISABLE_SOUND_MUTED` and `DISABLE_SOUND_ALONE` removed. `LIVEKIT_SECRET` added.

### Upstream config file changes

- `webrtc-sfu/config.yaml`: the `freeswitch` and `mediasoup` blocks are removed. A new block is added:

  ```yaml
  livekit:
    enabled: true
    host: http://10.7.7.1:7880
    bbbDomain: BBB_DOMAIN
    tokenTTL: 14400
    key: bbb
  ```

- `livekit/livekit.yaml`: port 7880, RTC range 16384-32768, `tcp_port: 0`, `allow_tcp_fallback: false`, `interfaces.excludes: [docker0]`, Redis, a webhook to `http://webrtc-sfu:3040/livekit-webhook` with `api_key: bbb`, audio levels, and codecs opus, red, vp8 and rtx. No TURN servers are set.
- `nginx/bbb/livekit.nginx`: `location /livekit/` proxies WebSocket traffic to port 7880.
- `nginx/bbb/graphql.nginx`: `/api/rest/clientSettings` is removed.
- `nginx/bbb/bbb-shared-notes-server.nginx`: adds the `Meeting-Name` and `Meeting-Create-Time` headers from `auth_request`.
- `bbb-web.properties`: `sharedNotesEditor` is removed.
- `bbb-web/entrypoint.sh`: the classpath becomes `-cp .`.
- `recordings/recording.yml`: `notes_endpoint` is removed. Notes are now read from `bn_notes_endpoint`, which defaults to `http://127.0.0.1:8787/loopback/api/documents`.
- `base-java`: `MALLOC_ARENA_MAX=2`.
- `apps-akka/entrypoint.sh` still sets `public.pads.url`, which 4.0 removes.

### Notes from the official 4.0 docs

- Per meeting, a media type can go back to the old stack with `audioBridge=bbb-webrtc-sfu` (or `freeswitch`), `cameraBridge` or `screenShareBridge`. This does not help us, since the docker images ship no FreeSWITCH.
- The docs strongly recommend `rtc.interfaces.includes` in livekit.yaml. Without it, recent LiveKit versions can cause CPU spikes.
- Firewall: UDP 16384-32768 is used by LiveKit. Signaling goes through HTTPS on 443 via nginx.
- With LiveKit audio, the mute sound is controlled in `bbb-html5.yml` with `public.app.defaultSettings.application.muteUnmuteAudioAlerts`.
- `public.media.audio.defaultFullAudioBridge` and `defaultListenOnlyBridge` now default to `livekit`.
- Phone dial-in uses `livekit-sip`, which is not in bbb-docker. The module does not offer dial-in today.

### Files touched in this repo

- `build-images.sh`: image list, `tcp-ports-demand`, port comments.
- `imageroot/systemd/user/`: remove `freeswitch.service`, `fsesl-akka-app.service`, `etherpad-app.service` and `bbb-pads-app.service`. Add `livekit.service` and `bbb-shared-notes-server-app.service`. Update `Requires`, `After` and `--add-host` in `bigbluebutton.service` and `recordings-app.service`.
- `imageroot/bin/apply-port-layout`: new split, LiveKit then the TURN relay. Drop the FreeSWITCH RTP range.
- `imageroot/overrides/`: new `livekit.yaml.in`. Update `webrtc-sfu-config.yaml.in`, `nginx.conf.in`, `bbb-web.properties.tmpl`, `bbb-web-entrypoint.sh` and `apps-akka-entrypoint.sh`. Drop `freeswitch-entrypoint.sh` and `turn-stun-servers.xml` if they are only used by FreeSWITCH.
- `imageroot/bin/generate-secrets` and `update-module.d/05secrets`: add `LIVEKIT_SECRET`, drop `FSESL_PASSWORD` and `ETHERPAD_API_KEY`.
- `imageroot/bin/bigbluebutton-periodic`: drop the FreeSWITCH clock resync if present.
- `imageroot/bin/detect-addresses`, `turn-relay-address`, `etc/state-include.conf`: drop FreeSWITCH and Etherpad references.
- `imageroot/sounds/`: the French FreeSWITCH sounds are no longer used.
- `imageroot/actions/configure-module/validate-input.json`, `10configure_environment_vars`, `get-configuration`, `ui/src/views/Settings.vue`: rework the sound settings. Map `disable_sound_muted` to `muteUnmuteAudioAlerts` and keep accepting the old fields.
- `update-module.d/`: new secret, ports, Redis cleanup of Etherpad keys (`pad:*`, `globalAuthor:*`, and so on), removal of old env variables.
- `tests/bigbluebutton.robot`, `README.md`, `docs/`: port range and component list.
