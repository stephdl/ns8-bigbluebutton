#!/bin/sh

#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Wraps ./bin/start from bigbluebutton/greenlight.
#
# Greenlight calls the API over the public name, so Ruby validates whatever answers.
# Pointing that name at the pod and trusting its certificate works with or without
# Let's Encrypt.
#

set -e

. /pod-trust-lib.sh

pod_trust_add_host
pod_trust_refresh_ca "API calls may fail"

exec ./bin/start
