#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; installed
"$HELPER" --recover
