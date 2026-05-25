# Zevy Raylib

[license]: https://img.shields.io/github/license/captkirk88/zevy-raylib?style=for-the-badge&logo=opensourcehardware&label=License&logoColor=C0CAF5&labelColor=414868&color=8c73cc

[![][license]](https://github.com/captkirk88/zevy-raylib/blob/main/LICENSE)

[![Zig Version](https://img.shields.io/badge/zig-0.16.0-blue.svg)](https://ziglang.org/)

> [!WARNING]
> This library and its APIs are experimental.
> The API and internal behavior can and will change without backward compatibility guarantees.
> Tests and cross-platform coverage are limited — treat this as a development-ready library, not production-ready.
> Please open issues or submit PRs if you rely on features that should be stabilized or suggested.

### Table of contents

- [Introduction](#introduction)
- [Quick Start](#quick-start)
- [Contributing](#contributing)
- [Projects](#projects)
- [License](#license)

---

## Introduction

Zevy Raylib is a small library that wires the Raylib runtime into a Zevy ECS-based app. It handles window creation, input harvesting, asset management and sets up RayGui-based UI systems with multiple layout options.

---

## Quick Start

[Examples](examples/) can be ran with:

```bash
zig build examples
```

> [!NOTE]
> Requires `libgl-dev libx11-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev` on Linux.

---

## Contributing

- Follow existing Zig patterns
- Register new plugins in `src/root.zig` by adding them to `plug()`
- Add unit tests beside features in the `src/*` directory. Prefer tests to be named `*_tests.zig`.

## Projects
- [zevy-alloy](https://github.com/captkirk88/zevy-alloy)
- [zevy-ecs](https://github.com/captkirk88/zevy-ecs)

## License
[MIT](LICENSE)