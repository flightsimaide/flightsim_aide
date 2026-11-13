#!/usr/bin/env bash
# Task 4.12 (Linux half): build and test the plugin core on Linux (WSL on the PC).
#
#   tools/platform/linux/task_4.12_plugin_build.sh [--sdk <X-Plane SDK folder>]
#
# Needs g++ and cmake (sudo apt install build-essential cmake ninja-build). In WSL,
# run it from a clone on the Linux file system (for example ~/flightsim_aide), not
# from a Windows drive mounted under /mnt: builds there are slow and can fail on line endings or permissions.
# With --sdk (or XPLANE_SDK set) it also builds the X-Plane shell.
# The result is written to plugin/build/4.12-linux/result.txt.
exec "$(dirname "$0")/../../plugin_build_check.sh" Linux "$@"
