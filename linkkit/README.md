<h1 align="center">📡 LinkKit</h1>

<p align="center">
  <b>Your Mac app, meet your little gadget. Over Bluetooth or USB.</b>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="C++17" src="https://img.shields.io/badge/C%2B%2B-17-00599C?logo=cplusplus&logoColor=white">
  <img alt="ESP32" src="https://img.shields.io/badge/device-ESP32-E7352C?logo=espressif&logoColor=white">
  <img alt="MIT licence" src="https://img.shields.io/badge/licence-MIT-blue">
</p>

You built a gadget: a status light, a tiny screen with a face, a buzzer
that judges you. Now your Mac app needs to talk to it without you
inventing yet another protocol. LinkKit is the whole conversation:

```mermaid
flowchart LR
    H["🖥️ Your Mac app<br/><i>LinkKit (Swift)</i>"] -- "state · do" --> D["🟨 Your device<br/><i>LinkKit device library (C++)</i>"]
    D -- "hello · ev" --> H
```

- ✉️ **Four JSON messages.** The Mac says how things are (`state`) and
  asks for things to play (`do`). The device says who it is (`hello`)
  and what happened (`ev`).
- 🎬 **The device decides when.** Each `do` waits in a queue behind
  whatever's playing, and every one gets exactly one answer: done, cut
  or skipped.
- 🔌 **Bluetooth or USB, same messages.** A USB bridge shares the board
  with your app and your tools at once. When Bluetooth is off or not
  allowed, the transport says why, with a cause your app can act on.
- ⬆️ **Firmware updates from your app.** `Flasher` writes new firmware
  onto an ESP32 or ESP32-S3 over USB through the chip's own bootloader,
  the images you pick for the chip it reports, checks it, and restarts
  it, even when the write fails; `linkkit-flash` does the same from a
  terminal. `Bridge.hello(on:)` asks the board on a port who it is
  first.
- 🧪 **Runs on a Mac too.** The device library's core has no Arduino
  headers, so its tests and simulators run anywhere.

## Quick start

You need Swift 6 (Xcode or the Command Line Tools) on macOS 13 or later,
and PlatformIO for the device side. Run each side's tests:

```sh
cd linkkit
swift test --scratch-path .build/tests   # the Swift host
pio test -d device -e native             # the C++ device library
```

Then add the host library to your app's `Package.swift`:

```swift
.package(path: "../linkkit"),
// and in a target's dependencies:
.product(name: "LinkKit", package: "linkkit"),
```

LinkKit lives inside Boop's repository for now, so both sides are used
by path, from a checkout of it. A version to depend on by URL comes when
it has a repository of its own.

The device library's README has a whole lamp that fits on a page.

## Learn more

- **[ARCHITECTURE.md](ARCHITECTURE.md)**: the four messages, the queue,
  and driving a lamp from Swift.
- **[device/README.md](device/README.md)**: the C++ side, and how your
  app plugs into it.
- **[SPEC.md](SPEC.md)**: every message and rule, exactly.

It was pulled out of Boop, a desk creature that watches your coding
agents; Boop's app and firmware both run on it. MIT-licensed
([LICENSE](LICENSE)).
