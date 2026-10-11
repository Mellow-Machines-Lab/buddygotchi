# How LinkKit works

Updated 2026-10-11. The tour of LinkKit: the four messages, the turn, and
each side's library. [README.md](README.md) is the short version;
[SPEC.md](SPEC.md) has every rule exactly.

```mermaid
flowchart LR
    H["🖥️ Your Mac app<br/><i>LinkKit (Swift)</i>"] -- "state · do" --> D["🟨 Your device<br/><i>LinkKit device library (C++)</i>"]
    D -- "hello · ev" --> H
```

## The four messages

Each is one JSON line of at most 512 bytes, the same over Bluetooth and
USB:

| Message | Way | What |
| --- | --- | --- |
| `state` | host → device | How things are now, the app's own map, sent whole on every change and every 10 s |
| `do` | host → device | Please play this: a name the device plays, how it takes the turn (`play`), and the app's `args`. Exactly one `ended` comes back |
| `hello` | device → host | Who it is (`app`, `id`, `fw`), the protocol's version (`kit`) and the names it plays (`does`). The host asks for it with a bare `{"t":"hello"}`, first on every link-up |
| `ev` | device → host | Something happened: a tap, a held button, and how each `do` ended (`ended`) |

```json
{"t":"state","base":"working","mood":"calm","busy":1,"vol":6}
{"t":"do","id":44,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}
{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.4.0","does":["react","starting","listening"],"voice":"1aace295d219"}
{"t":"ev","kind":"tap","did":"poked"}
{"t":"ev","kind":"ended","data":{"id":44,"how":"cut","why":"tap"}}
```

The kit owns a few field names and the app owns the rest: all of
`state`, a `do`'s `args`, an `ev`'s kinds and `data`, and any other field
in `hello`. Tools also send `dbg.*` messages over USB (SPEC.md §7).

## The turn, in five lines

The device, not the host, decides when each request plays. Here a
celebration waits its turn behind a busy animation, and a tap cuts it
short:

```mermaid
sequenceDiagram
    participant Host
    participant Device
    Host->>Device: do task_complete (play: next, ttl 5 s)
    Note over Device: waits: something busy holds the turn
    Note over Device: the holder rests, so it plays
    Device-->>Host: ev tap
    Device-->>Host: ev ended {how: cut, why: tap}
```

1. One call holds the turn at a time: busy (don't cut me) or resting
   (the part that matters is over, and anyone may take over).
2. `now` takes the turn at once, cutting a busy holder; `next` waits its
   turn, up to its `ttl` (5 s by default); `if_free` plays only if
   nothing busy holds it.
3. The device's app says when its holder rests or ends, what it refuses,
   and what cuts it (a tap, a button).
4. Every `do` gets exactly one `ended`: `done`, `cut` or `skipped`, with
   a short word why (`now`, `late`, `busy`, `tap`).
5. The host never times what the device plays: it sends at once and
   waits for the `ended`, giving up only at the `ttl` plus 60 s.

## The host, in Swift

It builds from source with Swift 6 (Xcode or the Command Line Tools) on
macOS 13 or later, on Foundation and CoreBluetooth alone:

```swift
// Package.swift
.package(path: "../linkkit"),
// and in a target's dependencies:
.product(name: "LinkKit", package: "linkkit"),
```

A `DeviceLink` keeps the device's picture true with `state`, sends each
`do` and hands its end to a completion called exactly once, and passes on
every other `ev`. USB writes share one [deadline per line](SPEC.md#8-transport),
so even a bridge reading slowly cannot hold up the app indefinitely.
It runs on one queue of yours: the transport calls back
on its own thread, so hop to the queue, and tick the link about once a
second for the keepalive and the give-ups. This drives the lamp from the
device library's example (below) through the USB bridge's socket, with
the board plugged in and `swift run linkkit-bridge --socket /tmp/lamp.sock`
running beside it:

```swift
import Foundation
import LinkKit

/// Drives a lamp over its USB bridge: its level, a blink, its button.
final class LampHost: @unchecked Sendable {
    let queue = DispatchQueue(label: "lamp")  // the link's one queue
    let link = DeviceLink(app: "lamp", transport: SocketTransport(path: "/tmp/lamp.sock"), log: { print($0) })
    var keep: [Any] = []

    func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func start() {
        link.onEvent = { ev in
            if ev.kind == "press" { print("pressed; the lamp \(ev.did ?? "did nothing")") }
        }
        link.transport?.start(
            onLine: { [self] line in queue.async { [self] in link.receive(line, now: now()) } },
            onConnection: { [self] up in queue.async { [self] in link.connection(up, now: now()) } })
        queue.async { [self] in link.update(state: ["level": 40], now: now()) }
        let tick = DispatchSource.makeTimerSource(queue: queue)
        tick.schedule(deadline: .now() + 1, repeating: 1)
        tick.setEventHandler { [self] in link.tick(now: now()) }
        tick.resume()
        keep = [tick]
    }

    /// Blinks twice once the lamp's turn is free, and says how it went.
    func blink() {
        queue.async { [self] in
            link.do("blink", args: ["times": 2], now: now()) { outcome in print("blink:", outcome) }
        }
    }
}
```

- **Ids** start somewhere random each launch and count up, so a call an
  earlier launch left on the device can't be mistaken for a new one.
- **Who asked** for each line goes to `onSend` with it, for a debug log:
  the name you pass as `by:` on `do` (`app` when you don't), and `link` for
  the link's own lines, every `state` and its ask for `hello`.
- **A `do` fails at once**, with nothing sent, when there's no link, no
  `hello` yet, the name isn't in `hello.does` or the line would be too
  long; later when the link drops or no `ended` comes in time. The
  completion's `Outcome` says which, in plain words. A `state` too long
  for a line isn't sent either: the last one that fit stands.
- **`hello`** is `link.hello`, the app's own fields among it; `onHello`
  hears a new one. The link asks for it (`{"t":"hello"}`, which the
  device library answers) when the link comes up, and every 10 s until
  it comes, since a device that still counts the host as there (an app
  relaunched within 30 s, or one taking over a Bluetooth link macOS
  kept) doesn't say it unasked. A device whose `kit` or `app` doesn't
  fit, or one your app finds too old by a line of its own
  (`link.incompatible`, for firmware from before it had a `hello`),
  still gets `state` but no `do`, its `ev`s are dropped, and
  `link.trouble` says why (`.tooOld`, `.tooNew`, `.otherApp`), with what
  to do about it in its `description`, for your settings screen.
- **Bluetooth:** `BLETransport(prefix: "Lamp")` finds `Lamp-XXXX` on the
  Nordic UART service, cuts lines to the write size and keeps a newer
  `state` from queueing behind an old one; it never drops a `do`, and
  gives up a link too stuck to take them. macOS kills a process that
  touches Bluetooth without the right to, so tests, and anything started
  from an agent's shell, use `SocketTransport`. The link isn't paired or
  encrypted, so anyone in range can reach the device (SPEC.md §8).
- **USB:** `linkkit-bridge` owns the board's serial port and shares it on
  a Unix socket, so your app (`SocketTransport`) and your tools can use
  the board at once: `--port` names the port when there's more than one
  USB serial port, `--socket` where to share it (`$TMPDIR/linkkit-bridge.sock` by
  default), `--baud` the board's
  rate (460800 by default). An app can run one itself (`Bridge`), and ask
  whether one answers on a socket (`SocketTransport.answers`).

`Wire` builds and reads the lines themselves, and `JSON` and `JSONObject`
(keys in order) are the app's parts of them.

## The device, in C++

The device's half is in [device/](device/README.md): C++17 on
ArduinoJson, with no Arduino headers in its portable part, so it runs on
a Mac for tests and simulators. Its `Kit` reads the host's lines, keeps
the links, says `hello`, runs the turn, routes `ev` and answers the
`dbg.*` messages; your `App` says what it plays, draws it, and reports
when its holder rests, ends or is cut. Its README has the lamp, whole.
Boop's firmware is another app on it.

## Boop

Boop, the desk creature LinkKit was pulled out of, is one app on it: its
own `state` fields, `do` names, `hello`'s `voice` and taps, on the Mac
and in its firmware.

## Development

```sh
swift test --scratch-path .build/tests
```

The tests use Swift Testing: `LinkKitTests` (framing and chunking, the
Bluetooth outbox and reconnect timing, the socket transport, the bridge
on a pseudo-terminal, the wire, the keepalive, `hello` and trouble, ids,
exactly one end, the give-up and a link that drops), each naming the
SPEC.md section it checks. The device half has
its own PlatformIO project for its tests
([device/README.md](device/README.md)). The package depends on nothing
but Foundation and CoreBluetooth, and on nothing outside this folder.
