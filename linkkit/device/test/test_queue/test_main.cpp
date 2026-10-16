// LinkKit's queue (linkkit/SPEC.md §4), alone: a fake app, the wire in and
// the wire out. Each test names the rule it pins.
#include <unity.h>

#include "../kit_fakes.h"

using kitfake::ended;
using kitfake::has;
using kitfake::Rig;
using linkkit::Link;
using linkkit::QueueView;

void setUp() {}
void tearDown() {}

// §4 table, `now`: plays at once; a busy `do` playing ends `cut`, `now`.
static void test_now_plays_at_once_and_cuts_a_busy_one() {
  Rig r;
  r.doLine(1, "say", "now");
  TEST_ASSERT_EQUAL(1, int(r.app.started.size()));
  TEST_ASSERT_TRUE(r.kit.queue().held);
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
  TEST_ASSERT_FALSE(r.kit.queue().resting);  // it starts busy
  r.doLine(2, "show", "now");
  TEST_ASSERT_EQUAL_STRING(ended(1, "cut", "now").c_str(), r.usb.text.substr(r.usb.text.find("{\"t\":\"ev\"")).c_str());
  TEST_ASSERT_EQUAL(2, int(r.app.started.size()));
  TEST_ASSERT_EQUAL(2, r.kit.queue().id);
  TEST_ASSERT_EQUAL_STRING("show", r.kit.queue().name);
}

// §4: a resting `do`, replaced, ends `done`.
static void test_a_resting_do_replaced_ends_done() {
  Rig r;
  r.doLine(1, "say", "now");
  r.app.k().rest(r.app.started[0].key);
  TEST_ASSERT_TRUE(r.kit.queue().resting);
  r.doLine(2, "say", "now");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "done")));
  r.app.k().rest(r.app.started[1].key);
  r.doLine(3, "say", "next");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "done")));
  r.app.k().rest(r.app.started[2].key);
  r.doLine(4, "say", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(3, "done")));
  TEST_ASSERT_EQUAL(4, r.kit.queue().id);
}

// §4 table, `now`: the `do`s waiting keep waiting.
static void test_now_leaves_the_queue_waiting() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  TEST_ASSERT_EQUAL(1, r.kit.queue().waiting);
  r.doLine(3, "show", "now");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "cut", "now")));
  TEST_ASSERT_EQUAL(3, r.kit.queue().id);
  TEST_ASSERT_EQUAL(1, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL(2, r.kit.queue().wait[0].id);
}

// §4 table, `next`: plays when nothing is playing, else waits at the back
// of the queue; the queue moves when the one playing rests or ends, oldest
// first.
static void test_next_waits_in_order_and_moves_when_the_holder_rests_or_ends() {
  Rig r;
  r.doLine(1, "say", "next");
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);  // free: it plays
  r.doLine(2, "say", "next");
  r.doLine(3, "show", "next");
  TEST_ASSERT_EQUAL(1, int(r.app.started.size()));
  TEST_ASSERT_EQUAL(2, r.kit.queue().waiting);
  r.app.k().rest(r.app.started[0].key);  // 1 rests: 2 replaces it, and 1 is done
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL(2, int(r.app.started.size()));
  TEST_ASSERT_EQUAL(2, r.kit.queue().id);
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "done")));
  r.app.k().ended(r.app.started[1].key);  // 2 ends: 3 plays
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL(3, int(r.app.started.size()));
  TEST_ASSERT_EQUAL(3, r.kit.queue().id);
  TEST_ASSERT_EQUAL_STRING("show", r.app.started[2].name.c_str());
  TEST_ASSERT_TRUE(r.app.started[2].play == linkkit::Play::kNext);
  TEST_ASSERT_EQUAL(0, r.kit.queue().waiting);
}

// §4: the queue moves at the exact millisecond the app rests or ends the
// one playing, whatever steps the clock takes (App::nextDue).
static void test_the_queue_moves_at_the_exact_millisecond() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  r.app.timers.push_back({r.app.started[0].key, 1234, false});  // 1 rests at 1234
  r.clock(4000);
  TEST_ASSERT_EQUAL(2, int(r.app.started.size()));
  TEST_ASSERT_EQUAL_UINT32(1234, r.app.started[1].t);
  // A timer the clock is already past fires at the next step: here the
  // do's own message, so nothing is playing when it arrives.
  r.app.timers.push_back({r.app.started[1].key, 2500, true});
  r.doLine(3, "say", "next");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "done")));
  TEST_ASSERT_EQUAL(3, int(r.app.started.size()));
  TEST_ASSERT_EQUAL_UINT32(4000, r.app.started[2].t);
}

// §4, §9: a `next` still waiting after its ttl, 5000 ms by default, is
// `skipped`, `late`: it may start at arrival + ttl, not a millisecond after.
static void test_next_is_late_after_its_ttl() {
  TEST_ASSERT_EQUAL_UINT32(5000, linkkit::kDefaultTtlMs);
  Rig r;
  r.doLine(1, "say", "now");
  r.clock(1000);
  r.doLine(2, "say", "next");  // waits from 1000
  r.app.timers.push_back({r.app.started[0].key, 6000, false});
  r.clock(7000);
  TEST_ASSERT_EQUAL(2, int(r.app.started.size()));  // waited exactly 5000: in time
  TEST_ASSERT_EQUAL_UINT32(6000, r.app.started[1].t);

  Rig l;
  l.doLine(1, "say", "now");
  l.clock(1000);
  l.doLine(2, "say", "next");
  l.app.timers.push_back({l.app.started[0].key, 6001, false});
  l.clock(3000);
  TEST_ASSERT_EQUAL(3000, int(l.kit.queue().wait[0].leftMs));
  l.clock(6000);
  TEST_ASSERT_FALSE(has(l.usb.text, ended(2, "skipped", "late")));
  TEST_ASSERT_EQUAL(0, int(l.kit.queue().wait[0].leftMs));
  l.clock(7000);
  TEST_ASSERT_TRUE(has(l.usb.text, ended(2, "skipped", "late")));  // late at 6001, as 1 rests
  TEST_ASSERT_EQUAL(1, int(l.app.started.size()));
}

// §3, §9: `ttl` is an integer 1–60000; anything else reads as 5000.
static void test_ttl_is_held_to_its_range() {
  TEST_ASSERT_EQUAL_UINT32(60000, linkkit::kMaxTtlMs);
  const struct {
    const char* ttl;
    uint32_t reads;
  } cases[] = {{"1", 1}, {"60000", 60000}, {"0", 5000}, {"60001", 5000}, {"-5", 5000},
               {"2.5", 5000}, {"\"300\"", 5000}, {"true", 5000}, {"null", 5000}};
  for (const auto& c : cases) {
    Rig r;
    r.doLine(1, "say", "now");
    r.doLine(2, "say", "next", (std::string(",\"ttl\":") + c.ttl).c_str());
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(c.reads, r.kit.queue().wait[0].leftMs, c.ttl);
  }
}

// §4 table, `if_free`: plays when nothing plays or the one playing rests;
// otherwise `skipped`, `busy`, and never waits.
static void test_if_free_is_skipped_while_a_busy_one_plays() {
  Rig r;
  r.doLine(1, "say", "if_free");
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
  r.doLine(2, "beep", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "busy")));
  TEST_ASSERT_EQUAL(0, r.kit.queue().waiting);
  r.app.k().rest(r.app.started[0].key);
  r.doLine(3, "beep", "if_free");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "done")));
  TEST_ASSERT_EQUAL(3, r.kit.queue().id);
}

// §3: `play` missing or unknown is `next`.
static void test_play_defaults_to_next() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", nullptr);
  r.doLine(3, "say", "later");
  TEST_ASSERT_EQUAL(2, r.kit.queue().waiting);
}

// §4, starting to play: refuse is asked first; a reason skips the `do`
// with it and leaves the one playing alone.
static void test_refuse_skips_and_leaves_the_one_playing_alone() {
  Rig r;
  r.doLine(1, "say", "now");
  r.app.refuseWith = "asleep";
  r.doLine(2, "show", "now");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "asleep")));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"id\":1,"));
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
  TEST_ASSERT_EQUAL(1, int(r.app.started.size()));
  // Nothing waits or is busy-skipped without being asked: only a `do` about to play.
  size_t asked = r.app.refused.size();
  r.doLine(3, "show", "next");
  r.doLine(4, "show", "if_free");
  TEST_ASSERT_EQUAL(int(asked), int(r.app.refused.size()));
}

// §4: a refused head of the queue is skipped and the next one tries.
static void test_a_refused_head_is_skipped_and_the_next_tries() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "show", "next");
  r.doLine(3, "say", "next");
  r.app.refuseNames = {"show"};
  r.app.k().ended(r.app.started[0].key);
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "done")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "no")));
  TEST_ASSERT_EQUAL(3, r.kit.queue().id);
}

// §4, §9: at most 4 `do`s wait; a fifth ends the oldest `skipped`, `full`.
static void test_at_most_4_wait() {
  TEST_ASSERT_EQUAL(4, linkkit::kMaxWaiting);
  Rig r;
  r.doLine(1, "say", "now");
  for (int id = 2; id <= 5; ++id) r.doLine(id, "say", "next");
  TEST_ASSERT_EQUAL(4, r.kit.queue().waiting);
  TEST_ASSERT_FALSE(has(r.usb.text, "\"full\""));
  r.doLine(6, "say", "next");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "full")));
  TEST_ASSERT_EQUAL(4, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL(3, r.kit.queue().wait[0].id);
  TEST_ASSERT_EQUAL(6, r.kit.queue().wait[3].id);
}

// §4, the app reports: a report for a key that isn't playing, or has
// already ended, is ignored: each do gets exactly one `ended`.
static void test_each_do_ends_exactly_once() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  const uint32_t one = r.app.started[0].key;
  r.app.k().ended(one + 1);  // the waiting `do`'s key: not the one playing
  r.app.k().rest(one + 1);
  r.app.k().ended(12345);
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
  TEST_ASSERT_FALSE(r.kit.queue().resting);
  r.app.k().ended(one, linkkit::How::kCut, "tap");
  r.app.k().ended(one);
  r.app.k().rest(one);
  r.usbLine("{\"t\":\"dbg.ping\"}");  // 2 plays
  r.app.k().cut("again");
  r.usbLine("{\"t\":\"dbg.clock\",\"freeze\":60000}");
  TEST_ASSERT_EQUAL(1, kitfake::count(r.usb.text, "\"id\":1,"));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "cut", "tap")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "cut", "again")));
  TEST_ASSERT_EQUAL(1, kitfake::count(r.usb.text, "\"id\":2,"));
}

// §4: cut(why) ends the one playing `cut` with why; dropWaiting(why) ends
// every waiting `do` `skipped` with why, and leaves the one playing.
static void test_cut_and_drop_waiting() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  r.doLine(3, "show", "next");
  r.app.k().dropWaiting("mic");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "mic")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(3, "skipped", "mic")));
  TEST_ASSERT_EQUAL(0, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
  r.app.k().cut("tap");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "cut", "tap")));
  TEST_ASSERT_FALSE(r.kit.queue().held);
  r.app.k().cut("tap");  // nothing playing: ignored
  TEST_ASSERT_EQUAL(1, kitfake::count(r.usb.text, "\"why\":\"tap\""));
}

// §4: dropWaiting(why, link) ends only the `do`s waiting that came in on
// that link (the host an input reached), each on its own link; the rest
// keep their places.
static void test_drop_waiting_from_one_link() {
  Rig r;
  r.kit.connected();
  r.doLine(1, "say", "now");
  r.bleLine("{\"t\":\"do\",\"id\":2,\"name\":\"say\",\"play\":\"next\"}");
  r.doLine(3, "show", "next");
  r.bleLine("{\"t\":\"do\",\"id\":4,\"name\":\"beep\",\"play\":\"next\"}");
  r.app.k().dropWaiting("mic", Link::kUsb);
  TEST_ASSERT_TRUE(has(r.usb.text, ended(3, "skipped", "mic")));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"kind\":\"ended\""));
  TEST_ASSERT_EQUAL(2, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL(2, r.kit.queue().wait[0].id);
  TEST_ASSERT_EQUAL(4, r.kit.queue().wait[1].id);
  r.app.k().dropWaiting("mic", Link::kBle);
  TEST_ASSERT_TRUE(has(r.ble.text, ended(2, "skipped", "mic")));
  TEST_ASSERT_TRUE(has(r.ble.text, ended(4, "skipped", "mic")));
  TEST_ASSERT_EQUAL(0, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
}

// §4, same id again: a do whose id matches one still playing or waiting
// comes from a later launch of the host; the old one is forgotten without
// an `ended`, and the new one is handled as usual.
static void test_the_same_id_again_forgets_the_old_do() {
  Rig r;
  r.doLine(5, "say", "now");
  r.doLine(5, "show", "next");  // the one playing was a lost launch's: nothing plays
  TEST_ASSERT_EQUAL(2, int(r.app.started.size()));
  TEST_ASSERT_EQUAL_STRING("show", r.kit.queue().name);
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));
  r.doLine(6, "say", "next");
  r.doLine(6, "beep", "next");
  TEST_ASSERT_EQUAL(1, r.kit.queue().waiting);
  TEST_ASSERT_EQUAL_STRING("beep", r.kit.queue().wait[0].name);
  TEST_ASSERT_FALSE(has(r.usb.text, "\"kind\":\"ended\""));
  // The old one's key is no longer playing: its reports are ignored.
  r.app.k().ended(r.app.started[0].key);
  TEST_ASSERT_EQUAL_STRING("show", r.kit.queue().name);
  r.app.k().ended(r.app.started[1].key);
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL(1, kitfake::count(r.usb.text, "\"kind\":\"ended\""));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(5, "done")));
}

// §4: dbg.reset ends the one playing `cut`, `reset`, and every waiting
// `do` `skipped`, `reset`, then resets the app.
static void test_reset_ends_the_whole_queue() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "cut", "reset")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "reset")));
  TEST_ASSERT_TRUE(has(r.usb.text, "{\"t\":\"dbg.reset\"}\n"));
  TEST_ASSERT_EQUAL(1, r.app.resets);
  TEST_ASSERT_FALSE(r.kit.queue().held);
  TEST_ASSERT_EQUAL(0, r.kit.queue().waiting);
}

// §3: a name not in hello.does is `skipped`, `unknown`, at once; the app
// never sees it.
static void test_an_unknown_name_is_skipped() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "dance", "now");
  r.usbLine("{\"t\":\"do\",\"id\":3}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "skipped", "unknown")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(3, "skipped", "unknown")));
  TEST_ASSERT_EQUAL(1, int(r.app.started.size()));
  TEST_ASSERT_EQUAL(1, int(r.app.refused.size()));
  TEST_ASSERT_EQUAL(1, r.kit.queue().id);
}

// §2, §3: an id is an integer 1–2147483647; anything else reads as missing,
// and a do without one still plays but gets no `ended`.
static void test_a_do_without_a_valid_id_plays_unanswered() {
  TEST_ASSERT_EQUAL(2147483647, linkkit::kMaxId);
  for (const char* id : {"0", "-1", "2147483648", "1.5", "\"7\"", "true", "null"}) {
    Rig r;
    r.usbLine(std::string("{\"t\":\"do\",\"id\":") + id + ",\"name\":\"say\",\"play\":\"now\"}");
    TEST_ASSERT_EQUAL_MESSAGE(1, int(r.app.started.size()), id);
    TEST_ASSERT_EQUAL_MESSAGE(0, r.app.started[0].id, id);
    r.doLine(0, "dance", "now");
    r.doLine(9, "say", "now");  // cuts it, unanswered
    r.usbLine("{\"t\":\"dbg.reset\"}");
    TEST_ASSERT_EQUAL_MESSAGE(1, kitfake::count(r.usb.text, "\"kind\":\"ended\""), id);  // only 9's
  }
  Rig r;
  r.usbLine("{\"t\":\"do\",\"id\":2147483647,\"name\":\"say\"}");
  r.usbLine("{\"t\":\"dbg.reset\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2147483647, "cut", "reset")));
}

// §3, §5: `ended` goes back on the link its do came in on.
static void test_ended_goes_back_where_the_do_came_from() {
  Rig r;
  r.kit.connected();
  r.bleLine("{\"t\":\"do\",\"id\":1,\"name\":\"say\",\"play\":\"now\"}");
  r.doLine(2, "say", "now");
  TEST_ASSERT_TRUE(has(r.ble.text, ended(1, "cut", "now")));
  TEST_ASSERT_FALSE(has(r.usb.text, "\"id\":1,"));
  r.bleLine("{\"t\":\"do\",\"id\":3,\"name\":\"say\",\"play\":\"now\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "cut", "now")));
  TEST_ASSERT_FALSE(has(r.ble.text, "\"id\":2,"));
}

// §3: args reach the app untouched, `{}` when missing, and a waiting `do`
// keeps its own copy, whatever messages come after it.
static void test_args_arrive_untouched_even_after_waiting() {
  Rig r;
  r.doLine(1, "say", "now", ",\"args\":{\"take\":\"hi\",\"n\":[1,2.5,{\"deep\":\"é\"}]}");
  TEST_ASSERT_EQUAL_STRING("{\"take\":\"hi\",\"n\":[1,2.5,{\"deep\":\"é\"}]}", r.app.started[0].args.c_str());
  r.doLine(2, "say", "next", ",\"args\":{\"who\":{\"agent\":\"claude\",\"thread\":\"fix-nav\"}}");
  r.doLine(3, "say", "next");
  for (int i = 0; i < 20; ++i) r.usbLine("{\"t\":\"state\",\"pad\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}");
  r.app.k().ended(r.app.started[0].key);
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL_STRING("{\"who\":{\"agent\":\"claude\",\"thread\":\"fix-nav\"}}", r.app.started[1].args.c_str());
  r.app.k().ended(r.app.started[1].key);
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_EQUAL_STRING("null", r.app.started[2].args.c_str());  // none: reads as {}
}

// §4: an app may report from inside its hooks. A `do` that ends as it
// starts lets the next one in; a refuse that ends the one playing (as
// Boop's reply ends listening) leaves the queue to the `do` it let through.
static void test_hooks_may_report_at_once() {
  Rig r;
  r.doLine(1, "say", "now");
  r.doLine(2, "say", "next");
  r.doLine(3, "say", "next");
  r.app.endAtStart = true;
  r.app.k().rest(r.app.started[0].key);
  r.usbLine("{\"t\":\"dbg.ping\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, ended(1, "done")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(2, "done")));
  TEST_ASSERT_TRUE(has(r.usb.text, ended(3, "done")));
  TEST_ASSERT_FALSE(r.kit.queue().held);

  Rig h;
  h.doLine(1, "say", "now");
  h.app.endHolderInRefuse = true;
  h.doLine(2, "show", "now");
  TEST_ASSERT_TRUE(has(h.usb.text, ended(1, "done")));  // the app's own end, not `cut`
  TEST_ASSERT_FALSE(has(h.usb.text, "\"why\":\"now\""));
  TEST_ASSERT_EQUAL(2, h.kit.queue().id);
}

// §7: dbg.state carries the queue (its `turn`), `holder` null when nothing
// plays.
static void test_dbg_state_shows_the_queue() {
  Rig r;
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"turn\":{\"holder\":null,\"waiting\":[]}}"));
  r.doLine(44, "say", "now");
  r.doLine(45, "show", "next", ",\"ttl\":4000");
  r.doLine(0, "beep", "next");
  r.clock(800);
  r.usb.text.clear();
  r.usbLine("{\"t\":\"dbg.state\"}");
  TEST_ASSERT_TRUE(has(r.usb.text, "\"turn\":{\"holder\":{\"id\":44,\"name\":\"say\",\"resting\":false},\"waiting\":["
                                   "{\"id\":45,\"name\":\"show\",\"left_ms\":3200},{\"id\":null,\"name\":\"beep\",\"left_ms\":4200}]}"));
  TEST_ASSERT_TRUE(has(r.usb.text, "\"rx\":{\"state\":0,\"do\":3}"));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_now_plays_at_once_and_cuts_a_busy_one);
  RUN_TEST(test_a_resting_do_replaced_ends_done);
  RUN_TEST(test_now_leaves_the_queue_waiting);
  RUN_TEST(test_next_waits_in_order_and_moves_when_the_holder_rests_or_ends);
  RUN_TEST(test_the_queue_moves_at_the_exact_millisecond);
  RUN_TEST(test_next_is_late_after_its_ttl);
  RUN_TEST(test_ttl_is_held_to_its_range);
  RUN_TEST(test_if_free_is_skipped_while_a_busy_one_plays);
  RUN_TEST(test_play_defaults_to_next);
  RUN_TEST(test_refuse_skips_and_leaves_the_one_playing_alone);
  RUN_TEST(test_a_refused_head_is_skipped_and_the_next_tries);
  RUN_TEST(test_at_most_4_wait);
  RUN_TEST(test_each_do_ends_exactly_once);
  RUN_TEST(test_cut_and_drop_waiting);
  RUN_TEST(test_drop_waiting_from_one_link);
  RUN_TEST(test_the_same_id_again_forgets_the_old_do);
  RUN_TEST(test_reset_ends_the_whole_queue);
  RUN_TEST(test_an_unknown_name_is_skipped);
  RUN_TEST(test_a_do_without_a_valid_id_plays_unanswered);
  RUN_TEST(test_ended_goes_back_where_the_do_came_from);
  RUN_TEST(test_args_arrive_untouched_even_after_waiting);
  RUN_TEST(test_hooks_may_report_at_once);
  RUN_TEST(test_dbg_state_shows_the_queue);
  return UNITY_END();
}
