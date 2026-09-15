# Web UI firmware integration

The browser UI is a separate source component from the native Rust player.

Repository layout on the firmware `dev` branch:

```text
proaudio-player-firmware/
├── sources/
│   ├── proaudio-player-native/  -> proaudio-player-native/dev
│   └── proaudio-player-webui/   -> proaudio-player-webui/newui
└── upstream/buildroot/          -> pinned Buildroot revision
```

During the `newui` development phase the firmware Web UI submodule tracks the `newui` branch. After that branch is merged into `proaudio-player-webui/dev`, the firmware submodule branch setting should be changed to `dev`.

The Buildroot `proaudio-webui` package owns frontend compilation. It uses host Node.js only during the firmware build, installs the frontend dependency tree with `npm ci --include=dev` from the committed `package-lock.json`, runs the Vite production build, and installs only the generated `dist/` contents into:

```text
/usr/share/proaudio-player/webui
```

Node.js, npm, Vite, SolidJS development tooling and `node_modules` are not installed in the target root filesystem.

The native Rust daemon remains frontend-toolchain agnostic. It only serves the installed static directory and continues to work headlessly when the Web UI package is disabled.

For a reproducible firmware checkout, use the submodule revisions pinned by the firmware commit:

```bash
git switch dev
git pull --ff-only
git submodule sync
git submodule update --init \
  upstream/buildroot \
  sources/proaudio-player-native \
  sources/proaudio-player-webui
```

For active development, the matching branches are currently `proaudio-player-native/dev` and `proaudio-player-webui/newui`. Once a tested revision is selected for a firmware build, update the firmware gitlinks so the exact native and Web UI commits remain reproducible.

`package-lock.json` is mandatory while `BR2_PACKAGE_PROAUDIO_WEBUI=y`; the Buildroot package fails early if the lockfile is missing rather than silently falling back to a non-reproducible `npm install`.
