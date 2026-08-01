# BigBlueButton 3.0 → NS8 packaging gap analysis

Read-only analysis. Every claim points at `path:line`. Anything the code did not settle is
in section 8.

> **Status.** This was written before any code, to plan the port. It has since been
> reconciled with what was actually shipped: FreeSWITCH runs in the host network namespace
> rather than in the pod, which changes sections 2b, 3, 4 and blocker 2. The reasoning that
> led there is kept rather than rewritten, because the wrong turn is the useful part.

## Sources read

| Repo | Ref | Local path |
|---|---|---|
| `bigbluebutton/docker` | `d38784b` (2026-03-24, "Update version to 3.0.23") | `~/dev/git_work/bigbluebutton-docker` |
| `bigbluebutton/bigbluebutton` | `v3.0.x-release`, sparse: `bbb-graphql-server`, `bbb-common-web`, `bbb-voice-conference`, `record-and-playback` | `~/dev/git_work/bigbluebutton` |
| `bigbluebutton/bbb-webrtc-sfu` | default branch | `~/dev/git_work/bbb-webrtc-sfu` |
| `ns8-core`, `ns8-mail`, `ns8-nextcloud`, `ns8-nethvoice`, `ns8-nethvoice-proxy`, `ns8-kickstart-postgresql` | working copies | `~/dev/git_work/` |

`bbb-webrtc-sfu` had to be cloned separately: the mediasoup adapter cited in the brief is not
vendored in `bigbluebutton/docker` (`mod/webrtc-sfu/` contains only `Dockerfile` and
`config.yaml`).

## Corrections to the brief

Stated up front, as required, rather than worked around silently.

1. **Scope is 16 containers, not 15.** The brief's own list enumerates sixteen names. Counted
   against `docker-compose.tmpl.yml`, the unconditional services are fifteen (`bbb-web`,
   `freeswitch`, `nginx`, `etherpad`, `bbb-pads`, `bbb-export-annotations`, `redis`,
   `webrtc-sfu`, `fsesl-akka`, `apps-akka`, `bbb-graphql-server`, `bbb-graphql-actions`,
   `bbb-graphql-middleware`, `periodic`, `postgres`), of which `periodic` is excluded, plus
   `recordings` and `bbb-webrtc-recorder` which are gated on `ENABLE_RECORDING`
   (`docker-compose.tmpl.yml:427-474`). 15 − 1 + 2 = **16**.

2. **`turn1` has a two-term guard, not one.** The brief says `turn1` is guarded by
   `ENABLE_HTTPS_PROXY`. It is guarded by `ENABLE_HTTPS_PROXY` **and** `not IGNORE_TLS_CERT_ERRORS`
   (`mod/bbb-web/turn-stun-servers.xml:17`, repeated at `:45`).

3. **The `STUN_IP` default is misleading evidence.** `sample.env:73` does hardcode
   `216.93.246.18`, but `scripts/setup:130` rewrites it:
   `sed -i "s/.*STUN_IP=.*/STUN_IP=$EXTERNAL_IPv4/" .env`. Any actually-installed upstream
   deployment points STUN at its own coturn, not at a third party.

4. **The UDP appetite is 16385 ports upstream, not 8192.** mediasoup takes 24577–32768
   (`bbb-webrtc-sfu/config/default.example.yml:417-418`) and FreeSWITCH takes 16384–24576
   (`bigbluebutton/bbb-voice-conference/config/freeswitch/conf/autoload_configs/switch.conf.xml:147-148`).
   Decision 5 accounts only for the first. See section 3.

5. **FreeSWITCH's RTP range collides with the NS8 core allocator.** 16384–24576 overlaps
   20000–45000 (`ns8-core/core/imageroot/usr/local/agent/pypkg/node/ports_manager.py:69-70`)
   over 20000–24576. This only bites if FreeSWITCH ends up in the host netns — see section 5,
   blocker 2.

6. **The brief's Q3 premise is incomplete.** Two ports published to loopback (nginx, Redis) do
   not suffice. `webrtc-sfu` also needs FreeSWITCH's ESL, its SIP-over-WebSocket port, and its
   whole RTP range. See section 2.

7. **`mod/freeswitch/entrypoint.sh` runs `iptables`.** Not mentioned in the brief and a
   first-order rootless concern (`mod/freeswitch/entrypoint.sh:4-16`). See section 5, blocker 3.

8. **`mod/livekit/` exists in the checkout** but no `livekit` service appears in
   `docker-compose.tmpl.yml`. Dead weight at this ref; ignore.

9. **Decision 5 names the wrong mechanism.** NS8 allocates UDP ports *declaratively*, at
   install time, from a container label — not from a `create-module` call. See section 9a.

10. **Publishing FreeSWITCH's RTP range to host loopback re-introduces the collision that
    keeping FreeSWITCH in the pod was supposed to avoid.** See section 5, blocker 2, revised.

Decision 5's underlying claims were verified and hold: `agent.allocate_ports` exists at
`ns8-core/core/imageroot/usr/local/agent/pypkg/agent/__init__.py:730`; allocator span
20000–45000 at `ports_manager.py:69-70`; `install-core.sh:39` sets only
`net.ipv4.ip_unprivileged_port_start=23`, `user.max_user_namespaces=28633`,
`net.ipv4.ip_forward=1`. The correction in item 9 is about *which* entry point to use, not
about the allocator itself — both paths reach the same `node.ports_manager`.

---

## 1. What the existing NS8 modules give us, and what they do not

### Given

**The pod idiom is a direct fit, and better than the brief assumes.**
`ns8-nextcloud/imageroot/systemd/user/nextcloud.service:11` is the template:

```
ExecStartPre=/usr/bin/podman pod create --infra-conmon-pidfile %t/nextcloud.pid \
  --pod-id-file %t/nextcloud.pod-id --name nextcloud -p 127.0.0.1:${TCP_PORT}:80 \
  --replace --network=slirp4netns:allow_host_loopback=true --add-host=accountprovider:10.0.2.2
```

Joiners bind with `BindsTo=` / `After=` / `--pod-id-file`
(`ns8-nextcloud/imageroot/systemd/user/nextcloud-app.service:4,5,17`).

The fit is stronger than "an idiom we can borrow". `docker-compose.tmpl.yml:209-210` carries
an upstream comment recording what BBB's own defaults are:

```
# "bbbWebAPI": "http://127.0.0.1:8090",    -> bbb-web
# "bbbPadsAPI": "http://127.0.0.1:9002",   -> bbb-pads
```

BigBlueButton is natively a single-host product. `bigbluebutton/docker` *added* the 10.7.7.x
split to fit compose. Collapsing back onto one loopback restores the upstream shape rather
than inventing a third one.

**Port allocation.** `agent.allocate_ports(n, proto, module_id)` at `agent/__init__.py:730`,
backed by SQLite over 20000–45000 (`ports_manager.py:69-70,73`). Confirmed as the right
mechanism, and confirmed distinct from `ns8-nethvoice`'s module-local
`allocate_rtp_ports_range()` (`ns8-nethvoice/imageroot/actions/create-module/05setenvs:23,44,45`),
which has no shared registry.

**Public-service declaration.** `agent.add_public_service(name, ports, replace_ports=False)`
at `agent/__init__.py:452`. Shape to copy is `ns8-nethvoice-proxy/imageroot/actions/create-module/20firewall:12-16`
(a flat list including a range: `"10000-20000/udp"`) or `ns8-mail/imageroot/actions/create-module/90firewall:11-19`.

**Single instance per node.** `--label="org.nethserver.max-per-node=1"` in
`ns8-mail/build-images.sh:39`.

**Readiness gates.** Three working patterns exist:
- TCP probe: `ns8-mail/imageroot/systemd/user/dovecot.service:35-36` —
  `ExecStartPost=/usr/bin/bash -c "while ! exec 3<>/dev/tcp/127.0.0.1/9288 &>/dev/null; do sleep 1 ; done"`
- Application probe: `ns8-kickstart-postgresql/imageroot/systemd/user/postgresql-app.service:30` —
  `while ! podman exec postgresql-app psql -U postgres -d kickstart ; do sleep 5 ; done`
- Scripted probe: `ExecStartPost=runagent wait-startup`
  (`ns8-nextcloud/imageroot/systemd/user/nextcloud-app.service:14`)

**NAT handling.** `ns8-nethvoice-proxy/imageroot/actions/configure-module/20configure:23-38`
implements the whole `public_address` / `behind_nat` shape, including deriving the local
network from the routing table.

### Not given

- **No module publishes a UDP port *range*.** `ns8-nethvoice-proxy` declares
  `"10000-20000/udp"` in the firewall (`20firewall:14`), but that range is hardcoded, not
  allocated. Nothing in the tree demonstrates `agent.allocate_ports(8192, 'udp', ...)` followed
  by publishing the result. This is new ground.
- **No module mixes a pod and host-network containers.** `ns8-nextcloud` is all-pod;
  `ns8-nethvoice` is all-host (23 units). The hybrid the brief specifies has no precedent.
- **No coturn/TURN reference anywhere**, as the brief already notes for `ns8-nethvoice-proxy`.
- **The core does not know the node's public address.** No `public_address` symbol exists
  anywhere under `ns8-core/core/` or `ns8-core/ui/`. `get-facts` exposes `default_ipv4` but
  passes it through `agent.facts.pseudo_ip()`
  (`core/imageroot/var/lib/nethserver/node/actions/get-facts/50get:114`), i.e. anonymised. The
  UI field cannot be pre-filled from core; it must be typed, exactly as `ns8-nethvoice-proxy`
  does.
- **The kickstart template is a two-container demo.** `imageroot/` holds one pod unit and two
  joiners (`kickstart.service`, `kickstart-app.service`, `postgresql-app.service`). See section 6.

---

## 2. Port and address map

### 2a. Collision check inside the pod — the decisive question

Every listening port of the fourteen in-pod services, collected from the images' own configs.
**There are no collisions.** All port numbers are distinct.

| Service | Ports | Evidence |
|---|---|---|
| `postgres` | 5432 | `mod/apps-akka/bbb-apps-akka.conf:20`; `mod/bbb-graphql-server/entrypoint.sh:10` |
| `redis` | 6379 | `mod/bbb-graphql-middleware/config.yml:6`; `mod/bbb-export-annotations/config/settings.json:27` |
| `bbb-web` | 8090 | `mod/bbb-web/entrypoint.sh:29` (`-Dserver.port=8090`) |
| `bbb-graphql-server` | 8085 | `mod/bbb-graphql-server/entrypoint.sh:18`; healthcheck `docker-compose.tmpl.yml:327` |
| `bbb-graphql-actions` | 8093 | `mod/bbb-graphql-server/entrypoint.sh:22` |
| `bbb-graphql-middleware` | 8378 | `mod/bbb-graphql-middleware/config.yml:3` |
| `apps-akka` | 8901 | `mod/bbb-graphql-server/entrypoint.sh:21`; `mod/bbb-graphql-middleware/config.yml:15` |
| `etherpad` | 9001 | `mod/nginx/bbb/notes.nginx:10,27` |
| `bbb-pads` | 9002 | `mod/bbb-export-annotations/config/settings.json:24`; `mod/recordings/recording.yml:2` |
| `nginx` | 48081, 48082, 48083, 48087, 8185 | `mod/nginx/bigbluebutton:3,4,7,73`; `mod/nginx/nginx.conf:40` |
| `freeswitch` | 8021 (ESL), 5066 (ws), 7443 (wss), 5060 (dial-in SIP), 15060 (external SIP), 16384–24576/udp (RTP) | `event_socket.conf.xml:5`; `sip_profiles/external.xml:104,105,24`; `sip_profiles/external-dialin.xml:28`; `switch.conf.xml:147-148` |
| `fsesl-akka` | none observed (ESL client) | no listener in `mod/fsesl-akka/` — see section 8 |
| `bbb-export-annotations` | none (Redis queue worker) | `settings.json:29-32` |
| `recordings` | none (resque workers) | `mod/recordings/supervisord.conf:4-7,15,26` |

**Consequence: the pod needs no port reallocation.** Upstream even leaves a clean gap —
FreeSWITCH RTP ends at 24576 and mediasoup starts at 24577, adjacent and non-overlapping.

The gap is 48083, whose only purpose is Greenlight in dev mode
(`mod/nginx/nginx.conf:34-50`, redirecting to `10.7.7.35`). Greenlight is out of scope, so
48083 can be dropped.

### 2b. Publication map

| Port | Service | Classification | Why |
|---|---|---|---|
| 48087/tcp | nginx | **published to node loopback** | Traefik's upstream. The only nginx listener without `proxy_protocol` (`mod/nginx/bigbluebutton:7-8`, `default_server`). 48081/48082 require PROXY protocol from haproxy and are unusable by Traefik. |
| 6379/tcp | redis | **published to node loopback**, *not* on 6379 | `webrtc-sfu` and `bbb-webrtc-recorder` are host-netns and need Redis. The node's own Redis already holds `127.0.0.1:6379` (`ns8-core/core/imageroot/etc/systemd/system/redis.service:21`, `--network=host`). Must publish on a `TCP_PORTS_RANGE` port. |
| 8021/tcp | freeswitch ESL | **host, not published** | `webrtc-sfu` needs it (`mod/webrtc-sfu/config.yaml:12-13`), and both are in the host namespace. Below 20000, outside the allocator span, so nothing else is handed it. `fsesl-akka`, which stays in the pod, reaches it through `10.0.2.2`. |
| 5066/tcp | freeswitch SIP-over-WS | **host, not published** | `mod/webrtc-sfu/config.yaml:10-11`. Same reasoning. |
| allocated 1024/udp | freeswitch RTP | **host, not public** | The SFU↔FreeSWITCH audio leg, node-local. Allocated rather than left at FreeSWITCH's 16384–24576 default, which overlaps the allocator span. |
| 3008/tcp | webrtc-sfu | host loopback, reached **from** the pod | `mod/nginx/bbb/webrtc-sfu.nginx:1,10` — `location /bbb-webrtc-sfu` → `proxy_pass http://10.7.7.1:3008`. Default `clientPort: "3008"` (`bbb-webrtc-sfu/config/default.example.yml:37`). |
| 3010/tcp | webrtc-sfu mcs | host loopback, internal to SFU | `default.example.yml:151` |
| allocated 8192/udp | webrtc-sfu mediasoup | **public** | `default.example.yml:417-418` |
| 5432, 8085, 8090, 8093, 8378, 8901, 9001, 9002, 48081, 48082, 8185 | see 2a | **pod-internal** | never leave the pod netns |
| 5060 | freeswitch | **not bound** | The `external-dialin` profile is deleted by the patched entrypoint: on the host namespace 5060 would collide with ns8-nethvoice-proxy. |
| 15060, 7443 | freeswitch | **host, unused** | Bound by the `external` profile. Below 20000, unmanaged; residual collision risk, documented in section 7. |
| ?/udp | bbb-webrtc-recorder | **public** (count unknown) | see section 8 |

The FreeSWITCH RTP row is the one that breaks the brief's "only two ports" premise. It is not
optional: with `webrtc-sfu` in the host netns and FreeSWITCH in the pod, every conference-audio
packet crosses that boundary.

### 2c. Every `10.7.7.x` literal and `extra_hosts` entry

| File:line | Literal | Becomes |
|---|---|---|
| `docker-compose.tmpl.yml:42` | `10.7.7.2:8090` (bbb-web healthcheck) | `127.0.0.1:8090` |
| `docker-compose.tmpl.yml:63,103,145,177,193,212,228,279,305,334,355,382,425,457,580` | per-service static IPs | all dropped — one pod netns |
| `docker-compose.tmpl.yml:137-142` | nginx published on `127.0.0.1` and `10.7.7.1` | single `--publish 127.0.0.1:${TCP_PORT}:48087` |
| `docker-compose.tmpl.yml:148-155` | nginx `extra_hosts`: `host.docker.internal:10.7.7.1`, `bbb-web:10.7.7.2`, `etherpad:10.7.7.4`, `webrtc-sfu:10.7.7.1`, `greenlight:10.7.7.21`, `bbb-graphql-server:10.7.7.31`, `bbb-graphql-middleware:10.7.7.32` | all `127.0.0.1` **except** `webrtc-sfu` and `freeswitch`, which become `10.0.2.2` (slirp4netns host loopback, as `ns8-nextcloud` does for `accountprovider`); `greenlight` dropped |
| `docker-compose.tmpl.yml:473` | `bbb-webrtc-recorder` `extra_hosts: redis:10.7.7.5` | host-netns container → pod Redis via its published loopback port |
| `docker-compose.tmpl.yml:606-610` | `bbb-net` subnet `10.7.7.0/24` | dropped |
| `mod/webrtc-sfu/config.yaml:2` | `redisHost: 10.7.7.5` | published Redis loopback port |
| `mod/webrtc-sfu/config.yaml:3` | `clientHost: 10.7.7.1` | `127.0.0.1` (upstream default anyway, `default.example.yml:38`) |
| `mod/webrtc-sfu/config.yaml:6,7` | `mcs-host` / `mcs-address: 10.7.7.1` | `127.0.0.1` |
| `mod/webrtc-sfu/config.yaml:9,10,12` | freeswitch `ip` / `sip_ip` / `esl_ip: 10.7.7.10` | `127.0.0.1` (published FS ports) |
| `mod/webrtc-sfu/config.yaml:32` | `plainRtp.listenIp.announcedIp: "10.7.7.1"` | `127.0.0.1` — this leg is node-local |
| `mod/apps-akka/bbb-apps-akka.conf:5` | `redis.host="10.7.7.5"` | `127.0.0.1` |
| `mod/apps-akka/bbb-apps-akka.conf:11` | `graphqlMiddlewareAPI = "http://10.7.7.32:8378"` | `http://127.0.0.1:8378` |
| `mod/freeswitch/conf/vars.xml.tmpl:63` | `local_ip_v4=10.7.7.10` | `127.0.0.1` |
| `mod/nginx/bbb/webrtc-sfu.nginx:10` | `proxy_pass http://10.7.7.1:3008` | `http://10.0.2.2:3008` |
| `mod/nginx/nginx.conf:43,49` | `https://10.7.7.35` | dropped with 48083/Greenlight |
| `mod/nginx/bbb-html5.dev.nginx:17` | `http://10.7.7.1:3000` | dropped (dev only) |
| `mod/nginx/bbb/bbb-exporter.nginx:2` | `http://10.7.7.33:9688` | dropped (exporter excluded) |
| `mod/nginx/bbb/webhooks.nginx:3` | `http://10.7.7.17:3005` | dropped (webhooks excluded) |
| `mod/periodic/bbb-resync-freeswitch:5` | `fs_cli -H 10.7.7.1 -P 8021` | see section 6 |
| `mod/haproxy/*`, `scripts/greenlight-migrate-v2-v3` | — | dropped with haproxy/Greenlight |

Note `mod/periodic/bbb-resync-freeswitch:5` uses `-H 10.7.7.1` while `scripts/fs_cli:10` uses
`-H 10.7.7.10`, and neither passes `-p "$FSESL_PASSWORD"` in the former case. Upstream
inconsistency; do not replicate.

---

## 3. Port budget verdict

### What the code settles

**8192 is a hard ceiling for the whole SFU, not a per-worker figure.** `createWorker` is called
with a shared settings object and no per-worker range split
(`bbb-webrtc-sfu/lib/mcs-core/lib/adapters/mediasoup/workers.js:213-220`, default
`workerSettings = WORKER_SETTINGS`). `WORKER_SETTINGS` derives from
`config/default.example.yml:417-418`. All workers draw from the same 24577–32768 span. Whatever
`workers: "auto"` resolves to (`default.example.yml:368`), the total never exceeds the range.

**Transports are keyed by media type per element, and BBB creates one element per stream.**
`mtransport-sdp-element.js:144-149`:

```js
let transportSet = this._transportSets.get(mediaType);
if (transportSet == null) {
  transportSet = await this._createTransportSet(options);
  this._transportSets.set(mediaType, transportSet);
}
```

That caches per `mediaType` *within one element*. It does not share transports across elements.
And `lib/video/video.js` calls `this.mcs.subscribe(...)` once per subscription — at `:333`,
`:859`, `:887`, `:955` (RTP), `:1414` — with a distinct `mediaId` each time. No transport-reuse
setting exists: `grep -i reuse` over the mediasoup adapter and `default.example.yml` returns
nothing.

**Answer to the brief's decisive sub-question: yes, one transport per consumed webcam.**
Consumption is therefore quadratic in meeting size for the video plane, not linear.

**A second, independent draw exists.** `transports.js:91` calls `router.createPlainTransport`
for the SFU↔FreeSWITCH leg, from the same worker range.

### Estimate

For a meeting of N participants, all cameras on, all subscribed to all:

- video publish: N transports
- video subscribe: N × (N−1) transports
- audio WebRTC: N transports
- SFU↔FS `PlainTransport`: on the order of N

≈ N² + 2N. Setting N² + 2N = 8192 gives N ≈ 89.

**Verdict: 8192 is right for the intended scale, but it is a scale cap, not headroom.** It
bounds the module at roughly a single ~90-person all-cameras meeting, or proportionally more
concurrent smaller meetings. Two qualifiers, both material:

- BBB paginates webcam subscriptions, so real subscribe counts are below N−1. The effective
  ceiling is higher than 89 by an unknown factor.
- The figure covers **mediasoup only**. It does not cover FreeSWITCH's 8193-port RTP range, nor
  `bbb-webrtc-recorder`.

### The number the brief does not account for

Total upstream UDP appetite is 16384–32768 = **16385 ports**, from two independent ranges.
If both FreeSWITCH and the SFU end up in the host netns, that is 65% of the core allocator's
25000-port span (`ports_manager.py:69-70`) for one module — untenable against decision 4's own
"a third of the node's budget" reasoning.

The pod does not make the FreeSWITCH range free: FreeSWITCH ends up in the host namespace too,
alongside the SFU, so its RTP range is bound on the host and has to be allocated like any other.

The shipped budget is **9216 UDP in one contiguous allocation**, split by
`create-module/05setenvs` into 8192 for mediasoup (public) and 1024 for the FreeSWITCH RTP leg
(host-local). That is 37% of the allocator's 25000-port span. See section 5, blocker 2.

The pod/host split is still a port-budget decision as much as a networking one and should be
recorded as such in the ADR — but what it buys is a narrowable, allocatable range with no
userspace forwarding on the media path, not a free one.

---

## 4. Compose → systemd translation

Target: one user unit per container in `imageroot/systemd/user/`, `ns8-nextcloud` layout — one
pod unit, thirteen joiners with `--pod-id-file`, two standalone host-network units. `docker
compose` does not exist at runtime.

| Service | Image | Volumes | Env | Flags | Ordering / gate | Restart |
|---|---|---|---|---|---|---|
| **pod** `bigbluebutton.service` | — | — | `%S/state/environment` | `--publish 127.0.0.1:${NGINX_PORT}:48087`, `--publish 127.0.0.1:${REDIS_PORT}:6379`, `--network=slirp4netns:allow_host_loopback=true`, `--add-host` per service name → `127.0.0.1`, `--add-host=webrtc-sfu:10.0.2.2`, `--add-host=freeswitch:10.0.2.2` | `Before=` all joiners | `always` |
| `postgres` | `postgres:16-alpine` (`:564`) | named volume ← `./data/postgres` (`:576`); `initdb.sh` as `%S/state/` bind (`:577`) | `POSTGRES_MULTIPLE_DATABASES=bbb_graphql,hasura_app` (`:567`, drop `greenlight`), `POSTGRES_USER`, `POSTGRES_PASSWORD` ← secret | — | first; gate `pg_isready` (`:571`) | `unless-stopped` → `always` |
| `redis` | `redis:8.4-alpine` (`:219`) | named volume ← `./data/redis` (`:230`) | — | — | gate `redis-cli ping` (`:222`) | `always` |
| `bbb-web` | `alangecker/bbb-docker-web:${TAG_BBB}` (`:32`) | `bigbluebutton` volume (`:59`), `freeswitch-meetings` volume (`:60`) — **both backed up** | `DOMAIN`, `SHARED_SECRET`, `STUN_SERVER`, `TURN_SECRET`, `TURN_EXT_*`, `ENABLE_RECORDING`, `WELCOME_*`, `ENABLE_LEARNING_DASHBOARD` (`:44-57`); drop `COLLABORA_URL` | — | `After=` redis, etherpad, bbb-pads (`:34-37`); gate `/dev/tcp/127.0.0.1/8090` | `always` |
| `freeswitch` **(host netns)** | `alangecker/bbb-docker-freeswitch:...` (`:76`) | `conf/sip_profiles` (`:99`), `freeswitch-meetings` volume (`:100`); **plus** patched `vars.xml.tmpl` | `DOMAIN`, `EXTERNAL_IPv4`, `ESL_PASSWORD` ← secret, `SOUNDS_LANGUAGE`, `DISABLE_SOUND_*` (`:85-93`); drop `SIP_IP_ALLOWLIST` | `cap_add` per `:78-84` — see section 5 | gate `/dev/tcp/127.0.0.1/8021` | `always` |
| `nginx` | `alangecker/bbb-docker-nginx:...` (`:122`) | `bigbluebutton` volume ro (`:125`), default presentation (`:126`), `--tmpfs /tmp` (`:146`) | — | — | `After=` bbb-web, graphql-middleware | `always` |
| `etherpad` | `alangecker/bbb-docker-etherpad:...` (`:165`) | — | `ETHERPAD_API_KEY` ← secret (`:173`) | — | `After=` redis | `always` |
| `bbb-pads` | `alangecker/bbb-docker-pads:${TAG_PADS}` (`:184`) | — | `ETHERPAD_API_KEY` ← secret (`:190`) | — | `After=` redis, etherpad (`:186-188`) | `always` |
| `bbb-export-annotations` | `...bbb-export-annotations:${TAG_BBB}` (`:200`) | `bigbluebutton` volume (`:214`), `--tmpfs /tmp` (`:216`) | — | — | `After=` redis, etherpad, bbb-pads (`:202-205`) | `always` |
| `apps-akka` | `alangecker/bbb-docker-apps-akka:${TAG_BBB}` (`:291`) | `freeswitch-meetings` (`:301`), `bbb-html5.yml` ro (`:302`); **plus** patched `bbb-apps-akka.conf` | `DOMAIN`, `SHARED_SECRET`, `POSTGRES_PASSWORD` (`:296-299`) | — | `After=` redis, postgres (`:293-295`) | `always` |
| `fsesl-akka` | `alangecker/bbb-docker-fsesl-akka:${TAG_BBB}` (`:270`) | — | `FSESL_PASSWORD` ← secret (`:276`) | — | `After=` redis, freeswitch (`:272-274`) | `always` |
| `bbb-graphql-server` | `...graphql-server:${TAG_BBB}` (`:315`) | — | `POSTGRES_USER`, `POSTGRES_PASSWORD`, `HASURA_GRAPHQL_ADMIN_SECRET` (`:322-325`) — **currently `TODO_CHANGE_ME`** | — | `After=` postgres, bbb-web, apps-akka, graphql-actions (`:316-320`); gate `curl /healthz` (`:327`) | `always` |
| `bbb-graphql-actions` | `...graphql-actions:${TAG_BBB}` (`:348`) | — | — | — | `After=` redis, apps-akka (`:350-352`) | `always` |
| `bbb-graphql-middleware` | `...graphql-middleware:${TAG_BBB}` (`:373`) | — | — | — | `After=` graphql-server, graphql-actions, bbb-web, redis (`:375-379`) | `always` |
| `recordings` | `alangecker/bbb-docker-recordings:${TAG_BBB}` (`:439`) | `bigbluebutton`, `freeswitch-meetings`, `mediasoup`, `bbb-webrtc-recorder` volumes (`:447-451`), tmpfs (`:452-454`) | `DOMAIN`, `SHARED_SECRET` (`:444-446`) | — | `After=` redis, bbb-pads (`:441-443`) | `always` |
| `webrtc-sfu` **(host netns)** | `...webrtc-sfu:${TAG_WEBRTC_SFU}` (`:239`) | `mediasoup` volume (`:252`), tmpfs (`:253`); **plus** patched `config.yaml` | `ESL_PASSWORD` ← secret, `MS_WEBRTC_LISTEN_IPS` (`:244-250`) — rewritten, section 7 | `--network=host`, `--security-opt seccomp=unconfined` (`:257`), `--ulimit memlock=...` (`:259`) | `After=` pod unit + freeswitch gate | `always` |
| `bbb-webrtc-recorder` **(host netns)** | `...webrtc-recorder:${TAG_WEBRTC_RECORDER}` (`:464`) | `bbb-webrtc-recorder` volume (`:468`) | `BBBRECORDER_PUBSUB_ADAPTERS_REDIS_ADDRESS` (`mod/bbb-webrtc-recorder/Dockerfile:32`) → published Redis port | `--network=host` (`:471`) | `After=` pod unit | not set upstream → `always` |

`depends_on` in compose is ordering only. `After=`/`Wants=` reproduce exactly that and no more —
the readiness gates in the table are the real dependency mechanism, using the three NS8 patterns
listed in section 1.

### Peer addresses that are NOT environment-driven — the real work

This is the list that sets the effort. Each needs either a mounted file override or a
`--add-host` entry. Split by which fix applies.

**Category A — solved by `--add-host <name>:127.0.0.1` on the pod, no file edit.**
These reference peers by *hostname*, so a hosts entry is sufficient once the pod collapses
everything onto one loopback:

| Where | Reference |
|---|---|
| `mod/bbb-graphql-server/entrypoint.sh:4` | `PGHOST=postgres` |
| `mod/bbb-graphql-server/entrypoint.sh:10,11,25` | `postgres://…@postgres:5432/…` |
| `mod/bbb-graphql-server/entrypoint.sh:21` | `HASURA_GRAPHQL_AUTH_HOOK=http://apps-akka:8901/userInfo` |
| `mod/bbb-graphql-server/entrypoint.sh:22` | `HASURA_BBB_GRAPHQL_ACTIONS_ADAPTER_URL=http://bbb-graphql-actions:8093` |
| `mod/bbb-graphql-middleware/config.yml:5,9,11,13,15` | `redis`, `ws://nginx:8185/v1/graphql`, `bbb-graphql-actions:8093`, `bbb-web:8090`, `apps-akka:8901` |
| `mod/bbb-export-annotations/config/settings.json:23,24,26` | `bbb-web:8090`, `bbb-pads:9002`, `redis` |
| `mod/bbb-pads/entrypoint.sh:8,10` | `jq '.etherpad.host = "etherpad"'`, `jq '.redis.host = "redis"'` |
| `mod/recordings/recording.yml:1,2` | `redis_host: redis`, `notes_endpoint: http://bbb-pads:9002/p` |
| `mod/nginx/bbb/*.nginx`, `mod/nginx/bigbluebutton:65` | `bbb-web:8090`, `etherpad:9001`, `bbb-graphql-server:8085`, `bbb-graphql-middleware:8378` |

These are hardcoded in image files, but the fix costs one `--add-host` per name and zero file
maintenance. The `bbb-pads` entrypoint is the least comfortable of them — it rewrites the config
with `jq` on every start (`mod/bbb-pads/entrypoint.sh:6-10`), so a mounted `settings.json` would
be overwritten. `--add-host` is the only clean option there.

**Category B — hardcoded IP literals; require a mounted file override.** This is the actual
work list:

| File:line | Value | Fix |
|---|---|---|
| `mod/webrtc-sfu/config.yaml:2` | `redisHost: 10.7.7.5` | mount patched `config.yaml`; also needs `redisPort` added, since Redis will not be on 6379 |
| `mod/webrtc-sfu/config.yaml:3` | `clientHost: 10.7.7.1` | → `127.0.0.1` |
| `mod/webrtc-sfu/config.yaml:6,7` | `mcs-host`, `mcs-address: 10.7.7.1` | → `127.0.0.1` |
| `mod/webrtc-sfu/config.yaml:9,10,12` | freeswitch `ip`/`sip_ip`/`esl_ip: 10.7.7.10` | → `127.0.0.1`; `port`/`esl_port` must change to the published loopback ports |
| `mod/webrtc-sfu/config.yaml:32` | `plainRtp.listenIp.announcedIp: "10.7.7.1"` | → `127.0.0.1` |
| `mod/apps-akka/bbb-apps-akka.conf:5` | `redis.host="10.7.7.5"` | mount patched conf — but see below |
| `mod/apps-akka/bbb-apps-akka.conf:11` | `graphqlMiddlewareAPI = "http://10.7.7.32:8378"` | → `http://127.0.0.1:8378` |
| `mod/freeswitch/conf/vars.xml.tmpl:63` | `local_ip_v4=10.7.7.10` | mount patched `.tmpl`; drives ESL bind (`event_socket.conf.xml:4`) and both SIP profiles' `rtp-ip` |
| `mod/bbb-web/turn-stun-servers.xml:11-15,43` | `turn0` emitted unconditionally | mount patched `.tmpl` — mandatory, section 7 |
| `mod/nginx/bbb/webrtc-sfu.nginx:10` | `proxy_pass http://10.7.7.1:3008` | mount patched file; `10.0.2.2` is not a name `--add-host` can help with here since the literal is an IP |

`bbb-apps-akka.conf` is a special case: it is copied and `sed`-substituted at start
(`mod/apps-akka/entrypoint.sh:5-8`) from `/etc/bigbluebutton/bbb-apps-akka.conf.tmpl`, so a
mounted `.tmpl` is honoured. The same entrypoint also rewrites `settings.yml` with `yq`
(`:13-14`), setting `public.kurento.wsUrl` and `public.pads.url` from `$DOMAIN` — env-driven, so
no override needed there.

**Ten files in category B.** Every one is either a `.tmpl` consumed by `dockerize` or a plain
config read at start, so all are mountable — none require rebuilding an image. That is the
finding that makes the port realistic.

### The two templating layers

Cleanly separable, as the brief anticipated.

- **Compose-generation layer — disappears.** `scripts/generate-compose:41,66` runs
  `jwilder/dockerize -template /docker-compose.tmpl.yml`, feeding it ~15 `ENABLE_*` variables
  (`:54-65`). Every `{{if}}` in `docker-compose.tmpl.yml` becomes a decision about which units
  we ship and enable. `BBB_BUILD_TAG` is pinned in the script itself
  (`scripts/generate-compose:39`); image tags come from `get_tag` over `repos/` submodules
  (`:28-36`), which we replace with explicit pins.
- **In-image layer — survives, and is what makes the port work.** Entrypoints call `dockerize
  -template` at container start: `mod/bbb-web/entrypoint.sh:26-29` (two templates),
  `mod/freeswitch/entrypoint.sh:69-72` (`vars.xml.tmpl`, `conference.conf.xml.tmpl`),
  `mod/recordings/entrypoint.sh:10-12`. Plus `sed`/`jq`/`yq` rewrites in
  `mod/apps-akka/entrypoint.sh`, `mod/fsesl-akka/entrypoint.sh:6`, `mod/bbb-pads/entrypoint.sh`.

---

## 5. Rootless blockers, by severity

### Blocker 1 — `webrtc-sfu` `memlock: -1` and `seccomp:unconfined`

`docker-compose.tmpl.yml:256-259`, with upstream's own reasons inline:

```yaml
security_opt:
  - seccomp:unconfined # allow io_uring access for mediasoup
ulimits:
  memlock: -1 # allow io_uring_register_buffers to allocate enough ram
```

Both exist for **io_uring**. `--security-opt seccomp=unconfined` is available to rootless
podman and needs no privilege. The memlock hard limit is the problem: a rootless process cannot
raise `RLIMIT_MEMLOCK` above the hard limit it inherits, and `podman run --ulimit memlock=...`
can only lower it. `install-core.sh:39` sets three sysctls and no limits
(`net.ipv4.ip_unprivileged_port_start=23`, `user.max_user_namespaces=28633`,
`net.ipv4.ip_forward=1`), so NS8 does not raise it for us.

**To clear:** either a node-level drop-in raising `DefaultLimitMEMLOCK` (outside the module
contract), or establish that mediasoup's io_uring path is optional and can be disabled. I did
not find a config key disabling io_uring in `config/default.example.yml` — see section 8.

Severity: highest, because it is the one item a module genuinely may not be able to fix itself.

### Blocker 2 — FreeSWITCH RTP range vs the core allocator

FreeSWITCH defaults to 16384–24576 (`switch.conf.xml:147-148`), which overlaps the allocator's
20000–45000 (`ports_manager.py:69-70`) across 20000–24576.

Keeping FreeSWITCH in the pod does **not** by itself clear this, contrary to my first reading.
With `webrtc-sfu` in the host namespace, the FS RTP range has to be published to host loopback
for the SFU to reach it. Publishing 8193 ports occupies them *on the host*, 20000–24576 of them
inside the allocator's span, and puts every audio packet through rootlessport in userspace.

**Cleared, by moving FreeSWITCH into the host namespace as well.** Both ends of the audio leg
then share a namespace and talk over `127.0.0.1`: no publishing, no port translation, no
userspace proxy. The range is still allocated — FreeSWITCH binds it on the host, so the
allocator has to know — but it is narrowed from 8193 to 1024 ports and comes out of the same
contiguous UDP allocation as mediasoup, split by `create-module/05setenvs`. The narrowing is
done by the patched entrypoint rather than by shipping a copy of `switch.conf.xml`, so upstream
changes to that file are still picked up.

The residual cost is that FreeSWITCH also binds 15060 and 7443 on the host. Both sit below
20000, outside the allocator span, so no NS8 module will be handed them — but nothing prevents
another module from hardcoding them, the same class of risk as ns8-nethvoice-proxy hardcoding
5060. Port 5060 itself is not bound: the patched entrypoint deletes the `external-dialin`
profile.

1024 is provisional. Sizing it properly needs the measurement in section 8 item 2; the audio leg
uses one port per audio participant, not one per stream, so it is already generous against the
node's CPU ceiling.

### Blocker 3 — `mod/freeswitch/entrypoint.sh` runs `iptables`

`mod/freeswitch/entrypoint.sh:4-16`:

```sh
iptables -S INPUT | grep "\-\-dport 5060 " | cut -d " " -f 2- | xargs -rL1 iptables -D
iptables -A INPUT -p tcp --dport 5060 -s 0.0.0.0/0 -j REJECT
```

The script is `#!/bin/bash -e`, so a failing `iptables` aborts the container before FreeSWITCH
starts. Two problems in a pod: the rules would apply to the *shared pod netns*, affecting every
container in it; and rootless `iptables` depends on kernel modules and xtables locks that may
not be reachable.

**To clear:** the entire block exists to block SIP dial-in on 5060 and allow-list specific IPs.
SIP dial-in is out of scope, so the block is dead code for us. Replace the entrypoint with one
that skips it. Low effort, but it must be done — this is not optional.

### Blocker 4 — FreeSWITCH capabilities

`docker-compose.tmpl.yml:78-84` requests `IPC_LOCK`, `NET_ADMIN`, `NET_RAW`, `NET_BROADCAST`,
`SYS_NICE`, `SYS_RESOURCE`.

- `NET_ADMIN`, `NET_RAW` — needed only by the `iptables` block above. Removed with blocker 3.
- `SYS_NICE` — real-time thread priority. Rootless podman can grant it in the user namespace,
  but it does not confer the ability to actually raise priority beyond the user's `RLIMIT_NICE`.
  Degrades to normal scheduling; audio quality risk under load, not a startup failure.
- `IPC_LOCK` — `mlock()`. Same `RLIMIT_MEMLOCK` question as blocker 1.
- `SYS_RESOURCE` — raising rlimits. Same constraint: capability in a user namespace does not
  exceed the namespace's own limits.
- `NET_BROADCAST` — no exercising code found; FreeSWITCH does not broadcast in this
  configuration.

**To clear:** drop `NET_ADMIN`/`NET_RAW`/`NET_BROADCAST` with the iptables block, keep
`SYS_NICE`/`SYS_RESOURCE`/`IPC_LOCK` as best-effort, and verify audio under load. See section 8.

### Blocker 5 — the node's Redis owns `127.0.0.1:6379`

`ns8-core/core/imageroot/etc/systemd/system/redis.service:21` runs `--network=host`. The pod's
own Redis is in the pod netns, so no conflict there. But the two host-netns containers need
Redis, and publishing the pod's Redis on 6379 would collide.

**To clear:** publish on a `TCP_PORTS_RANGE` port; override
`BBBRECORDER_PUBSUB_ADAPTERS_REDIS_ADDRESS` (`mod/bbb-webrtc-recorder/Dockerfile:32`, an `ENV`,
so a plain `--env` wins) and `redisHost`/`redisPort` in the mounted
`mod/webrtc-sfu/config.yaml`. Fully solvable.

Confirming the brief's Q11 premise otherwise: `ip_unprivileged_port_start=23` covers every port
BBB binds. The lowest is 5060, and inside the pod netns even that is unconstrained.

---

## 6. Lifecycle gaps

### What the kickstart template provides

`imageroot/`: `actions/create-module/` (absent — no create-module directory),
`actions/configure-module/{01Hostname_validation,05configure_traefik,10configure_environment_vars,20configure_traefik,80start_services,validate-input.json}`,
`actions/destroy-module/20destroy`, `actions/get-configuration/`,
`actions/restore-module/{06copyenv,40restore_database,50traefik}`, `actions/clone-module/50traefik`,
`bin/{discover-smarthost,module-cleanup-state,module-dump-state}`, `etc/state-include.conf`,
`events/smarthost-changed/10reload_services`, `update-module.d/20restart`, and three systemd
units.

### Gaps

**Install.** No `create-module` directory exists at all. But most of what decision 5 asks for is
*declarative*, not code — see section 9a. What remains as `create-module` code is
`agent.add_public_service()` and secret generation (`10genpasswords`). Model on
`ns8-nethvoice/imageroot/actions/create-module/05setenvs` for structure only, not for the
allocator.

**Units.** Three units become sixteen plus a pod unit. The template's pod unit
(`imageroot/systemd/user/kickstart.service:13-14`) uses `Requires=`/`Before=` naming each joiner
explicitly — that list grows to fifteen names and must stay in sync by hand. `ns8-nextcloud`'s
`Before=` line has the same property.

**Configure.** `10configure_environment_vars` handles a handful of values. We need the ten
category-B file overrides rendered into `%S/state/` at configure time, plus `public_address` /
`behind_nat` handling.

**Backup.** `etc/state-include.conf:8-9` lists `state/kickstart.sql` and
`volumes/kickstart-app` — a two-line demo. See section 6b.

**Restore.** `restore-module/40restore_database` restores one PostgreSQL dump via the
`%S/state/restore/` → `/docker-entrypoint-initdb.d/` bind
(`imageroot/systemd/user/postgresql-app.service:18,24`). We need two databases
(`bbb_graphql`, `hasura_app` — `docker-compose.tmpl.yml:567`, minus `greenlight`) plus large
media volumes. The closer reference is `ns8-mattermost`: `imageroot/bin/module-dump-state` runs
`podman exec postgres-app pg_dump -U mattuser --format=c mattermost > mattermost.pg_dump`, and
`restore-module/40restore-postgres` replays it through an ephemeral `${POSTGRES_IMAGE}` with the
dump piped on stdin. We need that twice, and a matching `module-cleanup-state` to remove both
dumps after backup.

`restore-module/50call-configure-module` must pass **every** variable that `06copyenv` restored,
not just the Traefik ones — any omitted field falls back to a default and silently misconfigures
the module. With BBB's settings surface (section 9c) that list is long; enumerate it from
`configure-module/validate-input.json` rather than by hand.

**Update.** `update-module.d/20restart` restarts everything. Two problems. First, with sixteen
containers and Hasura metadata migrations at `bbb-graphql-server` start, a blind restart is not
obviously safe (unverified — section 8). Second, `update-module.d/` scripts are *independent*:
a failing script does not halt the sequence, the next one runs anyway. That is the opposite of
action steps, where non-zero exit halts everything. Any BBB schema migration placed here must
therefore be idempotent and must not assume its predecessor succeeded. Convention is `05`–`06`
pre-restart migrations, `30restart`, then `50`–`60` post-restart work.

**Uninstall.** `destroy-module/20destroy` exists but must additionally deallocate the UDP range
and remove the public service.

### 6b. What to back up, and what a restore loses

**Must be backed up** (`imageroot/etc/state-include.conf`):
- `volumes/bigbluebutton` (`docker-compose.tmpl.yml:59,125,214,448`) — recordings,
  presentations, published playback. This is the large one.
- `state/bbb_graphql.pg_dump`, `state/hasura_app.pg_dump` (`:567`) plus `volumes/postgres-data`.
- `state/passwords.env` — the generated secrets (section 7).

**Must NOT be backed up:** the rendered category-B config overrides. The rule is to exclude
anything derivable from the module image; those files are regenerated by `configure-module`
during restore, so backing them up would only risk restoring a stale copy over a newer template.
My first draft got this wrong.

**Reconstructible, do not back up:**
- Redis (`./data/redis`, `:230`). It carries live meeting state and pub/sub channels only —
  `mod/bbb-graphql-middleware/config.yml:5`, `mod/bbb-export-annotations/config/settings.json:29-32`.
  Meaningless across a restore.
- `./data/mediasoup` (`:252`), `./data/freeswitch-meetings` (`:60,100,301,449`) — per-meeting
  scratch.
- `./data/bbb-webrtc-recorder` (`:451,468`) — raw recorder output, consumed by the `recordings`
  pipeline. Worth backing up only if unprocessed recordings may be in flight.

**A restore explicitly loses:** every in-progress meeting; any recording still in the
`rap:archive`/`rap:process`/`rap:publish` queues at backup time, since those are resque jobs in
Redis (`mod/recordings/supervisord.conf:7`) and Redis is not backed up — the raw media survives
in `/var/bigbluebutton/recording/raw`, but the job that would process it does not. The status
directories under `/var/bigbluebutton/recording/status/` (`mod/recordings/entrypoint.sh:5-16`)
are the recovery mechanism; whether `rap-starter.rb` re-enqueues from them is unverified.

### 6c. `periodic` → systemd timer

`mod/periodic/entrypoint.sh` is a `while : … sleep 30m` loop (`:8,22`) doing exactly three things:

1. `/bbb-resync-freeswitch` (`:12`) — one `fs_cli` call
2. delete presentations older than 5 days (`:6,15`):
   `find /var/bigbluebutton/ -maxdepth 1 -type d -name "*-[0-9]*" -mtime +$history -exec rm -rf '{}' +`
3. `/bbb-remove-old-recordings` if `ENABLE_RECORDING` and `REMOVE_OLD_RECORDING` (`:18-20`)

`/var/run/docker.sock` (`docker-compose.tmpl.yml:414`) is mounted **solely** for step 1:
`mod/periodic/bbb-resync-freeswitch:5` runs `docker exec -it bbb-freeswitch fs_cli …`.

**Equivalent:** a `bigbluebutton-periodic.timer` with `OnUnitActiveSec=30min` plus a service
running a `runagent` script that does:

```
podman exec bigbluebutton-freeswitch /opt/freeswitch/bin/fs_cli \
    -H 127.0.0.1 -p "$FSESL_PASSWORD" -x 'fsctl sync_clock_when_idle'
```

`podman exec` replaces the socket mount entirely — no socket, no extra container. Use
`-H 127.0.0.1` (correct inside the pod netns) and pass `-p "$FSESL_PASSWORD"`, following
`scripts/fs_cli:10` rather than `bbb-resync-freeswitch:5`, which uses the wrong host and omits
the password. Steps 2 and 3 are plain `find`/script invocations against the volume.

---

## 7. Security notes

### Trust boundary: pod ↔ the two host-netns containers

The pod is a closed netns reachable only through what we publish to `127.0.0.1`. The two media
containers sit in the host netns and can reach **everything on the node's loopback** — including
the node's own Redis on `127.0.0.1:6379` (`ns8-core/core/imageroot/etc/systemd/system/redis.service:21`),
which holds cluster state, and any other module that published to loopback.

This is the sharpest security consequence of the hybrid design, and it is asymmetric: the pod
cannot reach the host (except via `allow_host_loopback` to `10.0.2.2`), but the host-netns
containers can reach the pod's published ports *and* the rest of the node.

Mitigation is limited. Neither container needs the node's Redis, but nothing prevents access.
Worth stating in the ADR rather than pretending it is contained.

### `seccomp=unconfined` on `webrtc-sfu`

Removes syscall filtering entirely for that container. Upstream's stated reason is io_uring
(`docker-compose.tmpl.yml:257`), and io_uring is precisely what the default podman seccomp
profile blocks. The exposure is the full syscall surface to a process that terminates untrusted
WebRTC media from the public internet — the single most attacker-reachable component in the
stack, running with the weakest confinement.

Rootless containment still applies (user namespace, no root on the host), so this is a
privilege-escalation-surface concern, not a direct root compromise. But it should be recorded
as an accepted risk, not glossed.

### Secrets and anonymity

`HASURA_GRAPHQL_ADMIN_SECRET: TODO_CHANGE_ME` at `docker-compose.tmpl.yml:325` is a literal in
the compose file. Must be generated per install.

**All six BBB secrets must go through `state/passwords.env`, never `agent.set_env()`.**
`agent.set_env()` writes to Redis in plain text, readable by every module on the node — putting
`SHARED_SECRET` there would let any co-installed module forge BBB API calls, and
`FSESL_PASSWORD` would hand over the FreeSWITCH command socket. The secrets, from `sample.env:53-58`:

| Variable | `sample.env` | Consumed by |
|---|---|---|
| `SHARED_SECRET` | `:53` | bbb-web (`:48`), apps-akka (`:298`), recordings (`:446`) — the BBB API shared secret |
| `ETHERPAD_API_KEY` | `:54` | etherpad (`:173`), bbb-pads (`:190`) |
| `POSTGRESQL_SECRET` | `:56` | postgres (`:569`), apps-akka (`:299`), graphql-server (`:324`) |
| `FSESL_PASSWORD` | `:57` | freeswitch (`:93`), fsesl-akka (`:276`), webrtc-sfu (`:245`) |
| `TURN_SECRET` | `:58` | bbb-web (`:53`) — retained only if external TURN is configured |
| `HASURA_GRAPHQL_ADMIN_SECRET` | — (hardcoded `:325`) | graphql-server |

Generate all six in `create-module/10genpasswords` with `secrets.token_urlsafe()`, write
`state/passwords.env` at mode 0600, list it in `etc/state-include.conf`, load with
`EnvironmentFile=-%S/state/passwords.env` and inject with `--env-file=%S/state/passwords.env`.
Restic restores the file, so no restore-side code is needed.

Note `TURN_EXT_SECRET` (`sample.env:79`) is admin-supplied rather than generated, but belongs in
the same file for the same reason.

`RAILS_SECRET` (`sample.env:55`) is Greenlight-only and drops out of scope.

On anonymity (decision 7): the plumbing supports it. `mod/nginx/bbb/webrtc-sfu.nginx:2-8,15-18`
shows nginx taking `User-Id`, `Meeting-Id`, `Voice-Bridge`, `User-Name` from bbb-web's
`checkAuthorization` response and forwarding them to the SFU. Whatever `fullName` the frontend
supplies at join is what propagates — identity never needs to reach BBB.

Counting against the anonymity requirement, two defaults leak outward and must be changed:
`sample.env:73` `STUN_IP=216.93.246.18` sends every client's IP to a third party, and the
`turn0` bean (below) would do the same if pointed at an external TURN server.

### TURN/STUN with coturn dropped — mandatory template patch

`mod/bbb-web/turn-stun-servers.xml:11-15` emits `turn0` (`turn:${DOMAIN}:3478`) with no
`ENABLE_COTURN` guard, and `:43` references it in the `turnServers` set unconditionally. With
coturn dropped, every client receives a TURN candidate pointing at a port nothing listens on.
The same applies to `stun1` (`:8`) once `STUN_IP` points at `EXTERNAL_IPv4` per
`scripts/setup:130`.

**The template must be patched** — this is category B, item 9. `TURN_EXT_SERVER` / `TURN_EXT_SECRET`
already have a proper guard (`:27,49`), so the external-TURN path in decision 3 works as
intended once `turn0` is removed.

`ENABLE_HTTPS_PROXY` has exactly three consumers in the whole repo: the haproxy service
(`docker-compose.tmpl.yml:495`), bbb-web's env (`:52`), and `turn1`
(`turn-stun-servers.xml:17,45`). **Setting it false disables nothing else.** Confirmed by
exhaustive grep.

For STUN: it can be left empty or pointed inward, but with coturn gone there is no inward STUN
listener either. Leaving `stun1` pointing at a dead address is the same failure as `turn0`.
Whether bbb-web tolerates an empty `STUN_SERVER` is unverified.

### NAT / `MS_WEBRTC_LISTEN_IPS`

`docker-compose.tmpl.yml:249`:

```yaml
MS_WEBRTC_LISTEN_IPS: '[{"ip":"${EXTERNAL_IPv4}", "announcedIp":"${EXTERNAL_IPv4}"}]'
```

The brief is right: identical values in both fields. On a node behind NAT the box does not own
the public address and mediasoup cannot bind it. The correct split is `ip` = a locally bindable
address, `announcedIp` = the public address:

```json
[{"ip":"0.0.0.0", "announcedIp":"<public>"}]
```

The IPv6 branch (`:247`) already demonstrates the pattern with `"ip":"::"`.

On a second array entry for LAN clients: mediasoup accepts multiple entries (`:247` proves the
array form), and adding `{"ip":"<lan>", "announcedIp":"<lan>"}` would advertise both candidates,
letting ICE pick the local path without NAT reflection. I did not verify that bbb-webrtc-sfu
passes multi-entry arrays through unmodified — see section 8.

**Reusable from `ns8-nethvoice-proxy/imageroot/actions/configure-module/20configure`:** the
`public_address`-present/absent branch and the `PUBLIC_IP`/`PRIVATE_IP`/`BEHIND_NAT` env split
(`:23-32`) transfer almost verbatim. **Not reusable:** `DEFAULT_CONTACT` (`:38`) is SIP-specific,
and the `LOCALNETWORKS` derivation via `ip route` (`:34`) serves kamailio's trust model, not
mediasoup's — though the same routing-table lookup is exactly how the optional LAN entry above
would be computed.

**The field cannot be pre-filled.** No `public_address` symbol exists in `ns8-core`; `get-facts`
anonymises `default_ipv4` through `agent.facts.pseudo_ip()`
(`core/.../get-facts/50get:114`). The admin types it, as in `ns8-nethvoice-proxy`.

### Firewall

Public services to declare via `agent.add_public_service()`, shaped like
`ns8-nethvoice-proxy/imageroot/actions/create-module/20firewall:12-16`:

- the allocated mediasoup UDP range (`<start>-<end>/udp`)
- `bbb-webrtc-recorder`'s UDP ports, if any (unverified)
- **nothing on TCP** — Traefik owns 443 and reverse-proxies to nginx on loopback

**Yes, the allocated range must be declared in the firewall in addition to being allocated.**
`agent.allocate_ports` (`agent/__init__.py:730`) reserves against the SQLite registry;
`agent.add_public_service` (`:452`) dispatches the node's `add-public-service` action. They are
independent — `ns8-nethvoice-proxy` calls `add_public_service` for its RTP range despite that
range being hardcoded rather than allocated.

Nothing in BBB assumes it owns 443 once coturn is gone: the only 443 reference is
`turns:${DOMAIN}:443` in `turn1` (`turn-stun-servers.xml:21`), which disappears with
`ENABLE_HTTPS_PROXY=false`.

### Traefik

Forward to nginx on `48087` — the only listener without `proxy_protocol`
(`mod/nginx/bigbluebutton:3,4,7-8`; 48081/48082 both declare `proxy_protocol` and require
haproxy). Routes served, from `mod/nginx/bigbluebutton:25` (`include /etc/nginx/bbb/*.nginx`):

| Path | Upstream | WebSocket |
|---|---|---|
| `/bigbluebutton` (+ subpaths) | `bbb-web:8090` (`bbb/web.nginx:6`) | no |
| `/graphql` | `bbb-graphql-middleware:8378` (`bbb/graphql.nginx:2,8`) | **yes** |
| `/api/rest/{clientSettings,meetingStaticData,userMetadata}` | `bbb-graphql-server:8085` (`bbb/graphql.nginx:14,35,39,63`) | no |
| `/bbb-webrtc-sfu` | SFU `3008` via `10.0.2.2` (`bbb/webrtc-sfu.nginx:1,10`) | **yes** |
| `/pad`, `/pad/socket.io`, `/static` | `etherpad:9001` (`bbb/notes.nginx:2,25,35,45,52,71`) | **yes** (`socket.io`) |
| `/html5client` (+ `/locales`, `/wasm`) | static (`bbb/bbb-html5.nginx:2,9,15`) | no |
| `/playback/presentation/…`, `/presentation` | static (`bbb/presentation.nginx:18,21,25`) | no |
| `/playback/video/` | static `/var/bigbluebutton/published/video/` (`bbb/playback-video.nginx:18-19`) | no |
| `/learning-analytics-dashboard/` | static (`bbb/learning-dashboard.nginx:1`) | no |
| `/recording/screenshare`, `/slides`, `/podcast`, `/notes` | static playback assets | no |

Three WebSocket upgrade paths: `/graphql`, `/bbb-webrtc-sfu`, `/pad/socket.io`. Note the
internal `8185` listener (`mod/nginx/bigbluebutton:73`) is nginx proxying to the Hasura upstream
for the middleware's own use (`mod/bbb-graphql-middleware/config.yml:9`) — pod-internal, never
exposed.

Drop the `/demo`, `/bbb-exporter`, `/bigbluebutton/api/hooks` and `/livekit/` routes with their
excluded services.

---

## 8. Unverified

Ordered roughly by how much each would change the plan.

1. **Whether mediasoup's io_uring can be disabled.** Decides blocker 1, the most likely hard
   stop. `grep -i "io_uring\|iouring"` over `bbb-webrtc-sfu/config/default.example.yml` returns
   nothing. *To settle:* read mediasoup's own worker documentation for the version pinned by the
   SFU image, and check whether `MEDIASOUP_*` env vars or a worker arg disable it. Then run the
   container rootless with the inherited memlock limit and see whether it starts.

2. **Actual per-participant UDP port consumption.** The N²+2N estimate in section 3 is derived,
   not measured, and BBB's webcam pagination is unmodelled. *To settle:* run a meeting of known
   size with all cameras on and count with `ss -uln` inside the SFU's network namespace, at
   N = 5, 10, 20; fit the curve. Do the same for FreeSWITCH's range.

3. **`bbb-webrtc-recorder`'s UDP port range.** It is a WebRTC endpoint on the host netns
   (`docker-compose.tmpl.yml:471`) so it must bind UDP, but its config is baked into the image
   from `/app/config/bbb-webrtc-recorder.yml` (`mod/bbb-webrtc-recorder/Dockerfile:38`) and that
   repo is not cloned. Affects both the firewall declaration and the total port budget. *To
   settle:* clone `bigbluebutton/bbb-webrtc-recorder` and read `config/bbb-webrtc-recorder.yml`.

4. **Whether `bbb-webrtc-sfu` passes multi-entry `MS_WEBRTC_LISTEN_IPS` through unmodified.**
   Decides whether the LAN-client-without-NAT-reflection fix works. *To settle:* trace
   `MS_WEBRTC_LISTEN_IPS` parsing in `lib/mcs-core/lib/adapters/mediasoup/configs.js`.

5. **`fsesl-akka`'s listening ports.** No listener found in `mod/fsesl-akka/`, and it is
   presented as an ESL client (`entrypoint.sh:6` substitutes only `FSESL_PASSWORD`). If it does
   listen, the section 2a no-collision conclusion needs rechecking. *To settle:* read
   `akka-bbb-fsesl` config in the `bigbluebutton` repo, or `ss -lntu` in a running container.

6. **`apps-akka` ports beyond 8901.** 8901 is known only indirectly, from two consumers
   (`mod/bbb-graphql-server/entrypoint.sh:21`, `mod/bbb-graphql-middleware/config.yml:15`).
   `bbb-apps-akka.conf:13-15` sets `http.interface = "0.0.0.0"` without a port. Same collision
   caveat as above. *To settle:* read `akka-bbb-apps`' `application.conf` (included at
   `bbb-apps-akka.conf:2`), or `ss -lntu` in the container.

7. **Whether `bbb-web` tolerates an empty `STUN_SERVER`.** `turn-stun-servers.xml:8` interpolates
   it into a `StunServer` bean constructor with no guard, so an empty value may produce an
   invalid bean and fail Spring context startup. *To settle:* render the template with an empty
   value and start `bbb-web`.

8. **Q18 — what breaks in recording processing without `bbb-pads`.** `mod/recordings/recording.yml:2`
   sets `notes_endpoint: http://bbb-pads:9002/p`, and `recordings` declares `depends_on: bbb-pads`
   (`docker-compose.tmpl.yml:441-443`). `bbb-pads` is in scope so this is not blocking, but the
   failure mode is unknown. *To settle:* read the shared-notes fetch in
   `record-and-playback/presentation/scripts/process/presentation.rb` and check whether a failed
   fetch is fatal to the job or degrades to no-notes.

9. **Q19 — whether `bbb-export-annotations` needs `etherpad`/`bbb-pads` at runtime.** It declares
   `depends_on` on both (`:202-205`) and its config carries `bbbPadsAPI`
   (`settings.json:24`), but whether annotated-presentation download actually calls it, versus
   only breakout capture, is not settled by config. *To settle:* trace the `exportJobs` queue
   consumer (`settings.json:30`) in `bbb-export-annotations`' source.

10. **Whether `update-module.d/20restart`'s blind restart is safe.** `bbb-graphql-server` applies
    Hasura metadata at start; sixteen containers restarting unordered may race. Sharpened by the
    fact that `update-module.d/` scripts do not halt on failure (section 6), so a half-applied
    migration would be followed by a restart regardless. *To settle:* read the Hasura migration
    invocation in `bbb-graphql-server`'s image and test an in-place image bump.

11. **Whether a restore re-enqueues in-flight recordings.** Section 6b assumes the
    `/var/bigbluebutton/recording/status/` directories are the recovery mechanism. *To settle:*
    read `rap-starter.rb` (`mod/recordings/supervisord.conf:16`) and confirm it scans those
    directories rather than relying solely on Redis.

12. **`SYS_NICE` degradation impact on FreeSWITCH audio.** Section 5 blocker 4 assumes graceful
    degradation. *To settle:* load-test conference audio rootless without effective nice
    privilege.

13. **Q17 — recordings output format.** I believe this is settled, but state the reasoning since
    it contradicts a natural reading of the brief: the `recordings` image builds only from
    `record-core`, `presentation` and `bbb-conf` contexts
    (`docker-compose.tmpl.yml:432-435`). `record-and-playback/video` **exists upstream** (verified
    by sparse checkout) but is **not** among them. `bbb-presentation-video`
    (`mod/recordings/Dockerfile:116-118`) is a dependency of the *presentation* format — it
    renders slides and annotations — not an MP4 output format. The `/playback/video/` nginx route
    (`bbb/playback-video.nginx:18-19`) therefore serves a directory nothing populates.
    **Conclusion: web player only, no MP4.** *To settle definitively:* list
    `/usr/local/bigbluebutton/core/scripts/publish/` in a built image and confirm `video.rb` is
    absent.

14. **Whether 8192 UDP ports can actually be demanded via the label.** Section 9a assumes
    `org.nethserver.udp-ports-demand=8192` is honoured at that magnitude. The allocator does span
    25000 ports (`ports_manager.py:69-70`) so it is arithmetically possible, but nothing in the
    tree demands a range remotely this large — the biggest observed is
    `org.nethserver.tcp-ports-demand=1`. A failure here is an install-time failure, not a silent
    one. *To settle:* build a stub module with the label set to 8192 and install it.

15. **Q20 — local captions scope.** Scoped only, as instructed.
    `mod/freeswitch/conf/autoload_configs/modules.conf.xml:17` already loads `mod_audio_fork`, so
    the audio tap exists. Missing: a `bbb-transcription-controller` container, a Vosk (or
    equivalent) ASR server container plus its language models, a WebSocket endpoint for
    `mod_audio_fork` to stream to, the FreeSWITCH dialplan wiring to start the fork per
    conference leg, and the `rap:captions` resque queue already present
    (`mod/recordings/supervisord.conf:7`) being fed. Two additional containers and one dialplan
    change, all inside the pod, no new public ports. Model size is the practical cost. Not
    designed here.

---

## 9. NS8 module contract conformance

Added after re-reading the module conventions. Several items below correct the sections above;
those corrections are already applied in place and cross-referenced.

### 9a. Ports are declared, not allocated in code

Decision 5 specifies `agent.allocate_ports(8192, 'udp', module_id)` in `create-module`. That
function exists, but it is not how NS8 modules obtain ports. The platform allocates from a
container label at install time:

`ns8-core/core/imageroot/var/lib/nethserver/cluster/actions/add-module/50update:110-113` reads
`org.nethserver.udp-ports-demand`, passes it to the node's `add-module`
(`:174-175`), and `ns8-core/core/imageroot/var/lib/nethserver/node/actions/add-module/50update:76-83`
does the allocation and injects the result into the module environment:

```python
if request['udp_ports_demand'] > 0:
    udp_ports_range=node.ports_manager.allocate_ports(request['udp_ports_demand'], module_id, 'udp')
    module_environment['UDP_PORT'] = f'{udp_ports_range[0]}'
    if request['udp_ports_demand'] > 1:
        module_environment['UDP_PORTS_RANGE'] = f'{udp_ports_range[0]}-{udp_ports_range[1]}'
```

The TCP path is identical (`:66-74`), and is where `TCP_PORT` / `TCP_PORTS_RANGE` — used
throughout sections 2 and 4 — actually come from. Both call the same
`node.ports_manager.allocate_ports` that backs `agent.allocate_ports`, so decision 5's
*allocator* choice was right; only the entry point was wrong.

Note the argument order differs between the two: `node.ports_manager.allocate_ports(n, module_id, proto)`
versus `agent.allocate_ports(n, proto, module_id)` (`agent/__init__.py:730`).

So `build-images.sh` needs:

```bash
--label="org.nethserver.udp-ports-demand=8192" \
--label="org.nethserver.tcp-ports-demand=4" \
```

Four TCP: nginx 48087, Redis, FreeSWITCH ESL, FreeSWITCH SIP-over-WS (section 2b). The UDP
figure is provisional pending blocker 2 — if the narrowed FreeSWITCH RTP range is also drawn
from the allocator, this becomes 8192 + that range.

`agent.add_public_service()` in `create-module` is still required and still separate: allocation
reserves, the firewall exposes. That part of section 7 stands.

### 9b. Labels required in `build-images.sh`

Beyond the port demands:

```bash
--label="org.nethserver.authorizations=node:fwadm traefik@node:routeadm" \
--label="org.nethserver.max-per-node=1" \
--label="org.nethserver.rootfull=0" \
--label="org.nethserver.volumes=bigbluebutton postgres-data" \
--label="org.nethserver.images=<pinned refs>" \
```

- **`node:fwadm`** — without it `agent.add_public_service()` is refused. Section 7 described the
  call but not the privilege; `ns8-mail/build-images.sh:48` declares exactly this.
- **`traefik@node:routeadm`** — for the route in section 7. `ns8-kickstart-postgresql/build-images.sh:45`
  is the template.
- **`max-per-node=1`** — decision 4, matching `ns8-mail/build-images.sh:39`.
- **`org.nethserver.volumes=bigbluebutton postgres-data`** — not previously mentioned and worth
  having. It lets the sysadmin place these on a separate, larger disk at install time. BBB
  recordings are exactly the bulk-data case this exists for; `ns8-mail/build-images.sh:41`
  declares `dovecot-data` on the same reasoning.
- **`org.nethserver.images`** — the pin point that section 4's translation table left open. This
  label is what Renovate reads to open update PRs, which makes the tag format load-bearing:
  every reference must be fully pinned. `alangecker/bbb-docker-*:${TAG_BBB}` as written in
  `docker-compose.tmpl.yml:32,76,122,…` is a variable, and upstream resolves it from git
  describe over submodules (`scripts/generate-compose:28-36,44-52`). We must resolve those to
  concrete tags once and write them literally. `postgres:16-alpine` (`:564`) and
  `redis:8.4-alpine` (`:219`) are also insufficiently pinned — `16-alpine` floats. Verify each
  tag exists on Docker Hub before writing it; a bad tag fails only at pull time.

`min-core` should be set once a floor is known.

### 9c. Settings taxonomy (Q24)

| Class | Variables |
|---|---|
| **Module settings** (`configure-module` input, `agent.set_env()`) | `DOMAIN` (Traefik host), `public_address` / `behind_nat` (section 7), `ENABLE_RECORDING`, `REMOVE_OLD_RECORDING`, `RECORDING_MAX_AGE_DAYS` (`sample.env:45-47`), `SOUNDS_LANGUAGE` (`:118`), `DISABLE_SOUND_MUTED` / `DISABLE_SOUND_ALONE` (`:121,124`), `ENABLE_LEARNING_DASHBOARD` (`:127`), `WELCOME_MESSAGE` / `WELCOME_FOOTER` (`:93,94`), `TURN_EXT_SERVER` (`:78`), `STUN_SERVER` |
| **Computed at install/configure** | `TCP_PORT`, `TCP_PORTS_RANGE`, `UDP_PORT`, `UDP_PORTS_RANGE` (all injected by the platform, 9a); `EXTERNAL_IPv4` and `MS_WEBRTC_LISTEN_IPS` (derived from `public_address`, section 7); all ten category-B override files (section 4) |
| **Secrets** (`state/passwords.env`, 0600) | the six in section 7, plus `TURN_EXT_SECRET` |
| **Dropped** | `ENABLE_HTTPS_PROXY`→false, `ENABLE_COTURN`, `ENABLE_GREENLIGHT`, `ENABLE_COLLABORA`, `ENABLE_WEBHOOKS`, `ENABLE_PROMETHEUS_EXPORTER*`, `LETSENCRYPT_EMAIL`, `SIP_IP_ALLOWLIST`, `RAILS_SECRET`, all `SMTP_*` / `OPENID_*` / `S3_*` / `HCAPTCHA_*` (`sample.env:133-170`, Greenlight-only), `DEV_MODE`, `IGNORE_TLS_CERT_ERRORS` |

### 9d. Service start must name every unit

Section 6 noted the `Requires=`/`Before=` list grows to fifteen names. The sharper point is in
`configure-module/80start_services`: systemd does **not** cascade a restart from the pod unit to
its children. `systemctl --user restart bigbluebutton.service` alone leaves all sixteen
containers down. Every unit must be listed explicitly, pod first:

```bash
systemctl --user enable bigbluebutton.service
systemctl --user try-restart bigbluebutton.service postgres-app.service redis-app.service \
    bbb-web-app.service freeswitch-app.service nginx-app.service ...
```

`try-restart` rather than `restart` because on first configure the units are not yet running.
This is a sixteen-name list maintained by hand in at least two places (the pod unit's
`Requires=`/`Before=`, and here) — the largest single source of avoidable breakage in the port,
and worth a generator or a test that diffs the two lists.

### 9e. Logging in the periodic timer

Section 6c's timer script must not print to stdout: the agent framework treats stdout as an
action's JSON return value. Log to stderr, using `agent.SD_ERR` / `agent.SD_WARNING` prefixes so
journald sets the level. In bash, `exec 1>&2` at the top of the script.
