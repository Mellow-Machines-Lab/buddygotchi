// The voice player: the voice file's takes found by id, a `say` of one or two
// takes played whole at their recorded pitch (11.025 kHz resampled 2× to
// 22.05 kHz), volume, the cut's fade, and the mouth. The voice file is the chosen character
// pack's voice/voice.bin, as the board reads it from its card.
#include <unity.h>

#include "voice_file.h"  // internal/firmware/

#include <cstdlib>
#include <cstring>
#include <vector>

#include "voice/player.h"

void setUp() {}
void tearDown() {}

namespace {

voice::Say say(const char* id, uint8_t vol = 6, const char* then = nullptr) {
  int a = voice::takeIndex(id);
  return voice::makeSay(a, then ? voice::takeIndex(then) : -1, vol);
}

std::vector<uint8_t> renderAll(voice::Player& p, size_t extra = 0) {
  std::vector<uint8_t> out(p.total() + extra);
  size_t made = p.render(out.data(), out.size());
  TEST_ASSERT_EQUAL_UINT32(p.total(), made);
  return out;
}

int peak(const std::vector<uint8_t>& v) {
  int m = 0;
  for (uint8_t s : v) m = std::abs(int(s) - 128) > m ? std::abs(int(s) - 128) : m;
  return m;
}

// A clip's samples, straight from the voice file.
std::vector<uint8_t> samples(const voice::Clip& c) {
  std::vector<uint8_t> d(c.len);
  TEST_ASSERT_TRUE(voicefile::source().read(c.at, d.data(), c.len));
  return d;
}

}  // namespace

// The Mac's take table (the pack's mac/takes.tsv) was written with it: the same takes by
// the same ids, which the board finds in the voice file's sorted index.
void test_the_voice_file_finds_takes_by_id() {
  NEEDS_VOICE_PACK();
  TEST_ASSERT_TRUE(voice::fileOpen());
  TEST_ASSERT_EQUAL(2722, voice::takeCount());
  TEST_ASSERT_EQUAL(12, std::strlen(voice::assetsVersion()));
  int go = voice::takeIndex("previous.go");
  TEST_ASSERT_TRUE(go >= 0);
  TEST_ASSERT_EQUAL_STRING("Go", voice::takeText(go));
  TEST_ASSERT_EQUAL_STRING("previous.go", voice::takeId(go));
  TEST_ASSERT_EQUAL(go, voice::takeIndex("previous.go"));  // already loaded: the same handle
  int boom = voice::takeIndex("new.d15");
  TEST_ASSERT_EQUAL_STRING("Bada bing bada boom", voice::takeText(boom));
  int longest = voice::takeIndex("phase1.phrase.delegate.little-reinforcements__determined__contained");
  TEST_ASSERT_EQUAL_STRING("Little reinforcements", voice::takeText(longest));
  TEST_ASSERT_EQUAL(-1, voice::takeIndex("banana"));
  TEST_ASSERT_EQUAL(-1, voice::takeIndex(nullptr));
  TEST_ASSERT_NULL(voice::takeText(-1));
  TEST_ASSERT_EQUAL_UINT32(0, voice::takeMs(-1));
  // A handle goes stale once enough other takes have been loaded.
  const char* others[] = {"new.d01", "new.d02", "new.d03", "new.d04", "new.d05", "new.d06", "new.d07", "new.d08"};
  for (const char* id : others) TEST_ASSERT_TRUE(voice::takeIndex(id) >= 0);
  TEST_ASSERT_NULL(voice::takeText(go));
  // With no voice file there's no voice at all.
  voice::closeFile();
  TEST_ASSERT_EQUAL(-1, voice::takeIndex("previous.go"));
  TEST_ASSERT_EQUAL_STRING("none", voice::assetsVersion());
  TEST_ASSERT_TRUE(voicefile::open());
}

// A take plays whole: two output samples for each of its own, so its
// length in ms is the recording's (638 ms for "Go", 7042 samples).
void test_a_take_plays_whole_at_its_pitch() {
  NEEDS_VOICE_PACK();
  voice::Say l = say("previous.go");
  TEST_ASSERT_EQUAL_UINT32(7042, l.a.len);
  TEST_ASSERT_EQUAL_UINT32(2 * 7042, voice::saySamples(l));
  TEST_ASSERT_EQUAL_UINT32(638, voice::takeMs(l.take));
  voice::Player p;
  p.start(l);
  TEST_ASSERT_TRUE(p.playing());
  TEST_ASSERT_EQUAL(l.take, p.take());
  TEST_ASSERT_EQUAL_UINT32(2 * 7042, p.total());
  l.vol = 10;
  p.start(l);
  std::vector<uint8_t> out = renderAll(p, 500);
  TEST_ASSERT_FALSE(p.playing());
  // Even samples are the recording's; odd ones the midpoint of two.
  std::vector<uint8_t> d = samples(l.a);
  for (uint32_t i = 0; i + 2 < p.total(); i += 2) {
    TEST_ASSERT_INT_WITHIN(1, d[i / 2], out[i]);
    TEST_ASSERT_INT_WITHIN(1, (int(d[i / 2]) + d[i / 2 + 1]) / 2, out[i + 1]);
  }
  for (size_t i = p.total(); i < out.size(); ++i) TEST_ASSERT_EQUAL_UINT8(128, out[i]);  // then silence
  TEST_ASSERT_EQUAL_UINT32(0, p.render(out.data(), 10));
}

// A `say` of two takes plays the first, 180 ms of
// silence, then the second, and says both words; its mouth follows each.
void test_a_say_of_two_takes() {
  NEEDS_VOICE_PACK();
  voice::Say l = say("previous.tsk", 10, "phase1.word.test.test__annoyed__contained");
  TEST_ASSERT_TRUE(l.then >= 0);
  TEST_ASSERT_EQUAL_UINT32(2 * (l.a.len + voice::kGapSamples + l.b.len), voice::saySamples(l));
  TEST_ASSERT_EQUAL_UINT32(1377 + 180 + 868, voice::sayMs(l.take, l.then));  // a pair, its gap between
  voice::Player p;
  p.start(l);
  std::vector<uint8_t> out = renderAll(p);
  std::vector<uint8_t> a = samples(l.a), b = samples(l.b);
  for (uint32_t i = 0; i + 2 < 2 * l.a.len; i += 2) TEST_ASSERT_INT_WITHIN(1, a[i / 2], out[i]);
  for (uint32_t i = 2 * l.a.len + 2; i < 2 * (l.a.len + voice::kGapSamples); ++i) TEST_ASSERT_EQUAL_UINT8(128, out[i]);
  const uint32_t at = 2 * (l.a.len + voice::kGapSamples);
  for (uint32_t i = 0; i + 2 < 2 * l.b.len; i += 2) TEST_ASSERT_INT_WITHIN(1, b[i / 2], out[at + i]);
  // The mouth: the first take's, shut in the gap, then the second's.
  for (uint32_t ms = 0; ms < 1377; ++ms) TEST_ASSERT_EQUAL(voice::mouthOpen(l.take, ms), voice::sayMouthOpen(l.take, l.then, ms));
  for (uint32_t ms = 1377; ms < 1377 + 180; ++ms) TEST_ASSERT_FALSE(voice::sayMouthOpen(l.take, l.then, ms));
  for (uint32_t ms = 0; ms < 868; ++ms)
    TEST_ASSERT_EQUAL(voice::mouthOpen(l.then, ms), voice::sayMouthOpen(l.take, l.then, 1377 + 180 + ms));
  // A second take the voice file doesn't have: the first alone.
  voice::Say one = say("previous.tsk", 10, "banana");
  TEST_ASSERT_EQUAL(-1, one.then);
  TEST_ASSERT_EQUAL_UINT32(2 * one.a.len, voice::saySamples(one));
}

void test_an_unknown_take_plays_nothing() {
  voice::Player p;
  p.start(say("banana"));
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL(-1, p.take());
  TEST_ASSERT_EQUAL_UINT32(0, voice::saySamples(say("banana")));
  uint8_t s[16];
  TEST_ASSERT_EQUAL_UINT32(0, p.render(s, sizeof(s)));
  for (uint8_t v : s) TEST_ASSERT_EQUAL_UINT8(128, v);
}

// A `say` cut short, hushed or replaced by another `say`, fades
// from where it was over 4 ms instead of stepping to silence in one
// sample, which clicks.
void test_a_cut_fades_instead_of_clicking() {
  NEEDS_VOICE_PACK();
  for (int how = 0; how < 2; ++how) {
    voice::Player p;
    p.start(say("new.d14", 10));
    uint8_t s = 128;
    for (uint32_t i = 0; i < p.total() && std::abs(int(s) - 128) < 60; ++i) p.render(&s, 1);
    TEST_ASSERT_TRUE(std::abs(int(s) - 128) >= 60);  // cut at a loud sample
    if (how == 0) p.stop();
    else p.start(say("banana"));  // replaced by a `say` that plays nothing
    std::vector<uint8_t> out(200);
    p.render(out.data(), out.size());
    TEST_ASSERT_INT_WITHIN(2, s, out[0]);
    for (size_t i = 1; i < out.size(); ++i) TEST_ASSERT_INT_WITHIN(2, out[i - 1], out[i]);
    TEST_ASSERT_EQUAL_UINT8(128, out[22050 * 4 / 1000]);  // gone after 4 ms
  }
}

void test_volume_scales_and_zero_mutes() {
  NEEDS_VOICE_PACK();
  voice::Player p;
  p.start(say("new.d14", 10));
  int loud = peak(renderAll(p));
  p.start(say("new.d14", 5));
  int half = peak(renderAll(p));
  TEST_ASSERT_TRUE(loud > 90);
  TEST_ASSERT_INT_WITHIN(3, loud / 2, half);
  p.start(say("new.d14", 0));
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL_UINT32(0, p.total());
}

// The mouth follows the take's loud frames, one per 20 ms (220 samples at
// 11.025 kHz), and is shut before, after and with no take.
void test_the_mouth_follows_the_take() {
  NEEDS_VOICE_PACK();
  int go = voice::takeIndex("previous.go");
  int open = 0;
  for (uint32_t ms = 0; ms < voice::takeMs(go); ++ms) open += voice::mouthOpen(go, ms);
  TEST_ASSERT_TRUE(open > 0);
  TEST_ASSERT_FALSE(voice::mouthOpen(go, 0));  // "Go" starts quiet
  TEST_ASSERT_TRUE(voice::mouthOpen(go, 40));  // and opens at its 3rd frame
  TEST_ASSERT_FALSE(voice::mouthOpen(go, 100000));
  TEST_ASSERT_FALSE(voice::mouthOpen(-1, 100));
}

// A card that fails mid-`say` drops the rest of the `say`,
// fading out, and isn't asked again for every sample.
void test_a_card_failing_mid_say_ends_it() {
  NEEDS_VOICE_PACK();
  struct Failing : voice::Source {
    int reads = 0, after = -1, failed = 0;  // after: how many more reads work once armed
    bool read(uint32_t at, void* buf, uint32_t n) override {
      if (after >= 0 && ++reads > after) return ++failed, false;
      return voicefile::source().read(at, buf, n);
    }
  } card;
  TEST_ASSERT_TRUE(voice::openFile(&card));
  voice::Player p;
  p.start(say("new.d20"));
  TEST_ASSERT_TRUE(p.playing());
  card.after = 2;  // the card fails a couple of refills into the `say`
  std::vector<uint8_t> out(512);
  for (int i = 0; i < 400 && p.playing(); ++i) p.render(out.data(), out.size());
  TEST_ASSERT_FALSE(p.playing());
  TEST_ASSERT_EQUAL(1, card.failed);
  TEST_ASSERT_TRUE(voicefile::open());
}

// A take is looked up on the main loop, as its `do` arrives: the index's
// ids are read as the file opens, so a lookup reads the card once, for the
// take's record and mouth, not a dozen times over a binary search.
void test_a_lookup_reads_the_card_once() {
  NEEDS_VOICE_PACK();
  struct Counting : voice::Source {
    int reads = 0;
    bool read(uint32_t at, void* buf, uint32_t n) override {
      ++reads;
      return voicefile::source().read(at, buf, n);
    }
  } card;
  TEST_ASSERT_TRUE(voice::openFile(&card));
  card.reads = 0;
  TEST_ASSERT_TRUE(voice::takeIndex("new.d15") >= 0);
  TEST_ASSERT_EQUAL(2, card.reads);  // its record, then its mouth
  card.reads = 0;
  TEST_ASSERT_EQUAL(-1, voice::takeIndex("banana"));
  TEST_ASSERT_EQUAL(0, card.reads);
  TEST_ASSERT_TRUE(voicefile::open());
}

int main() {
  UNITY_BEGIN();
  if (!voicefile::open()) std::printf("no voice file: the chosen character pack has none\n");
  RUN_TEST(test_the_voice_file_finds_takes_by_id);
  RUN_TEST(test_a_take_plays_whole_at_its_pitch);
  RUN_TEST(test_a_say_of_two_takes);
  RUN_TEST(test_an_unknown_take_plays_nothing);
  RUN_TEST(test_a_cut_fades_instead_of_clicking);
  RUN_TEST(test_volume_scales_and_zero_mutes);
  RUN_TEST(test_the_mouth_follows_the_take);
  RUN_TEST(test_a_card_failing_mid_say_ends_it);
  RUN_TEST(test_a_lookup_reads_the_card_once);
  return UNITY_END();
}
