// LinkKit's helpers, alone (linkkit/SPEC.md §2, §7, §8): line reassembly
// over USB and Bluetooth packets, the screenshot's encoding, the clock.
#include <unity.h>

#include <cstring>
#include <algorithm>
#include <string>
#include <vector>

#include "linkkit/clock.h"
#include "linkkit/codec.h"
#include "linkkit/line_reader.h"
#include "linkkit/packets.h"

void setUp() {}
void tearDown() {}

static int feedAll(linkkit::LineReader& r, const char* s, std::string* last) {
  int lines = 0;
  for (const char* p = s; *p; ++p) {
    if (r.feed(*p)) {
      ++lines;
      *last = std::string(r.line(), r.length());
    }
  }
  return lines;
}

static void test_lines_reassemble_across_chunks() {
  linkkit::LineReader r;
  std::string last;
  TEST_ASSERT_EQUAL_INT(0, feedAll(r, "{\"t\":\"st", &last));
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, "ate\"}\r\n{\"t\"", &last));
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"state\"}", last.c_str());
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, ":1}\n\n", &last));  // empty lines are skipped
  TEST_ASSERT_EQUAL_STRING("{\"t\":1}", last.c_str());
}

static void test_overlong_lines_are_dropped_whole() {
  linkkit::LineReader r;
  std::string last, big(linkkit::LineReader::kMax + 10, 'x');
  big += "\nok\n";
  TEST_ASSERT_EQUAL_INT(1, feedAll(r, big.c_str(), &last));
  TEST_ASSERT_EQUAL_STRING("ok", last.c_str());
}

// BLE: packets of any size, split anywhere, come back as the same lines.
static void test_ble_packets_reassemble_through_the_ring() {
  const std::string msg = "{\"t\":\"state\",\"base\":\"working\",\"busy\":2}\n{\"t\":\"do\",\"id\":7,\"name\":\"poked\"}\n";
  for (size_t size : {1, 3, 20, 61, 182, 244}) {
    linkkit::ByteRing<1024> ring;
    linkkit::LineReader r;
    std::vector<std::string> got;
    for (size_t at = 0; at < msg.size(); at += size) {
      size_t k = std::min(size, msg.size() - at);
      TEST_ASSERT_EQUAL_UINT32(k, ring.put(reinterpret_cast<const uint8_t*>(msg.data()) + at, k));
      uint8_t c;
      while (ring.take(c))
        if (r.feed(char(c))) got.emplace_back(r.line(), r.length());
    }
    TEST_ASSERT_EQUAL_INT(2, int(got.size()));
    TEST_ASSERT_EQUAL_STRING("{\"t\":\"state\",\"base\":\"working\",\"busy\":2}", got[0].c_str());
    TEST_ASSERT_EQUAL_STRING("{\"t\":\"do\",\"id\":7,\"name\":\"poked\"}", got[1].c_str());
  }
}

// BLE: a host cut off mid-line (a long `do` takes two writes) leaves part
// of it in the ring. The disconnect ends it there (ble.cpp), so it comes
// out as a line of its own that fails to parse, and the next host's first
// line comes out whole.
static void test_a_dropped_links_part_line_doesnt_join_the_next() {
  linkkit::ByteRing<1024> ring;
  linkkit::LineReader r;
  const std::string part = "{\"t\":\"do\",\"id\":7,\"name\":\"re";
  const std::string next = "{\"t\":\"hello\"}\n";
  ring.put(reinterpret_cast<const uint8_t*>(part.data()), part.size());
  ring.endLine();  // the link dropped
  ring.put(reinterpret_cast<const uint8_t*>(next.data()), next.size());
  std::vector<std::string> got;
  uint8_t c;
  while (ring.take(c))
    if (r.feed(char(c))) got.emplace_back(r.line(), r.length());
  TEST_ASSERT_EQUAL_INT(2, int(got.size()));
  TEST_ASSERT_EQUAL_STRING(part.c_str(), got[0].c_str());
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"hello\"}", got[1].c_str());
  // With nothing left over, it's only an empty line, which is skipped.
  ring.endLine();
  ring.put(reinterpret_cast<const uint8_t*>(next.data()), next.size());
  got.clear();
  while (ring.take(c))
    if (r.feed(char(c))) got.emplace_back(r.line(), r.length());
  TEST_ASSERT_EQUAL_INT(1, int(got.size()));
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"hello\"}", got[0].c_str());
}

static void test_ring_drops_what_does_not_fit_and_wraps() {
  linkkit::ByteRing<8> ring;
  const uint8_t a[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
  TEST_ASSERT_EQUAL_UINT32(8, ring.put(a, 10));
  TEST_ASSERT_EQUAL_UINT32(2, ring.dropped());
  uint8_t c = 0;
  for (int i = 0; i < 5; ++i) ring.take(c);
  TEST_ASSERT_EQUAL_UINT8(5, c);
  TEST_ASSERT_EQUAL_UINT32(5, ring.put(a, 5));  // wraps around the end
  std::vector<uint8_t> rest;
  while (ring.take(c)) rest.push_back(c);
  TEST_ASSERT_EQUAL_INT(8, int(rest.size()));
  TEST_ASSERT_EQUAL_UINT8(6, rest[0]);
  TEST_ASSERT_EQUAL_UINT8(1, rest[3]);
  TEST_ASSERT_EQUAL_UINT8(5, rest[7]);
}

static void collect(void* ctx, const uint8_t* data, size_t n) {
  static_cast<std::vector<std::string>*>(ctx)->emplace_back(reinterpret_cast<const char*>(data), n);
}

static void test_packet_writer_sends_whole_lines_in_payload_chunks() {
  std::vector<std::string> pkts;
  linkkit::PacketWriter w(collect, &pkts);
  w.setPayload(20);
  const std::string line = "{\"t\":\"hello\",\"kit\":1,\"app\":\"lamp\",\"id\":\"lamp-7f3a\",\"fw\":\"0.4.0\"}";
  w.write(line.data(), 30);
  TEST_ASSERT_EQUAL_INT(0, int(pkts.size()));  // nothing until the newline
  w.write(line.data() + 30, line.size() - 30);
  w.write("\n", 1);
  std::string joined;
  for (auto& p : pkts) {
    TEST_ASSERT_TRUE(p.size() <= 20);
    joined += p;
  }
  TEST_ASSERT_EQUAL_INT(int((line.size() + 1 + 19) / 20), int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING((line + "\n").c_str(), joined.c_str());

  pkts.clear();
  w.setPayload(244);  // a negotiated MTU of 247
  const char* two = "{\"t\":\"ev\",\"kind\":\"tap\",\"did\":\"poked\"}\n{\"t\":\"hello\",\"fw\":\"t\"}\n";
  w.write(two, std::strlen(two));
  TEST_ASSERT_EQUAL_INT(2, int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING("{\"t\":\"hello\",\"fw\":\"t\"}\n", pkts[1].c_str());
}

static void test_packet_writer_drops_overlong_lines_and_clears() {
  std::vector<std::string> pkts;
  linkkit::PacketWriter w(collect, &pkts);
  std::string big(linkkit::LineReader::kMax + 5, 'x');
  w.write(big.data(), big.size());
  w.write("\nok\n", 4);
  TEST_ASSERT_EQUAL_INT(1, int(pkts.size()));
  TEST_ASSERT_EQUAL_STRING("ok\n", pkts[0].c_str());
  w.write("half", 4);
  w.clear();
  w.write("new\n", 4);
  TEST_ASSERT_EQUAL_STRING("new\n", pkts.back().c_str());
}

// A link that takes `room` packets, then none until it's given more.
struct FakeLink {
  std::vector<std::string> sent;
  int room = 0;
  static bool take(void* ctx, const uint8_t* data, size_t n) {
    FakeLink& l = *static_cast<FakeLink*>(ctx);
    if (l.room <= 0) return false;
    --l.room;
    l.sent.emplace_back(reinterpret_cast<const char*>(data), n);
    return true;
  }
};

// A link that can't take a packet keeps it waiting, in order, and never
// waits on it; one with no room left drops whole packets, and counts them.
static void test_the_outbox_keeps_what_the_link_cant_take_yet() {
  linkkit::PacketOutbox<16> box;
  FakeLink link;
  link.room = 1;
  box.send(reinterpret_cast<const uint8_t*>("abc"), 3, FakeLink::take, &link);
  box.send(reinterpret_cast<const uint8_t*>("de"), 2, FakeLink::take, &link);
  box.send(reinterpret_cast<const uint8_t*>("fghi"), 4, FakeLink::take, &link);
  TEST_ASSERT_EQUAL_INT(1, int(link.sent.size()));
  TEST_ASSERT_EQUAL_INT(2 + 2 + 2 + 4, int(box.waiting()));
  box.send(reinterpret_cast<const uint8_t*>("jklmno"), 6, FakeLink::take, &link);  // no room: dropped
  TEST_ASSERT_EQUAL_UINT32(1, box.dropped());
  link.room = 1;
  box.drain(FakeLink::take, &link);
  TEST_ASSERT_EQUAL_STRING("de", link.sent[1].c_str());
  link.room = 5;
  box.drain(FakeLink::take, &link);
  TEST_ASSERT_EQUAL_INT(3, int(link.sent.size()));
  TEST_ASSERT_EQUAL_STRING("fghi", link.sent[2].c_str());
  TEST_ASSERT_EQUAL_INT(0, int(box.waiting()));
  box.send(reinterpret_cast<const uint8_t*>("p"), 1, FakeLink::take, &link);
  TEST_ASSERT_EQUAL_STRING("p", link.sent[3].c_str());
  link.room = 0;
  box.send(reinterpret_cast<const uint8_t*>("q"), 1, FakeLink::take, &link);
  box.clear();
  TEST_ASSERT_EQUAL_INT(0, int(box.waiting()));
}

static void sink(void* ctx, const char* text, size_t n) { static_cast<std::string*>(ctx)->append(text, n); }

static void test_base64_matches_rfc4648() {
  const char* cases[][2] = {{"", ""}, {"f", "Zg=="}, {"fo", "Zm8="}, {"foo", "Zm9v"}, {"foobar", "Zm9vYmFy"}};
  for (auto& c : cases) {
    std::string out;
    linkkit::Base64Writer w(sink, &out);
    // Split the input to check chunking doesn't matter.
    size_t n = std::strlen(c[0]);
    w.write(reinterpret_cast<const uint8_t*>(c[0]), n / 2);
    w.write(reinterpret_cast<const uint8_t*>(c[0]) + n / 2, n - n / 2);
    w.finish();
    TEST_ASSERT_EQUAL_STRING(c[1], out.c_str());
    // And back (dbg.card's chunks).
    uint8_t back[16];
    long n2 = linkkit::base64Decode(c[1], std::strlen(c[1]), back, sizeof(back));
    TEST_ASSERT_EQUAL(long(n), n2);
    if (n) TEST_ASSERT_EQUAL_MEMORY(c[0], back, n);
  }
  uint8_t out[4];
  TEST_ASSERT_EQUAL(-1, linkkit::base64Decode("Zm9", 3, out, sizeof(out)));        // not a multiple of 4
  TEST_ASSERT_EQUAL(-1, linkkit::base64Decode("Zm*v", 4, out, sizeof(out)));       // not base64
  TEST_ASSERT_EQUAL(-1, linkkit::base64Decode("Zg==Zg==", 8, out, sizeof(out)));   // padding mid-way
  TEST_ASSERT_EQUAL(-1, linkkit::base64Decode("Zm9vYmFy", 8, out, sizeof(out)));   // too long for out
}

static void test_crc32_matches_zlib() {
  const uint8_t data[] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};
  TEST_ASSERT_EQUAL_UINT32(0xCBF43926u, linkkit::crc32(data, sizeof(data)));
  TEST_ASSERT_EQUAL_UINT32(0xCBF43926u, linkkit::crc32(data + 4, 5, linkkit::crc32(data, 4)));
}

static void test_clock_freezes_steps_and_runs() {
  linkkit::Clock c;
  c.start(false, 1000);
  TEST_ASSERT_EQUAL_UINT32(500, c.now(1500));
  c.freeze(42);
  TEST_ASSERT_EQUAL_UINT32(42, c.now(9999));
  c.step(8, 9999);
  TEST_ASSERT_EQUAL_UINT32(50, c.now(12345));
  c.run(20000);
  TEST_ASSERT_EQUAL_UINT32(60, c.now(20010));
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_lines_reassemble_across_chunks);
  RUN_TEST(test_overlong_lines_are_dropped_whole);
  RUN_TEST(test_ble_packets_reassemble_through_the_ring);
  RUN_TEST(test_a_dropped_links_part_line_doesnt_join_the_next);
  RUN_TEST(test_ring_drops_what_does_not_fit_and_wraps);
  RUN_TEST(test_packet_writer_sends_whole_lines_in_payload_chunks);
  RUN_TEST(test_packet_writer_drops_overlong_lines_and_clears);
  RUN_TEST(test_the_outbox_keeps_what_the_link_cant_take_yet);
  RUN_TEST(test_base64_matches_rfc4648);
  RUN_TEST(test_crc32_matches_zlib);
  RUN_TEST(test_clock_freezes_steps_and_runs);
  return UNITY_END();
}
