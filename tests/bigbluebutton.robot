*** Settings ***
Library    SSHLibrary
Library    Collections

*** Variables ***
# configure-module requires a public address: mediasoup has to announce
# something, and the module refuses to configure without it. Any address works
# for these tests, since nothing here establishes a real WebRTC session.
${TEST_PUBLIC_ADDRESS}    192.0.2.10
${TEST_HOST}              bbb.test.local

*** Test Cases ***
Check if bigbluebutton is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check if the port ranges were allocated
    # The platform allocates from the labels in build-images.sh, and
    # create-module/05setenvs splits the UDP range in two. If any of these are
    # missing the units will start with empty port variables.
    ${output} =    Execute Command    runagent -m ${module_id} env
    Should Contain    ${output}    NGINX_PORT=
    Should Contain    ${output}    REDIS_PORT=
    Should Contain    ${output}    MEDIASOUP_MIN_PORT=
    Should Contain    ${output}    MEDIASOUP_MAX_PORT=
    Should Contain    ${output}    FS_RTP_MIN_PORT=
    Should Contain    ${output}    FS_RTP_MAX_PORT=

Check if the mediasoup range is the expected size
    ${min} =    Execute Command    runagent -m ${module_id} printenv MEDIASOUP_MIN_PORT
    ${max} =    Execute Command    runagent -m ${module_id} printenv MEDIASOUP_MAX_PORT
    ${size} =    Evaluate    ${max} - ${min} + 1
    Should Be Equal As Integers    ${size}    8192

Check if the secrets file is not world readable
    # These must never reach the environment: agent.set_env writes to Redis in
    # plain text, readable by every module on the node.
    ${mode} =    Execute Command
    ...    stat -c %a /home/${module_id}/.config/state/passwords.env
    Should Be Equal As Strings    ${mode}    600
    ${output} =    Execute Command    runagent -m ${module_id} env
    Should Not Contain    ${output}    SHARED_SECRET=
    Should Not Contain    ${output}    FSESL_PASSWORD=

Check if bigbluebutton can be configured
    Configure module    en-us-callie

Check if configure-module refuses a missing public address
    # Without it mediasoup announces nothing and participants get no media, so
    # the schema must reject it rather than let the module start half-broken.
    ${rc} =    Execute Command
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}"}'
    ...    return_rc=True  return_stdout=False
    Should Not Be Equal As Integers    ${rc}  0

Check if get-configuration mirrors what was set
    ${output} =    Execute Command    api-cli run module/${module_id}/get-configuration
    &{config} =    Evaluate    ${output}
    Should Be Equal As Strings    ${config.host}    ${TEST_HOST}
    Should Be Equal As Strings    ${config.public_address}    ${TEST_PUBLIC_ADDRESS}
    Dictionary Should Contain Key    ${config}    mediasoup_port_range

Check if the pod and its containers are running
    ${output} =    Execute Command    runagent -m ${module_id} podman ps --format '{{.Names}}'
    Should Contain    ${output}    postgres-app
    Should Contain    ${output}    redis-app
    Should Contain    ${output}    bbb-web-app
    Should Contain    ${output}    nginx-app
    Should Contain    ${output}    etherpad-app
    Should Contain    ${output}    bbb-graphql-server-app

Check if the host network containers are running
    # These three are deliberately outside the pod: WebRTC media has to bind the
    # node's real addresses.
    ${output} =    Execute Command    runagent -m ${module_id} podman ps --format '{{.Names}}'
    Should Contain    ${output}    freeswitch
    Should Contain    ${output}    webrtc-sfu

Check if FreeSWITCH answers on the event socket
    ${output} =    Execute Command
    ...    runagent -m ${module_id} bash -c 'source passwords.env && podman exec freeswitch /opt/freeswitch/bin/fs_cli -H 127.0.0.1 -p "$FSESL_PASSWORD" -x "status"'
    Should Contain    ${output}    UP

Check if FreeSWITCH is not listening on the SIP dial-in port
    # The external-dialin profile is removed by the patched entrypoint: on the
    # host network 5060 would collide with ns8-nethvoice-proxy.
    ${output} =    Execute Command    ss -lnu sport = :5060
    Should Not Contain    ${output}    :5060

Check if the vendored sound packs are mounted
    # German and French ship in the module image under imageroot/sounds and are
    # bind-mounted read-only, so neither needs a download.
    ${german} =    Execute Command
    ...    runagent -m ${module_id} podman exec freeswitch sh -c 'ls /opt/freeswitch/share/freeswitch/sounds/de/de/daedalus3/conference/48000 | wc -l'
    Should Be Equal As Integers    ${german}    30
    ${french} =    Execute Command
    ...    runagent -m ${module_id} podman exec freeswitch sh -c 'ls /opt/freeswitch/share/freeswitch/sounds/fr/fr/sibylle/conference/48000 | wc -l'
    Should Be Equal As Integers    ${french}    11

Check if the vendored packs are readable by the freeswitch user
    # The daemon drops to that user, so root being able to read them proves nothing.
    ${rc} =    Execute Command
    ...    runagent -m ${module_id} podman exec freeswitch su -s /bin/sh freeswitch -c 'test -r /opt/freeswitch/share/freeswitch/sounds/fr/fr/sibylle/conference/48000/conf-alone.wav'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if a vendored language needs no download
    Configure sounds language    fr-fr-sibylle
    ${prefix} =    Sound prefix
    Should Contain    ${prefix}    /sounds/fr/fr/sibylle
    ${output} =    Execute Command
    ...    journalctl _UID=$(id -u ${module_id}) -t freeswitch --no-pager --since=-5min
    Should Not Contain    ${output}    installing sound pack
    # Neither pack carries these three, so the entrypoint borrows the English ones.
    ${link} =    Execute Command
    ...    runagent -m ${module_id} podman exec freeswitch readlink /opt/freeswitch/share/freeswitch/sounds/fr/fr/sibylle/digits
    Should Be Equal As Strings    ${link}    /opt/freeswitch/share/freeswitch/sounds/en/us/callie/digits

Check if a downloaded language survives a restart
    # zh-hk-sinmei is the smallest pack upstream publishes, 3 MB for the four
    # rates against 161 MB for French Canadian. It carries no conference prompts,
    # so this case asserts the cache mechanics only, not that anything is spoken.
    Configure sounds language    zh-hk-sinmei
    ${version} =    Execute Command
    ...    runagent -m ${module_id} podman exec freeswitch cat /var/lib/freeswitch-sounds/.version-zh-hk-sinmei
    Should Not Be Empty    ${version}
    ${before} =    Count sound pack installs
    Execute Command    runagent -m ${module_id} systemctl --user restart freeswitch
    Wait Until Keyword Succeeds    120s    5s    FreeSWITCH answers on the event socket
    ${after} =    Count sound pack installs
    Should Be Equal As Integers    ${before}    ${after}
    ${prefix} =    Sound prefix
    Should Contain    ${prefix}    /var/lib/freeswitch-sounds/zh/hk/sinmei

Check if the English pack is served from the image
    Configure sounds language    en-us-callie
    ${prefix} =    Sound prefix
    Should Contain    ${prefix}    /sounds/en/us/callie

Check if nginx answers behind Traefik
    ${port} =    Execute Command    runagent -m ${module_id} printenv NGINX_PORT
    ${rc} =    Execute Command    curl -f http://127.0.0.1:${port}/bigbluebutton/api
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if the maintenance timer is active
    ${output} =    Execute Command
    ...    runagent -m ${module_id} systemctl --user is-active bigbluebutton-periodic.timer
    Should Be Equal As Strings    ${output}    active

Check if bigbluebutton is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

*** Keywords ***
Configure module
    [Arguments]    ${language}
    # The schema requires every field, so a partial payload would be rejected here
    # even though only sounds_language is under test.
    ${rc} =    Execute Command
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","public_address":"${TEST_PUBLIC_ADDRESS}","private_address":"","stun_server":"","turn_ext_server":"","lets_encrypt":false,"enable_recording":false,"recording_max_age_days":0,"enable_learning_dashboard":true,"enable_external_videos":true,"enable_breakout_rooms":true,"show_presentation_on_join":true,"learning_dashboard_max_age_days":7,"sounds_language":"${language}","disable_sound_muted":false,"disable_sound_alone":false,"welcome_message":"","welcome_footer":""}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Configure sounds language
    [Arguments]    ${language}
    Configure module    ${language}
    Wait Until Keyword Succeeds    120s    5s    FreeSWITCH answers on the event socket

FreeSWITCH answers on the event socket
    ${output} =    Execute Command
    ...    runagent -m ${module_id} bash -c 'source passwords.env && podman exec freeswitch /opt/freeswitch/bin/fs_cli -H 127.0.0.1 -p "$FSESL_PASSWORD" -x "status"'
    Should Contain    ${output}    UP

Sound prefix
    ${output} =    Execute Command
    ...    runagent -m ${module_id} bash -c 'source passwords.env && podman exec freeswitch /opt/freeswitch/bin/fs_cli -H 127.0.0.1 -p "$FSESL_PASSWORD" -x "global_getvar sound_prefix"'
    [Return]    ${output}

Count sound pack installs
    ${output} =    Execute Command
    ...    journalctl _UID=$(id -u ${module_id}) -t freeswitch --no-pager | grep -c "installing sound pack" || true
    [Return]    ${output}
