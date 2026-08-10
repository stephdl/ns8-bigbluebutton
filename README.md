# ns8-bigbluebutton

[BigBlueButton](https://bigbluebutton.org/) 3.0 for [NethServer 8](https://github.com/NethServer/ns8-core),
ported from the community [bigbluebutton/docker](https://github.com/bigbluebutton/docker)
compose stack.

Seventeen containers, a mediasoup SFU and a FreeSWITCH audio mixer, running
rootless under podman, with Greenlight as the front end.

A detailed gap analysis of what the port required, with references into the
upstream sources, is in [docs/packaging-analysis.md](docs/packaging-analysis.md).

## Requirements

- **One instance per node.** The module is labelled `max-per-node=1`. It asks
  the node for 9216 UDP ports, and an SFU plus an audio mixer saturate a node's
  CPU well before its ports.
- **A public IP address reachable over UDP.** WebRTC media does not travel over
  the Traefik HTTPS port. The allocated UDP range must be reachable from the
  internet; the firewall rule on the node itself is created automatically, but
  any router in front of it needs the range forwarded.
- **No TURN server is included.** Participants behind a firewall that blocks
  UDP cannot join unless you point the module at an external TURN server. See
  *STUN and TURN* below.
- **A certificate the browser trusts, matching the site hostname.** WebRTC only
  grants microphone and camera access in a secure context, so without one every
  participant meets a warning page and stays without a microphone or a camera
  until they accept it. Traefik's default self-signed certificate carries the
  node's name, not the site's, and no amount of trusting it helps: the failure
  is a hostname mismatch. Either publish the name and use Let's Encrypt, or
  issue a certificate from an internal CA whose chain Traefik accepts. Note
  that Traefik rejects a bare self-signed certificate on upload with
  `cert_verification_failed_chain`: it wants a verifiable chain.

  This affects the browser only. Greenlight's own server-side API calls do not
  depend on it: the pod's nginx answers for the site name on its internal 443
  with a certificate `configure-module` issues, and the Greenlight container
  resolves that name to `127.0.0.1` and trusts it. Rooms therefore start with
  or without a publicly trusted certificate.

## Sizing

BigBlueButton asks for 8 cores and 16 GB for a server of this shape. The stack
starts on less, and the first thing to run out is memory, not CPU.

**What the stack costs before anybody joins.** Measured on an idle instance with
two participants connected, the containers hold about 3.2 GB between them —
`bbb-web` 759 MB, `apps-akka` 398 MB, `etherpad` 393 MB, `fsesl-akka` 355 MB,
`webrtc-sfu` 353 MB, `bbb-graphql-server` 314 MB, the rest below 200 MB each.
Three JVMs, a Hasura engine, a Rails application and a Node SFU are running
whether or not a meeting is. On a 7.5 GB node that is 4.5 GB gone at rest.

**Cores.** The SFU forwards every video stream to every subscriber without
transcoding, and FreeSWITCH mixes the audio of everyone in a conference. Both
scale with participants, and neither parallelises beyond the workers it starts —
mediasoup runs one worker per core by default. Recording is the heaviest
consumer of all, and it is on by default: the post-processing competes with the
live meeting, so turning it off buys back noticeable capacity.

**Bandwidth is rarely the wall**, thanks to `cameraQualityThresholds`. Every
camera drops to 100 kbps once a meeting reaches 8 participants, then 90, 70, 50,
40 and 30 kbps at 12, 15, 20, 25 and 30. A 20-person meeting showing five
cameras each therefore costs about 20 × 5 × 50 kbps = 5 Mbps upstream, plus
roughly 40 kbps of mixed audio per participant. Do not tune those thresholds
away: an SFU multiplies every extra kbps by the number of receivers.

**Ports are never the wall.** The allocated 8192 mediasoup ports allow 4096
concurrent transports, since each binds one socket per announced address and this
module declares two. Memory and CPU are exhausted long before that.

**What to expect.** On 8 vCPU and 7.5 GB with recording off, somewhere around 25
to 40 participants with cameras, or 60 to 80 with audio only. Treat that as an
order of magnitude rather than a guarantee: it is reasoning from the measured
idle footprint and from how the components scale, **not** the result of a load
test. Doubling the memory to 16 GB moves the ceiling from RAM to CPU, which is
where upstream's own recommendation puts it.

The failure mode is not a refused connection. It is audio breaking up, cameras
freezing and clients reconnecting, so watch memory and load before the meeting
that matters rather than after.

## Architecture

Fourteen containers share one rootless pod, reachable only through the two
ports it publishes to the node loopback:

| | Containers |
|---|---|
| **Pod** | postgres, redis, bbb-web, nginx, greenlight, etherpad, bbb-pads, bbb-export-annotations, apps-akka, fsesl-akka, bbb-graphql-server, bbb-graphql-actions, bbb-graphql-middleware, recordings |
| **Host network** | freeswitch, webrtc-sfu, bbb-webrtc-recorder |

Inside the pod every peer resolves to `127.0.0.1` through `--add-host`.
BigBlueButton is natively a single-host product; the `10.7.7.x` addressing in
`bigbluebutton/docker` exists only to fit compose, and collapsing it back onto
one loopback restores the upstream shape. None of the fourteen services collide
on a port number, so nothing had to be renumbered.

FreeSWITCH is on the host network on purpose. It exchanges RTP with the SFU for
every conference audio leg, and the SFU cannot leave the host namespace. With
FreeSWITCH inside the pod that traffic had to be published port by port, which
put every audio packet through rootlessport in userspace.

### Ports

| | Range | Reachable from |
|---|---|---|
| mediasoup RTC | 8192 UDP, allocated | the internet |
| FreeSWITCH RTP | 1024 UDP, allocated | the node only |
| nginx, Redis | 2 TCP, allocated | the node loopback |
| FreeSWITCH ESL, SIP-over-WebSocket | 8021, 5066 | the node only |

Both UDP ranges come from a single allocation that `create-module/05setenvs`
splits. FreeSWITCH's upstream default of 16384-24576 is not used: it overlaps
the NS8 allocator span of 20000-45000 and is far wider than the SFU-to-FreeSWITCH
audio leg needs.

## Install

    add-module ghcr.io/stephdl/bigbluebutton:latest 1

The output returns the instance name:

    {"module_id": "bigbluebutton1", "image_name": "bigbluebutton", "image_url": "ghcr.io/stephdl/bigbluebutton:latest"}

## Configure

Assuming the instance is named `bigbluebutton1`:

```
api-cli run configure-module --agent module/bigbluebutton1 --data - <<EOF
{
  "host": "bbb.domain.com",
  "lets_encrypt": true,
  "public_address": "203.0.113.10",
  "private_address": "192.168.1.10",
  "stun_server": "",
  "turn_ext_server": "",
  "turn_ext_secret": "",
  "enable_recording": true,
  "recording_max_age_days": 30,
  "enable_learning_dashboard": true,
  "enable_external_videos": true,
  "enable_breakout_rooms": true,
  "learning_dashboard_max_age_days": 7,
  "sounds_language": "en-us-callie",
  "disable_sound_muted": false,
  "disable_sound_alone": false,
  "welcome_message": "",
  "welcome_footer": ""
}
EOF
```

Every field above is required, because the action rewrites the whole
configuration: a missing one would silently reset a setting instead of leaving it
alone. Read the current values with `api-cli run get-configuration`, change what
you need and send the result back.

Two fields are exempt, both because they cannot round-trip. `lets_encrypt`
defaults to `false` when omitted, which is what the restore and clone paths rely
on to avoid requesting a certificate for a name that does not resolve yet.
`turn_ext_secret` keeps its stored value when omitted, since `get-configuration`
returns only `turn_ext_secret_set`; send an empty string to clear it.

`host` is the fully qualified domain name of the web client. `public_address` is
what participants use to reach this node: it is *announced* to WebRTC clients, not
bound locally, so a public address is correct even behind NAT. Both addresses are
detected at install time and returned by `get-configuration`; the Settings page
also offers a re-detection.

HTTP is always redirected to HTTPS: BigBlueButton is unusable without it, so it
is not offered as a choice.

What each field does, and the value a fresh install carries:

| Parameter | Fresh install | Notes |
|---|---|---|
| `private_address` | detected | Set it when participants also connect from the LAN. The server then advertises both addresses, so internal clients connect directly instead of depending on NAT reflection. |
| `stun_server` | empty | See *STUN and TURN* below. A public STUN server receives the IP address of every participant. |
| `turn_ext_server` | empty | Without TURN, participants behind UDP-blocking firewalls cannot join. |
| `turn_ext_secret` | empty | The TURN server's shared secret. Mandatory with the above. Omit the field to keep the stored value; `get-configuration` returns only `turn_ext_secret_set`, never the secret. |
| `enable_recording` | `true` | Recordings capture audio, video, chat, shared notes and presentations. |
| `recording_max_age_days` | `0` | How long a recording stays available after the meeting. `0` keeps it forever, otherwise 1 to 180 days. Deletion goes through `bbb-record --delete`, so the database and the published tree stay consistent. |
| `sounds_language` | `en-us-callie` | Language of the spoken announcements. `en-us-callie` comes with the FreeSWITCH image, `de-de-daedalus3` and `fr-fr-sibylle` with this module (see `imageroot/sounds/README.md`); every other code is downloaded from `files.freeswitch.org` on first use and cached in the `freeswitch-sounds` volume. |
| `disable_sound_muted`, `disable_sound_alone` | `false` | Suppress the corresponding announcement. |
| `welcome_message`, `welcome_footer` | empty | Shown in the chat when a meeting starts. |
| `enable_learning_dashboard` | `true` | Moderators can open a dashboard reporting each participant's connection time, talking time, chat messages, raised emojis and poll answers. Access is by shared link, not by role: whoever holds the link can read it. |
| `enable_external_videos` | `true` | A moderator can play a YouTube or media URL in sync for everyone. The server relays nothing, but every participant's browser fetches it from the third party. |
| `enable_breakout_rooms` | `true` | Each breakout room is a full meeting of its own, so a split multiplies what the node carries. |
| `learning_dashboard_max_age_days` | `0` | How long a report stays readable after the meeting. `0` keeps it forever, otherwise 1 to 180 days. Upstream deletes it 2 minutes after the meeting ends, from a timer inside `bbb-web` that a restart loses; the maintenance job enforces this value instead. |

## STUN and TURN

This module ships no coturn, so it has no STUN and no TURN listener of its own.
`stun_server`, `turn_ext_server` and `turn_ext_secret` are all empty by default,
and the patched `turn-stun-servers.xml` omits each bean whose value is empty — the
client is handed an empty list rather than a candidate pointing at a port nothing
listens on.

**Media works without either.** mediasoup announces the node's public address and
the allocated UDP range is open, so the browser sends straight to the SFU, which
learns the browser's address from the packets it receives.

**What STUN buys.** Upstream describes it as being used "to allow direct UDP
connections through certain types of firewalls which otherwise might not work":
some NAT shapes need the client to discover its own reflexive address first. It
does nothing for a client whose firewall blocks outbound UDP altogether. That case
needs TURN, which relays the media, typically over TCP 443.

**Privacy is why both are empty.** A STUN server learns the IP address of every
participant that queries it, and upstream's `sample.env` points at a third-party
public one. Run your own instead: coturn answers STUN and TURN on the same port,
so a single server covers both.

**TURN needs its secret.** BigBlueButton supports one authentication mode —
`TurnServer.generatePasswordFor()` signs a short-lived credential with
`HMAC-SHA1(expiry:userId, secret)`, and the TURN server recomputes it from its own
`static-auth-secret`. Set `turn_ext_secret` to that value or every allocation is
refused. There is no username-and-password mode.

Value formats: `stun:turn.example.org:3478` and
`turns:turn.example.org:443?transport=tcp`.

Upstream references:

- [TURN server configuration](https://docs.bigbluebutton.org/administration/turn-server/)
  — coturn setup, the ports it needs, and the `turn-stun-servers.xml` beans this
  module patches
- [Trickle ICE](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/)
  — check from a browser that your server returns candidates
- `stunclient --mode full --localport 30000 turn.example.org 3478`, from the
  `stuntman-client` package, to test a STUN endpoint from a shell

## First sign-in

Greenlight's own start-up migrates the database but never seeds it, so a fresh
instance would have no administrator and its admin panel would be hidden from
everyone. The module creates a bootstrap account once Greenlight has finished
migrating:

| | |
|---|---|
| Email | `admin@nethserver.org` |
| Password | `Nethesis,1234` |

That password ships with this module, so it is known to anyone. Sign in, create
your own account, give it the Administrator role, then change or delete the
bootstrap one. The module checks the password on every `get-configuration` and
keeps warning in the UI until it is changed.

The account is only created when the instance has no administrator at all, so
deleting it once you have your own does not bring it back.

## Get the configuration

    api-cli run get-configuration --agent module/bigbluebutton1

Two read-only fields come back with it. `mediasoup_port_range` is the UDP range
that must be reachable from the internet. `certificate_matches_host` is `false`
when Traefik serves a certificate for another name, which the Settings page
reports rather than silently ignoring.

## Differences from upstream

The port is not a straight translation of `bigbluebutton/docker`. What changed,
and why:

- **coturn is dropped.** Its template hardcodes `turns:${DOMAIN}:443`, which
  collides with Traefik, and `turn:...:3478` is a fixed port that would force
  one instance per node for a protocol reason rather than a resource one.
  Upstream also emits the `turn0` bean unconditionally, with no `ENABLE_COTURN`
  guard, so without this fix every client would receive a TURN candidate for a
  port nothing listens on. Use `turn_ext_server` instead, and see *STUN and TURN*.
- **STUN is empty by default.** `sample.env` ships a third-party public STUN
  server, which would receive the IP address of every participant.
- **Greenlight is the front end**, served at the site root, and the module seeds
  a bootstrap administrator for it. The BigBlueButton API stays available for
  another front end to drive.
- **haproxy is replaced by Traefik**, and `periodic` by a systemd timer.
- **Collabora, webhooks and the Prometheus exporter are not included.**
- **SIP dial-in is disabled.** The `external-dialin` FreeSWITCH profile is
  removed, so port 5060 is never bound and does not collide with
  ns8-nethvoice-proxy on the same node.
- **Recordings produce the web player only, not MP4.** The `video` playback
  format is not built into the upstream recordings image.
- **The learning analytics dashboard is served its data.** The image's nginx
  points `/learning-analytics-dashboard/` at the app alone, while `bbb-web` writes
  each meeting's JSON to `/var/bigbluebutton/learning-dashboard`. Nothing served
  it, so the dashboard opened empty as soon as the meeting ended and the session
  token stopped working. This module adds the missing location.

## Maintenance timer

`bigbluebutton-periodic.timer` runs every 30 minutes and replaces the upstream
`periodic` container:

1. resynchronises the FreeSWITCH clock
2. seeds the bootstrap administrator, in case the database was not ready when
   Greenlight last started
3. deletes presentation upload directories older than 5 days
4. deletes learning dashboards past `learning_dashboard_max_age_days`, unless it
   is `0`
5. deletes recordings past `recording_max_age_days`, when `enable_recording` is
   set and the retention is not `0`

    systemctl --user status bigbluebutton-periodic.timer
    journalctl --user -u bigbluebutton-periodic.service

## Backup and restore

Backed up: the recordings volume, the `greenlight` PostgreSQL database, the raw
recorder output, the Greenlight uploads, and the generated secrets.

Not backed up: Redis, the per-meeting scratch volumes, and the two GraphQL
databases. Redis holds live meeting state and the recording job queues, which are
meaningless across a restore. The GraphQL databases are skipped for a blunter
reason: on every start `bbb-graphql-server` drops and recreates `bbb_graphql` from
its own schema, and reapplies `hasura_app`'s metadata from the image, so a copy of
either would be restored and overwritten seconds later.

**A restore therefore loses every in-progress meeting, and any recording still
queued for processing at backup time.** The raw media survives, but the job that
would have processed it does not.

## Uninstall

    remove-module --no-preserve bigbluebutton1

## Update

    api-cli run update-module --data '{"module_url":"ghcr.io/stephdl/bigbluebutton:latest","instances":["bigbluebutton1"],"force":true}'

Bump the BigBlueButton images as a set. Upstream does not support mixing
component versions, and the pinned tags in `build-images.sh` come from a single
`bigbluebutton/docker` reference.

## Debug

Inspect the module environment, including the allocated port ranges:

    runagent -m bigbluebutton1 env | grep -E 'PORT|IP'

Become the module user:

    runagent -m bigbluebutton1
    podman ps

Secrets are not in the environment. They live in `state/passwords.env`, mode
0600, because `agent.set_env()` writes to Redis in plain text where every module
on the node can read it.

Reach the FreeSWITCH console:

    runagent -m bigbluebutton1
    source state/passwords.env
    podman exec freeswitch /opt/freeswitch/bin/fs_cli -H 127.0.0.1 -p "$FSESL_PASSWORD"

Confirm the SFU is actually holding UDP ports. Match on the process rather than
on a port range: the sockets are unconnected, the local address is not always the
same column, and the recorder holds ports of its own outside the mediasoup range.

    ss -uanp | grep mediasoup

Expect nothing when no meeting is running — the ports are bound per stream and
released when it ends. With one meeting, two participants and three cameras the
count was 25, because each WebRTC transport binds one socket per entry in
`MS_WEBRTC_LISTEN_IPS`, and this module declares two.

## Testing

    ./test-module.sh <NODE_ADDR> ghcr.io/stephdl/bigbluebutton:latest

The tests use [Robot Framework](https://robotframework.org/).

## UI translation

Translated with [Weblate](https://hosted.weblate.org/projects/ns8/).
Only `ui/public/i18n/en/translation.json` is edited by hand; the other languages
are generated.
