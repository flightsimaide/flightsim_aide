# Third-party notices

FlightSim Aide is released under the MIT licence (see `LICENSE`). It builds on, or ships with, the work of others. Their notices are below. Where a component's own licence file is kept in this repository, that file is the authoritative text.

Trademarks belong to their owners. X-Plane is a trademark of Laminar Research. XChecklist, Thranda, Pilatus and every other simulator, aircraft or add-on name appears only to say what FlightSim Aide works with. FlightSim Aide is not affiliated with, or endorsed by, any of them.

## XChecklist (reference for the checklist format and grammar)

FlightSim Aide reads the checklist file format of the XChecklist plugin for X-Plane. Its Dart parser and condition grammar were written independently, using XChecklist's documentation and source code (the parser and plugin, and its command-line `checker`) as a reference and as a test oracle. No XChecklist source file is included in this repository. XChecklist is acknowledged here, and its licence is reproduced in full, because its design and behaviour were followed closely.

Project: XChecklist, https://github.com/sparker256/xchecklist (reference revision `02987e0`).

```
MIT License

Copyright (c) 2019 William Good

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Components of the X-Plane plugin

CivetWeb and doctest are in this repository under `plugin/third_party/<name>/`, each with its licence file and a `VERSION.txt`. Keep each licence file next to its source. The X-Plane SDK is not in the repository.

| Component | Used for | Licence | Copyright |
|---|---|---|---|
| CivetWeb 1.16 | The plugin's embedded HTTP and WebSocket server | MIT (the bundled `LICENSE.md` lists further licences for optional features that are not used) | (c) 2013-2021 The CivetWeb developers; (c) 2004-2013 Sergey Lyubka; (c) 2013 No Face Press, LLC; (c) 2013 F-Secure Corporation |
| doctest 2.4.11 | The plugin's unit tests (test builds only, not shipped) | MIT | (c) 2016-2023 Viktor Kirilov |
| X-Plane SDK (XPLM) | Linked into the plugin | BSD-style, see below | (c) 2008 Sandy Barbour and Ben Supnik |

The X-Plane SDK licence requires that redistributions of source keep its copyright notice and disclaimer, and forbids using the names of its authors, X-Plane or Laminar Research to endorse or promote a derived product without written permission. The SDK itself is not redistributed in this repository; builders download it from Laminar Research. Keep its `license.txt` with any copy of the SDK files that is ever distributed.

## Dart and Flutter packages

The app is built with Flutter (BSD-3-Clause, The Flutter Authors) and the Dart packages listed in `pubspec.yaml`. Packages that are compiled into a build have their licences collected by Flutter at build time and shown by the app's licence page (`showLicensePage`). Before each release, check the list with `flutter pub deps` and confirm none is under a licence that conflicts with MIT distribution.

Build-time tools that are not shipped (for example `flutter_launcher_icons`) are not listed.

## Branding

The icon and logo in `assets/branding/` were designed for this project and are covered by this repository's MIT licence unless a file says otherwise.
