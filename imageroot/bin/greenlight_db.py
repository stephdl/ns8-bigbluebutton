#
# Copyright (C) 2026 Nethesis S.r.l.
# SPDX-License-Identifier: GPL-3.0-or-later
#

#
# Shared by check-default-admin and seed-default-admin: both need a one-shot
# query against the Greenlight database and the same --wait <seconds> argument.
#

import subprocess


def psql(sql, timeout=30):
    return subprocess.run(
        ["podman", "exec", "postgres-app", "psql", "-U", "postgres",
         "-d", "greenlight", "-tAc", sql],
        capture_output=True, text=True, timeout=timeout,
    )


def parse_wait_arg(argv):
    if len(argv) == 3 and argv[1] == "--wait":
        return int(argv[2])
    return 0
