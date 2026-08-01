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
    ${rc} =    Execute Command
    ...    api-cli run module/${module_id}/configure-module --data '{"host":"${TEST_HOST}","public_address":"${TEST_PUBLIC_ADDRESS}","lets_encrypt":false,"http2https":false}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

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
    ...    runagent -m ${module_id} bash -c 'source state/passwords.env && podman exec freeswitch /opt/freeswitch/bin/fs_cli -H 127.0.0.1 -p "$FSESL_PASSWORD" -x "status"'
    Should Contain    ${output}    UP

Check if FreeSWITCH is not listening on the SIP dial-in port
    # The external-dialin profile is removed by the patched entrypoint: on the
    # host network 5060 would collide with ns8-nethvoice-proxy.
    ${output} =    Execute Command    ss -lnu sport = :5060
    Should Not Contain    ${output}    :5060

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
