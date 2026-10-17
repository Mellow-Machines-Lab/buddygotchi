# LinkKit: the spec

Updated 2026-10-16. The contract between a host (a Mac app) and a small
device with a screen, a light or a speaker: four messages, how the device
decides what plays when, and the rules both sides keep. It's language
neutral: the Swift host library (`Sources/LinkKit`) and the C++ device
library (`device/`) both implement it, and a port to another language
matches this file. [README.md](README.md) is the overview. It was pulled
out of Boop, a desk creature whose app and firmware are one app on it.

## 1. The idea

The host tells the device how things are and asks it to play things. The
device draws them however it likes and says what happened. Neither side
gives orders: a `do` asks for something the device may play, make wait,
skip, or draw its own way.

```
host → device    state   how things are now (sent whole, on every change and every 10 s)
                 do      please play this (exactly one answer comes back)
device → host    hello   who I am and what I can play (a host's bare hello asks for it)
                 ev      something happened: a tap, a hold, how a `do` went
```

Tools also send `dbg.*` messages over USB (§7).

## 2. Framing

- Every message is one JSON object on one line, UTF-8, ending in `\n`,
  with its type in `t`. A receiver drops a trailing `\r`, skips empty
  lines, and buffers a line that spans packets or reads until its newline.
- A message is at most **512 bytes** either way, not counting its newline; the
  device drops a longer one whole, and a host never sends one (a `do` that
  would be longer fails at once). Only `dbg.*` replies over USB may be
  longer (§7).
- Receivers ignore types and fields they don't know, so a new optional
  field or type never breaks an older peer.
- **The kit owns a few field names and the app owns the rest.** `state` is
  entirely the app's. `do` carries the app's details in `args`, and `ev` in
  `data`. `hello` has six kit fields; any other field in it is the app's.
- There are no app-defined message types. An app extends the protocol by
  choosing `state` keys, `do` names and `ev` kinds. `dbg.*` is the one
  namespace an app adds types to.
- A number field that must be an integer in a range (`id`, `ttl`, `kit`,
  `ended`'s `data.id`) and isn't one reads as missing.

## 3. Messages

### `hello`: device → host

```json
{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.4.0","boot":"5d0e19a3","does":["react","starting","listening"],"voice":"1aace295d219"}
```

| Field | Meaning |
| --- | --- |
| `kit` | The protocol version, 1 (§6) |
| `app` | Which kind of device this is. A host drives only the `app` it was written for |
| `id` | The device's permanent id |
| `fw` | The firmware version |
| `boot` | 8 hex digits picked at random each time the device powers on, or missing. A different one from the last means the device restarted (§5) |
| `does` | The `do` names it plays, at most 32. The whole `hello` fits in one message |
| any other field | The app's (Boop's `voice`) |

`does` lists names only; what each name means lives on the host. A
`hello` longer than 512 bytes would be dropped on the way, so the
device sends it without the app's fields, or not at all when even the
kit's don't fit, and says so in `dbg.ping` (`hello_long`, its whole
length, §7).

**A host asks for it** with a bare `{"t":"hello"}` (any field in it is
ignored); the device answers with its `hello` on that link. A host sends
one first on every link-up, before its `state` (and may ask again while
none has come, as a lost message would leave it waiting), because the device may
still count the link as live and so not greet the host's first message
(§5): a host relaunched within 30 s over USB, or one taking over a
Bluetooth link the system kept up. Older firmware ignores the type (§2).

### `state`: host → device

```json
{"t":"state","base":"working","mood":"calm","busy":1,"vol":6}
```

The app's own map, sent whole every time, so a lost or late message is
fixed by the next. The kit reads none of it; any `state` counts as the host
speaking (§5).

### `do`: host → device

```json
{"t":"do","id":44,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}
```

| Field | Meaning |
| --- | --- |
| `id` | 1–2147483647. The host picks it, starting somewhere random each launch and counting up, so an id an earlier launch left on the device isn't reused. Every `do` from a host has one and gets exactly one `ended` (§4). A `do` without a valid id still plays but gets no answer (handy typed by hand) |
| `name` | One of `hello.does`. Any other gets `skipped`, `unknown` at once |
| `play` | `now`, `next` or `if_free` (§4). `next` when missing or unknown |
| `ttl` | How long a `next` may wait in the queue, in ms, 1–60000. 5000 when missing. A host sends it only with `next`; the device ignores it otherwise |
| `args` | The app's details, handed to its handler untouched. `{}` when missing |

### `ev`: device → host

```json
{"t":"ev","kind":"tap","did":"poked"}
{"t":"ev","kind":"tap","did":"dip","data":{"on":44}}
{"t":"ev","kind":"ended","data":{"id":44,"how":"cut","why":"tap"}}
```

| Field | Meaning |
| --- | --- |
| `kind` | What happened. The kit reserves `ended`; every other kind is the app's |
| `did` | Optional: what the device already did about it on its own |
| `data` | Optional: the app's details, or `ended`'s |

The device sends an app's `ev` on every live link (§5), and an `ended` on
the link its `do` came in on.

## 4. The queue: who decides what plays

The device decides, because it's the only one that knows when something
has finished. The host never times the device's outputs.

**The queue's head is the `do` playing; the rest wait behind it in order
of arrival.** The kit doesn't decide what's on screen: the app draws
whatever layers it likes. The `do` playing is **busy** (don't cut me) or
**resting** (the part that matters is over: anything may replace it, and
it then ends `done`).

| `play` | Nothing playing, or the one playing is resting, and nothing waiting | Otherwise |
| --- | --- | --- |
| `now` | Plays at once | Plays at once; a busy one playing ends `cut`, `now`. The `do`s waiting keep waiting |
| `next` | Plays at once | Waits at the back of the queue. Still waiting after its `ttl`: `skipped`, `late` |
| `if_free` | Plays at once | `skipped`, `busy` |

- **Starting to play.** First the app's `refuse` is asked. A reason ends
  the `do` `skipped` with that reason, and the one playing is left alone.
  Otherwise a resting one playing ends `done` (a busy one, for `now`,
  ends `cut`, `now`), the new `do` plays, busy, and the app's `onDo` runs.
- **The queue moves** whenever the `do` playing rests or ends: the oldest
  waiting `do` whose wait hasn't passed its `ttl` tries to start; one that
  has is `skipped`, `late`. A refused head is skipped and the next tries.
- **The app reports** through four calls: `rest(id)` (the one playing may
  be replaced now), `ended(id, how, why)` (it's over: `done`, or `cut`
  with why), `cut(why)` (the app cuts the one playing, `cut` with why, as
  for a tap) and `dropWaiting(why)` (every waiting `do` ends `skipped`
  with why; or only those from one link, when what drops them reached
  only that link's host). A report for an id that isn't playing, or has
  already ended, is ignored: each `do` gets exactly one `ended`.
- **At most 4 `do`s wait.** A fifth ends the oldest waiting as `skipped`,
  `full`. A `do` whose `args` the device can't keep while it waits (they'd
  take a whole message once written again) ends `skipped`, `full` at once.
- **Same id again.** A `do` whose id matches one still playing or waiting
  comes from a later launch of the host (ids never repeat within a
  launch): the old one is forgotten without an `ended`, and the new one
  is handled as usual.
- **`dbg.reset`** ends the one playing `cut`, `reset`, and every waiting
  `do` `skipped`, `reset`.
- **Things the device does on its own** (a tap's reflex, a held button)
  don't go through the queue: the app draws them, and cuts the one
  playing with `cut(why)` only when it actually cuts it.

**How a `do` can end:**

| `how` | `why` | Meaning |
| --- | --- | --- |
| `done` | — | It played through, or it was resting and something replaced it |
| `cut` | `now` | A `now` `do` replaced it |
| `cut` | `reset` | A tool sent `dbg.reset` |
| `cut` | the app's | The app cut it: `tap`, `needs_you` |
| `skipped` | `late` | It waited longer than its `ttl` |
| `skipped` | `busy` | It was `if_free` and a busy one was playing |
| `skipped` | `full` | Too many `do`s were waiting, or there was no room to keep its `args` while it waited |
| `skipped` | `unknown` | The device doesn't have that name |
| `skipped` | `reset` | A tool sent `dbg.reset` while it waited |
| `skipped` | the app's | The app's `refuse` or `dropWaiting` |

`why` is a short lower-case word; app reasons use `[a-z_]` too.

## 5. Lifecycle

| When | What happens |
| --- | --- |
| A link comes up | The host sends a bare `hello` (§3), then its latest `state`, at once |
| The device hears a host's `hello`, or its first message on a link it didn't count as live (any type but `dbg.*`) | It sends `hello` on that link, once for a first message that is a `hello` |
| The host gets a `hello` | It answers with its latest `state`, so a device that rebooted catches up at once |
| While the link is up | The host sends `state` on every change and at least every 10 s. The device sends `hello` again when something in it changes, and 60 s after the last one on the link the host last spoke on |
| 30 s with no message from the host | The device treats the host as gone: USB is no longer live, and it drops a Bluetooth link so it can advertise again |
| The link drops | The host ends every `do` still waiting for its `ended` as failed (the device may play on) |
| A `hello` whose `boot` differs from the last one the host heard | The device restarted and forgot every `do`: the host ends each still waiting as failed (`the device restarted`) at once, rather than at its give-up time, below. The host keeps the last `boot` across links, so a restart over a link that stayed up, or one that dropped, is caught either way |
| No `ended` by a `do`'s `ttl` (5000 ms for `now` and `if_free`) plus 60 s after it was sent | The host gives up on it as failed: a message was lost. Only the `ended` stops that wait (resting never reaches the host), so a `do` that may play longer than its `ttl` plus 60 s must end sooner, or be split into several `do`s |

A link is *live* for device → host messages while it's connected
(Bluetooth) or the host has spoken on it in the last 30 s (USB).
Answering the host's first message instead of announcing at connect
means the `hello` is always heard: by the time a host sends a message,
it's listening. The host's own `hello` covers a host that finds the link
already live, which the device has no way to tell from the host before.

## 6. Versioning

- There's one number, `hello.kit`. Adding a field, an `ev` kind, a `do`
  name or a message type never changes it; it changes only when something
  that exists changes meaning.
- Capabilities are names, not numbers: a host checks `does` before
  sending. An app's own compatibility goes in its own `hello` field.
- A host that meets a `kit` it doesn't know, or another `app`, keeps the
  link and keeps sending `state` (so a device that's flashed while the link
  stays up still hears it and answers with its new `hello`), but sends no
  `do`, drops the device's `ev`s, and says the firmware is too new, too
  old or not its device. A
  `do` asked for before a `hello` has come fails at once.

## 7. Debug messages (USB only)

Types starting `dbg.` are for tools and tests over USB; over Bluetooth the
device ignores them. Each gets one reply with the same `t`; an unknown one
gets none. The kit handles five, and an app adds its own.

| Message | Reply |
| --- | --- |
| `{"t":"dbg.ping"}` | `{"t":"dbg.ping","kit":1,"fw":…,"up":ms,"link":…,"ble":…,"name":…}` plus the app's vitals, and `hello_long` (the whole `hello`'s length) when the `hello` is longer than 512 bytes (§3). `up` is ms since power-on; `link` the link the host last spoke on (`usb`, `ble` or `none`); `ble` the Bluetooth radio (`off`, `idle`, `adv` or `conn`); `name` the name it advertises, missing when none |
| `{"t":"dbg.state"}` | `{"t":"dbg.state",…,"clock":{"now":T,"frozen":bool},"rx":{"state":N,"do":N},"turn":{…}}`: the app's fields first, then the kit's clock, the `state` and `do` messages it has read, and the queue (below) |
| `{"t":"dbg.clock","freeze":T}`, `{"step":MS}`, `{"run":true}` | `{"t":"dbg.clock","now":T,"frozen":bool}`. A frozen clock runs again by itself after 60 s with no `dbg.*` |
| `{"t":"dbg.shot"}` | `{"t":"dbg.shot","w":W,"h":H,"bytes":N,"crc":C}`, then one line of the frame's N bytes in base64, C their CRC-32. What the bytes are is the app's (Boop's: a palette and an index per pixel, or RGB565 pixels). An app that draws no frame sends 0 for each, and an empty line |
| `{"t":"dbg.reset"}` | `{"t":"dbg.reset"}`, after §4's reset and the app's own |

`dbg.state`'s `turn` is the queue: `{"holder":{"id":44,"name":"say","resting":false},"waiting":[{"id":45,"name":"show","left_ms":3200},{"id":null,"name":"beep","left_ms":4200}]}`,
`holder` the `do` playing, null when nothing is, and `waiting` the rest
in order.

The device's randomness, which the app draws its choices from, repeats
for tools: freezing the clock at T reseeds it from T, and `dbg.reset`
from 0, as a kit made with its clock frozen (a simulator) starts. A
device whose clock runs from power-on seeds it from its boot id (§3), so
no two power-ons make the same choices.

## 8. Transport

Both links carry the same messages, and the device answers on the link
a message came in on.

- **Bluetooth:** the Nordic UART Service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`;
  RX `…0002` host → device, written without response; TX `…0003` device →
  host, notified). The device is the peripheral and advertises as
  `<Prefix>-XXXX`, the prefix the app's. It asks for a 247-byte MTU and
  cuts notifications to MTU − 3.
  - `XXXX` is the last two bytes of the device's Bluetooth MAC in
    uppercase hex, the same two bytes as its `hello.id` (§3) in lowercase
    after the app's id prefix: `Boop-54FE` says `"id":"b00p-54fe"`.
  - The host takes the first device whose name has its prefix, or, told
    one device's whole name, only that one. Several hosts, or one host
    with a link per device, each named for its own, never take each
    other's device.
  - The link has no pairing or encryption. So anyone in range can connect to a
    device and send it messages, and a device that takes the name hears the
    host's. Send nothing over it you wouldn't show on the screen; `dbg.*`
    messages are refused over Bluetooth (§7).
  - The host cuts each message to the write size it's allowed, and keeps
    them in an outbox so a burst never loses part of one. A newer `state`
    replaces one not yet started; no other message is dropped, since the host waits for
    every `do`'s `ended` (§5). Once states merge only `do`s pile up, so a
    backlog past 4 KB means the link is stuck: the host gives it up and
    connects again, which ends what waited as failed (§5).
  - A device still connected to the system doesn't advertise, so the host
    first takes over a link the system holds to one, and scans otherwise.
    It's up once subscribed to TX. An attempt that isn't up within 10 s,
    or fails on the way, is cancelled and tried again, and a device whose
    UART service changed (a reflash) is connected again. After a drop or
    a failed attempt the host looks again after 1 s, doubling to 5 s, and
    back to 1 s once a link is up.
- **USB:** the board's serial port, owned by a bridge process that shares
  it on a Unix socket, so tools and the host can both use it:
  `linkkit-bridge`, or any bridge that keeps its rules.
  - The socket is for its user alone (mode 0600). `linkkit-bridge`
    shares it at `$TMPDIR/linkkit-bridge.sock` unless told otherwise, a
    folder only that user can open.
  - Every whole line from the board goes to every client, and every whole
    line from a client goes to the board whole, so two clients' lines
    never interleave.
  - The bridge never waits on a client: one that falls 4 MB behind (it
    stopped reading) is dropped, so it can't stall the others.
  - The host connects to the socket, and again every second while it
    can't. A write that can't finish within 250 ms drops the connection,
    which comes back a second later, so a stuck bridge can't freeze the
    host. Partial writes share that one deadline, including when a bridge
    keeps reading a little at a time.

## 9. Limits

| Limit | Value |
| --- | --- |
| A message | 512 bytes each way |
| `does` | 32 names |
| `do`s waiting | 4 |
| `ttl` | 5000 ms by default, 1–60000 |
| Ids | 1–2147483647 |
| `state` keepalive / host gone | 10 s / 30 s |
| `hello` repeat | 60 s |
| A host gives up on an `ended` | `ttl` + 60 s |
| Bluetooth backlog before the host gives the link up | 4 KB |
| A bridge client's backlog before it's dropped | 4 MB |
| A host's write to the bridge | 250 ms |
