# Security policy

## Supported versions

Only the latest release of the app and of the companion plugin receives security fixes.

## Reporting a vulnerability

Please do **not** open a public issue for a security problem.

Use GitHub's private vulnerability reporting: on the repository page choose **Security**, then **Report a vulnerability**. Include what you found, how to reproduce it, the app and plugin versions (the plugin version is shown in X-Plane under Plugins > Plugin Admin and in the `GET /v1/hello` answer) and the simulator version.

You can expect an acknowledgement within a few days. This is a small volunteer project, so a fix may take longer; the report is kept private until a fix is available.

## What the plugin exposes

The companion plugin runs inside the simulator and serves the app over the local network:

- It listens on a fixed port range (18086 to 18093) and is meant for the **local network only**.
- It is **read-only**: it serves the current aircraft's identity and checklist file, and a stream of dataref values the client subscribes to. Write operations are not supported.
- It never accepts a file path from a request. The only file served is the current aircraft's checklist.
- It has **no authentication or encryption** (plain HTTP and WebSocket). Anyone on the same network can read what it serves.

Do not expose the plugin's port to the internet or run it on an untrusted network. Use on an untrusted network is out of scope for this policy; a way to make the plugin do more than the list above (read other files, write values, crash the simulator from the network, run code) is in scope.

## Scope

In scope: the plugin (`plugin/`), the wire protocol (`plugin/PROTOCOL.md`), and the app's handling of data it receives from the plugin or from checklist files.

Out of scope: vulnerabilities in the simulator itself, in third-party libraries (report those upstream; CivetWeb is bundled in `plugin/third_party/`), and anything that needs physical access to a device you already control.
