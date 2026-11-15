## Pastimes: the table (firmware/src/render/gel/pastimes.cpp) and an estimate for one day
Rows: 52. By look: {'kWorking': 19, 'kIdle': 24, 'kNeedsYou': 4, 'kAsleep': 5}. By growth stage that first knows it: {1: 28, 2: 9, 3: 15}. Moves: coffee-reach, melt, stretch-break. Tag rows: busy-typing (busy), frantic-typing (frantic), pastime:morning-stretch (morning), pastime:night-drowse (night), pastime:party-bounce (party|newyear|lunar|programmers), pastime:friday-sway (friday), pastime:winter-shiver (winter), pastime:halloween-wobble (halloween), pastime:valentines-swoon (valentines), deep-snore (night).

Assumed day: Working 131 min in 40 stretches [(40, 20), (180, 12), (420, 6), (1200, 2)]; Idle 260 min in 40 stretches [(60, 20), (300, 12), (900, 6), (2700, 2)]; NeedsYou 13 min in 10 stretches [(20, 6), (90, 3), (400, 1)]; Asleep 90 min in 2 stretches [(1800, 1), (3600, 1)]. Share of the time a pastime may be dealt (no live call drawn, no Moment, no finger): {'kWorking': 0.5, 'kIdle': 0.9, 'kNeedsYou': 1.0, 'kAsleep': 1.0}. No calendar tag on, not busy or frantic, not morning. A bit or take with no clip is taken as 3 s. 400 simulated days each.

| pastime | look | needs | stage | move | clip s | per day, Hatchling (stage 1) | per day, Sprout (2) | per day, Buddy or Chonk (3+) |
|---|---|---|---:|---|---:|---:|---:|---:|
| snore-bubble | Asleep | wait 240s | 1 |  | 5.2 | 188.8 | 142.9 | 142.3 |
| sheep | Asleep | wait 120s | 2 |  | 6.0 | 0.0 | 123.4 | 123.9 |
| roll-over | Asleep | wait 60s | 1 |  | 4.2 | 211.8 | 120.1 | 120.5 |
| snuggle | Idle | tier5 (600s) | 1 |  | 6.0 | 191.7 | 141.8 | 92.3 |
| snooze | Idle | tier5 (600s) | 2 |  | 6.0 | 0.0 | 142.0 | 92.1 |
| daydream | Idle | tier5 (600s) | 3 |  | 6.0 | 0.0 | 0.0 | 91.2 |
| book | Idle | tier3 (120s) | 3 |  | 5.6 | 0.0 | 0.0 | 80.4 |
| water | Idle | tier3 (120s) | 3 |  | 4.4 | 0.0 | 0.0 | 80.0 |
| game | Idle | tier3 (120s) | 3 |  | 5.2 | 0.0 | 0.0 | 80.0 |
| sneeze-and-shake | Idle | tier1 (30s) | 1 |  | 3.0 | 222.8 | 100.3 | 70.2 |
| hop | Idle | tier1 (30s) | 1 |  | 2.4 | 222.2 | 100.2 | 69.6 |
| hopeful | Idle | tier1 (30s) | 1 |  | 2.6 | 222.5 | 99.6 | 69.5 |
| look-around | Idle | tier1 (30s) | 1 |  | 3.2 | 222.3 | 100.6 | 69.5 |
| yawn-and-settle | Idle | tier1 (30s) | 1 |  | 3.0 | 222.6 | 100.0 | 69.4 |
| bubble | Idle | tier2 (60s) | 2 |  | 4.4 | 0.0 | 213.3 | 68.7 |
| doodle | Idle | tier2 (60s) | 2 |  | 4.6 | 0.0 | 213.5 | 68.0 |
| dream | Asleep | wait 1800s | 1 |  | 3.0 | 60.8 | 59.5 | 59.2 |
| brb | Idle | tier4 (300s) | 3 |  | 6.0 | 0.0 | 0.0 | 41.9 |
| tower | Idle | tier4 (300s) | 3 |  | 5.6 | 0.0 | 0.0 | 41.9 |
| dance | Idle | tier4 (300s) | 3 |  | 5.2 | 0.0 | 0.0 | 41.3 |
| plane | Idle | tier4 (300s) | 3 |  | 5.2 | 0.0 | 0.0 | 41.2 |
| wave | NeedsYou | wait 30s | 1 |  | 2.8 | 39.8 | 39.9 | 39.9 |
| done-beat | Working | tier1 (30s) | 1 |  | 2.6 | 93.9 | 38.1 | 30.5 |
| hum | Working | tier1 (30s) | 1 |  | 3.6 | 94.1 | 37.9 | 30.5 |
| peek | Working | tier1 (30s) | 1 |  | 2.4 | 93.5 | 37.9 | 30.3 |
| sip | Working | tier1 (30s) | 1 |  | 3.2 | 94.7 | 38.1 | 30.3 |
| nod | Working | tier2 (60s) | 2 |  | 3.0 | 0.0 | 43.4 | 24.8 |
| ponder | Working | tier2 (60s) | 2 |  | 3.4 | 0.0 | 43.1 | 24.6 |
| read | Working | tier2 (60s) | 2 |  | 5.0 | 0.0 | 43.4 | 24.5 |
| snack | Working | tier4 (300s) | 2 |  | 3.6 | 0.0 | 43.7 | 22.9 |
| refill | Working | tier4 (300s) | 3 |  | 4.2 | 0.0 | 0.0 | 22.9 |
| stretch | Working | tier4 (300s) | 2 |  | 2.6 | 0.0 | 44.0 | 22.4 |
| sticky | Working | tier3 (120s) | 3 |  | 3.2 | 0.0 | 0.0 | 22.3 |
| bop | Working | tier3 (120s) | 3 |  | 4.0 | 0.0 | 0.0 | 22.2 |
| drum | Working | tier3 (120s) | 3 |  | 3.0 | 0.0 | 0.0 | 22.1 |
| phones-on | Working | tier3 (120s) | 1 |  | 2.4 | 19.9 | 19.9 | 19.9 |
| coffee-reach | Working | tier3 (120s) | 3 | move | 5.0 | 0.0 | 0.0 | 14.3 |
| tap | NeedsYou | wait 120s | 1 |  | 2.6 | 12.8 | 12.7 | 12.7 |
| stretch-break | Working | tier5 (600s) | 3 | move | 10.5 | 0.0 | 0.0 | 10.2 |
| melt | Working | tier4 (300s) | 3 | move | 6.2 | 0.0 | 0.0 | 7.2 |
| watch | NeedsYou | wait 300s | 1 |  | 4.2 | 3.8 | 3.8 | 3.8 |
| busy-typing | Working | tag busy | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| frantic-typing | Working | tag frantic | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:morning-stretch | Idle | tag morning | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:night-drowse | Idle | tag night | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:party-bounce | Idle | tag party|newyear|lunar|programmers | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:friday-sway | Idle | tag friday | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:winter-shiver | Idle | tag winter | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:halloween-wobble | Idle | tag halloween | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:valentines-swoon | Idle | tag valentines | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| drowsy | NeedsYou | wait 600s | 1 |  | 5.2 | 0.0 | 0.0 | 0.0 |
| deep-snore | Asleep | tag night | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |

Stage 1: about 2218 pastimes a day; 17 of 52 rows at least once a day. Under once a day: ponder, read, nod, bop, drum, sticky, coffee-reach, refill, snack, melt, stretch-break, stretch, busy-typing, frantic-typing, bubble, doodle, book, game, water, brb, tower, dance, plane, snooze, daydream, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, sheep, deep-snore

Stage 2: about 2103 pastimes a day; 26 of 52 rows at least once a day. Under once a day: bop, drum, sticky, coffee-reach, refill, melt, stretch-break, busy-typing, frantic-typing, book, game, water, brb, tower, dance, plane, daydream, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, deep-snore

Stage 3: about 2051 pastimes a day; 41 of 52 rows at least once a day. Under once a day: busy-typing, frantic-typing, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, deep-snore

### When a calendar tag is on (idle stretches of the same assumed day, stage 3)
| tags on | tag row | its share of idle pastimes | idle pastimes |
|---|---|---:|---:|
| morning | pastime:morning-stretch | 42% | 1341 a day |
| friday | pastime:friday-sway | 42% | 1341 a day |
| morning+friday | pastime:morning-stretch | 31% | 1389 a day |
| morning+friday | pastime:friday-sway | 32% | 1389 a day |
| night | pastime:night-drowse | 42% | 1341 a day |