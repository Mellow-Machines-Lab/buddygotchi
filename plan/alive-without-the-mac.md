# Alive without the Mac

Updated 2026-11-02. Built, firmware only, on both faces. Asked for by the owner
on 2026-11-01: super basic. With
no Mac, Boop is nearly dead: touches are held (`Behaviour::held`, with
`noApp`) and it shows the plug. A pet should still be a pet.

With no app:
- It breathes, and falls asleep after a while, on the board's own clock.
- A poke or a stroke gets the board's own reaction, in its last mood, with
  no brain. Anything that needs the Mac (opening a thread, the drawer's
  rows) does nothing.
- No voice that needs the brain; the board's own small sounds are fine.
- The plug follows `plan/lock-and-unlock.md`'s last item: never on a sleeping
  Boop until you touch it. Awake with no Mac, the plug still shows, small,
  so a real disconnection can be seen.
- When the Mac returns, a small hello, by the board. No new message.

Firmware only, on both faces if it costs nothing, else the gel. Tests pin the
held rule's change and that nothing is emitted as if the Mac heard it.

## As built

- Alone, the look is resting, in the last mood, at full light. After
  `kAloneSleepMs` (5 minutes) since the Mac went quiet or the last touch, it is
  asleep. The `no_app` look no longer shows, so no pack changes.
- `Behaviour::sleepsOn` still means asleep with no plug. It now holds in two
  cases: Boop was asleep when the Mac went quiet and nobody touched it (lock and
  unlock's rule), or it fell asleep alone. A touch ends both: it wakes Boop, and
  the plug shows until it sleeps again.
- `held` no longer includes no app, so a touch plays. `heldFromMac` keeps it for
  the Mac's reactions, which stay refused. Push-to-talk does nothing alone.
- With no app `tap`, `gesture`, `talk_on` and `talk_off` are not emitted. The one
  `ev` left is the drawer's shut, if it was open when the Mac went.
- The hello is the `notice` animation, on the first state after a silence. None
  at power-on, on needs you, on a Boop the state says is asleep, or face down.
