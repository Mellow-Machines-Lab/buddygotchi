// The gel's frame time on the Mac: a stand-in for the board's
// `boopctl perf --scenes` (internal/VERIFICATION.md L2), with no board.
// It runs the simulator's board (simulator/core/) on a frozen clock, plays
// each scene's messages as perf does, steps the clock a frame at a time
// and times every frame and the face's stages (render/gel/profile.h).
//
// A Mac's microseconds are not the board's: compare scenes and stages with
// each other, and a build with the one before, never with the board's
// budgets. The board's helper core is left out, so each stage is its whole
// work on one core. bench.sh builds and runs it.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "board.h"
#include "render/gel/profile.h"
#include "render/profile.h"

namespace {

struct Quiet : linkkit::Out {
  void write(const char*, size_t) override {}
};

// Tenths of a microsecond: a Mac draws a stage in a few.
uint32_t tenthsUs() {
  using namespace std::chrono;
  return uint32_t(duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count() / 100);
}

const char* const kWorking = R"("t":"state","base":"working","act":"terminal","mood":"happy","busy":1,"vol":0)";

struct Scene {
  const char* name;
  std::string state;                // sent at the start and every 2 s, as perf does
  std::vector<std::string> at;      // sent once each, at the start, after the state
  std::vector<std::string> repeat;  // one in turn every 2 s
};

std::vector<Scene> scenes() {
  const std::string working = std::string("{") + kWorking + "}";
  return {
      {"working", working, {}, {}},
      {"stream",
       std::string("{") + kWorking +
           R"(,"busy":2,"todo":{"done":3,"total":7},"calls":[[0,0,"grep"],[1,0,"edit +18"]]})",
       {},
       {R"({"t":"do","name":"call","args":{"a":0,"w":"make","as":"bonk"}})",
        R"({"t":"do","name":"call","args":{"a":1,"w":"task","as":"helper"}})",
        R"({"t":"do","name":"call","args":{"a":0,"w":"done","as":"gather"}})"}},
      {"attention", std::string("{") + kWorking + R"(,"attn":{"id":5000,"agent":"codex","project":"perf"}})", {}, {}},
      {"idle", R"({"t":"state","base":"idle","mood":"calm","idle":1,"vol":0,"when":["day"]})", {}, {}},
      {"invite",
       R"({"t":"state","base":"idle","mood":"calm","vol":0,"when":["day"]})",
       {R"({"t":"do","name":"react","play":"now","args":{"sign":"nice!","mood":"happy","loops":1,"invite":{"skit":"win","pose":"palm","touch":"tap","payoff":"highfive","ms":60000,"xp":3,"label":"tap"}}})"},
       {}},
      // Going with you: the jam, idle and at work, and the scroll's eyes.
      {"jam", R"({"t":"state","base":"idle","mood":"calm","idle":1,"vol":0,"when":["day","music"]})", {}, {}},
      {"jam-desk", std::string("{") + kWorking + R"(,"when":["day","music"]})", {}, {}},
      {"scroll", R"({"t":"state","base":"idle","mood":"calm","idle":1,"vol":0,"when":["day","scrolling","scrolldown"]})",
       {}, {}},
  };
}

// One frame: when (ms), its tenths of a microsecond in all and by stage,
// and its pixels.
struct Sample {
  uint32_t at = 0, draw = 0;
  render::gel::Profile parts;
  uint32_t written = 0, pushed = 0;
};

// The median of one field over the frames, in microseconds: the Mac is
// shared, and a frame another process cut into would pull a mean up.
template <typename Get>
double median(const std::vector<Sample>& all, Get get) {
  if (all.empty()) return 0;
  std::vector<uint32_t> v;
  v.reserve(all.size());
  for (const Sample& s : all) v.push_back(get(s));
  std::nth_element(v.begin(), v.begin() + v.size() / 2, v.end());
  return v[v.size() / 2] / 10.0;
}

// The frame as a PPM, for BENCH_SHOTS: to see what a scene draws.
void shot(const render::Surface& s, const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) return;
  std::fprintf(f, "P6 %d %d 255\n", s.width, s.height);
  for (int i = 0; i < s.width * s.height; ++i) {
    const uint16_t p = s.pixels[i];
    const unsigned char rgb[3] = {uint8_t((p >> 11) << 3), uint8_t(((p >> 5) & 63) << 2), uint8_t((p & 31) << 3)};
    std::fwrite(rgb, 1, 3, f);
  }
  std::fclose(f);
}

// Each second's median draw, by the second.
std::vector<double> seconds(const std::vector<Sample>& all) {
  std::vector<double> out;
  for (size_t i = 0; i < all.size();) {
    std::vector<Sample> second;
    const uint32_t from = all[i].at / 1000;
    while (i < all.size() && all[i].at / 1000 == from) second.push_back(all[i++]);
    out.push_back(median(second, [](const Sample& s) { return s.draw; }));
  }
  return out;
}
// The slowest second, each second the quickest of the runs': what perf's
// fps_min reads on the board, with another process's bursts left out.
double slowest(const std::vector<std::vector<Sample>>& runs) {
  std::vector<double> least;
  for (const auto& run : runs) {
    const std::vector<double> each = seconds(run);
    if (least.empty()) least = each;
    for (size_t i = 0; i < std::min(least.size(), each.size()); ++i) least[i] = std::min(least[i], each[i]);
  }
  return least.empty() ? 0 : *std::max_element(least.begin(), least.end());
}

// The pixels a frame wrote, by the rows' spans the surface keeps.
uint32_t written(const render::Surface& s) {
  uint32_t n = 0;
  for (int y = 0; y < std::min(s.height, render::Surface::kTrackedRows); ++y)
    if (s.written[y].last) n += s.written[y].last - s.written[y].first;
  return n;
}

}  // namespace

int main(int argc, char** argv) {
  // gel_bench [SECONDS [FRAME_MS [SCENE...]]]: BENCH_RUNS runs of each (3),
  // the quickest run's medians kept; BENCH_FROM (ms) where measuring starts
  // (1000); BENCH_SECONDS=1 each second's too; BENCH_SHOTS=DIR a PPM every 5 s.
  const int seconds = argc > 1 ? std::atoi(argv[1]) : 30;
  const int frameMs = argc > 2 ? std::atoi(argv[2]) : 33;
  const int runs = std::getenv("BENCH_RUNS") ? std::max(1, std::atoi(std::getenv("BENCH_RUNS"))) : 3;
  std::vector<std::string> only(argv + std::min(argc, 3), argv + argc);
  render::profileClock = tenthsUs;
  std::printf(
      "%-10s %6s %7s %7s | %6s %6s %6s %6s %6s %6s %6s %6s %6s | %7s %7s   (median us a frame, Mac, one core)\n",
      "scene", "frames", "draw", "slowest", "engine", "body", "art", "layers", "props", "lane", "stream", "front",
      "hands", "written", "pushed");
  for (const Scene& scene : scenes()) {
    if (!only.empty() && std::find(only.begin(), only.end(), scene.name) == only.end()) continue;
    std::vector<Sample> best;
    std::vector<std::vector<Sample>> all;
    double bestDraw = 1e30;
    for (int run = 0; run < runs; ++run) {
      Quiet out;
      sim::Board board(out, /*frozenClock=*/true);
      // A dbg.* line is handled at once and ends the batch: the lines after
      // it wait for the next tick, which handles them after its frame.
      auto send = [&](const std::string& line) {
        const std::string l = line + "\n";
        board.hosted().usb(l.data(), l.size());
      };
      send(R"({"t":"dbg.reset"})");
      board.hosted().tick();
      std::vector<Sample> samples;
      uint32_t nextState = 0, nextRepeat = 0;
      int repeats = 0;
      for (uint32_t t = 0; t < uint32_t(seconds) * 1000; t += frameMs) {
        send(R"({"t":"dbg.clock","freeze":)" + std::to_string(t) + "}");
        if (t >= nextState) {
          send(scene.state);
          if (!t)
            for (const auto& line : scene.at) send(line);
          nextState += 2000;
        }
        if (!scene.repeat.empty() && t >= nextRepeat) {
          send(scene.repeat[repeats++ % scene.repeat.size()]);
          nextRepeat += 2000;
        }
        render::gel::profile = {};
        const uint32_t start = tenthsUs();
        const bool drew = board.hosted().tick();
        const uint32_t took = tenthsUs() - start;
        // The first second is the change into the scene, as perf leaves out;
        // BENCH_FROM leaves out more, to look at one part of a scene.
        static const uint32_t from = std::getenv("BENCH_FROM") ? uint32_t(std::atoi(std::getenv("BENCH_FROM"))) : 1000;
        if (t < from || !drew) continue;
        Sample s;
        s.at = t;
        s.draw = took;
        s.parts = render::gel::profile;
        if (auto* frames = board.hosted().device().frames()) {
          s.written = written(frames->front());
          s.pushed = uint32_t(frames->plan().pixels());
          const char* shots = std::getenv("BENCH_SHOTS");
          if (shots && !run && t % 5000 < uint32_t(frameMs))
            shot(frames->front(), std::string(shots) + "/" + scene.name + "-" + std::to_string(t / 1000) + ".ppm");
        }
        samples.push_back(s);
      }
      all.push_back(samples);
      const double draw = median(samples, [](const Sample& s) { return s.draw; });
      if (draw < bestDraw) bestDraw = draw, best = samples;
    }
    using P = const Sample&;
    std::printf("%-10s %6zu %7.1f %7.1f | %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f | %7.0f %7.0f\n",
                scene.name, best.size(), bestDraw, slowest(all), median(best, [](P s) { return s.parts.engine; }),
                median(best, [](P s) { return s.parts.body; }), median(best, [](P s) { return s.parts.art; }),
                median(best, [](P s) { return s.parts.layers; }), median(best, [](P s) { return s.parts.props; }),
                median(best, [](P s) { return s.parts.lane; }), median(best, [](P s) { return s.parts.stream; }),
                median(best, [](P s) { return s.parts.front; }), median(best, [](P s) { return s.parts.hands; }),
                median(best, [](P s) { return s.written * 10; }), median(best, [](P s) { return s.pushed * 10; }));
    // BENCH_SECONDS: each second's medians, to see what a slow one draws.
    if (std::getenv("BENCH_SECONDS"))
      for (size_t i = 0; i < best.size();) {
        std::vector<Sample> second;
        const uint32_t from = best[i].at / 1000;
        while (i < best.size() && best[i].at / 1000 == from) second.push_back(best[i++]);
        using P = const Sample&;
        std::printf("  %2us %7.1f | body %6.1f art %6.1f props %6.1f lane %6.1f hands %6.1f | written %6.0f\n",
                    unsigned(from), median(second, [](P s) { return s.draw; }),
                    median(second, [](P s) { return s.parts.body; }), median(second, [](P s) { return s.parts.art; }),
                    median(second, [](P s) { return s.parts.props; }), median(second, [](P s) { return s.parts.lane; }),
                    median(second, [](P s) { return s.parts.hands; }),
                    median(second, [](P s) { return s.written * 10; }));
      }
  }
  return 0;
}
