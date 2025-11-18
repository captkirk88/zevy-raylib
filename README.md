# Zevy Raylib

Zevy Raylib is an integration layer that connects the Zevy ECS with the Raylib game library. It provides input handling, asset loading utilities, GUI components, and a plugin system to register common engine features easily.

[license]: https://img.shields.io/github/license/captkirk88/zevy-raylib?style=for-the-badge&logo=opensourcehardware&label=License&logoColor=C0CAF5&labelColor=414868&color=8c73cc

[![][license]](https://github.com/captkirk88/zevy-raylib/blob/main/LICENSE)

### Requirements

- Zig 0.15.1

### Table of contents

- [Introduction](#introduction)
- [Quick Start](#quick-start)
- [Input](#input)
  - [InputManager](#inputmanager)
  - [Bindings & Types](#bindings--types)
- [IO (Assets)](#io-assets)
  - [AssetManager](#assetmanager)
  - [Schemes & Loaders](#schemes--loaders)
- [GUI](#gui)
  - [Components](#components)
  - [Layout & Renderer](#layout--renderer)
  - [Systems](#systems)
- [Embed](#embed)
- [Plugins](#plugins)
  - [RaylibPlugin (app.plugin.zig)](#raylibplugin-appppluginzig)
  - [RayGuiPlugin (app.plugin.zig)](#rayguiplugin-appppluginzig)
  - [AssetsPlugin (assets.plugin.zig)](#assetsplugin-assetspluginzig)
  - [InputPlugin (input.plugin.zig)](#inputplugin-inputpluginzig)
- [Examples & Tests](#examples--tests)
- [Contributing](#contributing)

---

## Introduction

Zevy Raylib is a small library that wires the Raylib runtime into a Zevy ECS-based app. It handles window creation, input harvesting, asset management and sets up RayGui-based UI systems over the Zevy scheduler.

---

## Quick Start

An example application demonstrating manual plugin integration is included. To build and run it:

```bash
zig build run
```

This launches a window showing bouncing colored circles, demonstrating:

- Manual plugin registration (`RaylibPlugin`, `AssetsPlugin`, `InputPlugin`, `RayGuiPlugin`)
- Custom ECS systems for movement and rendering
- Entity creation with Position, Velocity, and Sprite components
- Integration of the Zevy ECS scheduler with Raylib's game loop

The example source is located in `example_main.zig` at the repository root.

> [!WARNING]
> This library and its APIs are experimental. They are intended as a convenient integration layer for example apps and prototypes.
> The API and internal behavior can and will change without backward compatibility guarantees.
> Tests and cross-platform coverage are limited — treat this as a development-time dependency rather than a production runtime.
> Please open issues or submit PRs if you rely on features that should be stabilized.

Files of interest:

- `src/root.zig` — main package root and plugin wiring
- `src/app.plugin.zig` — Raylib and RayGui plugin implementations
- `src/assets.plugin.zig` — Adds the asset subsystem to the ECS
- `src/input.plugin.zig` — Input plugin and system registration

---

## Input

The input layer provides the following:

- `InputManager` — the main runtime service that polls raylib for input state and dispatches events.
- `InputBindings` and `InputBinding` — mapping action names to input chords.
- Input types and helpers (keyboard, mouse, touch, gesture, and gamepads).

Files and location:

- `src/input/input_manager.zig`
- `src/input/input_bindings.zig`
- `src/input/input_types.zig`

### InputManager

`InputManager` is designed to be added to the ECS via the `InputPlugin` and optionally polled directly from systems. It supports event handlers and action checking API:

- `isActionActive("action_name")` — check if action is currently active
- `wasActionTriggered("action_name")` — check a press event this frame
- `addEventHandler` — subscribe to input events

### Bindings & Types

Input bindings, chords, and actions are declared with types located inside the `input` folder. Use the `InputBindings` helper to create action mappings from keyboard/mouse/gamepad/touch inputs.

---

## IO (Assets)

The IO module provides a powerful `AssetManager<T, Loader>` generator for loading and tracking assets.

Key files:

- `src/io/asset_manager.zig` — generic `AssetManager` implementation
- `src/io/loaders.zig` — built-in loaders for asset types
- `src/io/loader.zig` — loader interfaces
- `src/io/scheme_resolver.zig` — handles scheme parsing and resolving

### AssetManager

Use `AssetManager` to queue asset loads and process them in a separate step. It validates asset paths (supports builtin `embedded://` scheme), manages unload, and stores assets in a string-to-entry map.

Useful methods:

- `loadAsset(file, settings)` — queue asset for asynchronous loading
- `loadAssetNow(file, settings)` — load asset immediately
- `process()` — perform a single step of queued loaders
- `unloadAsset(handle)` — release a loaded asset

### Schemes & Loaders

The system supports schemes (for `embedded://` content or custom resolvers) and allows custom loaders via `AssetLoader` and `AssetUnloader` wrappers.

---

## GUI

Zevy Raylib exposes a RayGui-based GUI layer tied to the Zevy scheduler.

- `src/gui/ui.zig` — exports `components`, `layout`, `renderer`, and `systems`
- `src/gui/*` — UI primitives, layout engines (flex, grid, anchor, dock), render systems

The `RayGuiPlugin` registers a `GuiStage` and several systems:

- uiInputSystem — maps engine input to GUI events
- flexLayoutSystem / gridLayoutSystem / anchorLayoutSystem / dockLayoutSystem — layout pass
- uiRenderSystem — draws the UI after the normal draw stage

Examples are available in `src/gui/examples.zig` and unit tests in `src/gui/ui_tests.zig` and `src/gui/ui_render_tests.zig`.

---

## Embed

The `embed` module exposes helpers to include binary assets in the compiled artifact. See `embed.zig` in `src/builtin`. Use `embedded://` URIs with the asset manager to reference compiled-in assets.

- `src/builtin/embed.zig` — helper utilities

---

## Plugins

Zevy Raylib defines several convenience plugins that register and configure services with the Zevy ECS system.

- `src/app.plugin.zig` — Raylib application and RayGui plugin
- `src/assets.plugin.zig` — assets resource (wraps `io.Assets`)
- `src/input.plugin.zig` — registers `InputManager` and the input system

### RaylibPlugin (`app.plugin.zig`)

Provides:

- Window creation (`rl.initWindow`) with title, width, height
- Audio device initialization (`rl.initAudioDevice`)
- Logging of the window and audio state
- Cleaning up in `deinit` (close audio and window)

Usage example:

```zig
try plugs.add(RaylibPlugin, RaylibPlugin{ .title = "My App", .width = 800, .height = 600 });
```

### RayGuiPlugin (`app.plugin.zig`)

Wires RayGui into the Zevy scheduler and adds UI systems to a `GuiStage`. The plugin registers the UI systems and the `uiRenderSystem` into the drawing stage.

### AssetsPlugin (`assets.plugin.zig`)

Creates and registers `io.Assets` in the ECS as a resource so your systems can call `loadAsset` and `process` through the `io` API.

### InputPlugin (`input.plugin.zig`)

Registers the `InputManager` resource and attaches an input `update` system that polls device state and emits events each frame.

---

## Examples & Tests

- `src/gui/examples.zig` — GUI usage examples
- `src/input/tests.zig` — Input unit tests
- `src/io/*_tests.zig` — IO tests for asset managers and loaders

To run tests for the package use the workspace-level `zig build test` or per-package tests using `zig build test` inside the package directory.

---

## Contributing

- Follow existing Zig patterns
- Register new plugins in `src/root.zig` by adding them to `plug()`
- Add unit tests beside features in the `src/*` directory
