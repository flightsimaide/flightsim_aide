#!/usr/bin/env bash
# Task 4.12 (macOS half): build and test the plugin core on the MacBook.
#
#   tools/platform/mac/task_4.12_plugin_build.sh [--sdk <X-Plane SDK folder>]
#
# Needs Xcode command line tools and cmake (brew install cmake ninja). With --sdk
# (or XPLANE_SDK set) it also builds the X-Plane shell and checks it is universal.
# The result is written to plugin/build/4.12-darwin/result.txt.
exec "$(dirname "$0")/../../plugin_build_check.sh" Darwin "$@"
