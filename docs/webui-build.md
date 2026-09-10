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

The Buildroot `proaudio-webui` package owns frontend compilation. It uses host Node.js only during the firmware build, runs the Vite production build, and installs only the generated `dist/` contents into:

```text
/usr/share/proaudio-player/webui
```

Node.js, npm, Vite, SolidJS development tooling and `node_modules` are not installed in the target root filesystem.

The native Rust daemon remains frontend-toolchain agnostic. It only serves the installed static directory and continues to work headlessly when the Web UI package is disabled.

For a synced development checkout:

```bash
git switch dev
git pull --ff-only
git submodule sync --recursive
git submodule update --init --recursive

git -C sources/proaudio-player-native switch dev
git -C sources/proaudio-player-native pull --ff-only

git -C sources/proaudio-player-webui switch newui
git -C sources/proaudio-player-webui pull --ff-only
```

For reproducible frontend dependency resolution, `proaudio-player-webui` should commit `package-lock.json`. Until that lockfile exists on `newui`, the firmware package uses `npm install`; once the lockfile is committed, the package should be tightened to `npm ci`.
