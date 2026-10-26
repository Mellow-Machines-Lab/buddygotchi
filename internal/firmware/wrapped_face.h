// A face for the engine's tests: the build's own (render::makeFace), which
// it passes everything on to, and on top what a test needs that the pixel
// face hasn't: the context it was last synced to (FaceContext), and an
// agents' drawer as the gel's works, rows kRowH tall from canvas y kRowsTop
// down, pulled kTravel canvas px from shut to open. The
// gel's own drawer is tested with its pack.
#pragma once
#include <memory>

#include "render/face.h"

namespace testface {

struct WrappedFace : render::Face {
  static constexpr int kRowsTop = 40, kRowH = 30, kTravel = 160;
  std::unique_ptr<render::Face> f = render::makeFace();
  render::FaceContext context;  // the last sync's
  bool drawers = true;          // it has a drawer

  const char* name() const override { return f->name(); }
  bool drawsNative() const override { return f->drawsNative(); }
  const void* assets(size_t& bytes) const override { return f->assets(bytes); }
  void readAssetsFrom(const void* copy) override { f->readAssetsFrom(copy); }
  const voice::EffectClips& clips() const override { return f->clips(); }
  void reset(uint32_t t, linkkit::Rng& rng) override { f->reset(t, rng); }
  void seed(uint32_t s) override { f->seed(s); }
  void sync(const render::FaceSource& source, const render::FaceContext& c, uint32_t t) override {
    context = c;
    f->sync(source, c, t);
  }
  void rewind(uint32_t t, linkkit::Rng& rng) override { f->rewind(t, rng); }
  bool nextDue(uint32_t from, uint32_t to, uint32_t& at) override { return f->nextDue(from, to, at); }
  void step(uint32_t t, linkkit::Rng& rng) override { f->step(t, rng); }
  void alert(uint32_t t, bool replacing) override { f->alert(t, replacing); }
  uint8_t lookVariant() const override { return f->lookVariant(); }
  void newLook() override { f->newLook(); }
  void showLookVariant(uint8_t v) override { f->showLookVariant(v); }
  bool playPastime(const char* clip, uint32_t t) override { return f->playPastime(clip, t); }
  void watch(const render::Stream* stream) override { f->watch(stream); }
  void finger(bool down, int x, int y) override { f->finger(down, x, y); }
  void letGo(int vx, int vy) override { f->letGo(vx, vy); }
  bool playsSwipe() const override { return f->playsSwipe(); }

  bool hasDrawer() const override { return drawers; }
  int drawerTravel() const override { return kTravel; }
  int drawerRow(const render::Drawer& d, int x, int y) const override {
    (void)x;  // where its rows are open, however open it is: the device decides when they count
    if (y < kRowsTop) return -1;
    const int row = (y - kRowsTop) / kRowH;
    return row < d.total() ? row : -1;
  }
  void drawerShown(const render::Drawer& d, int& first, int& last) const override { first = 0, last = d.total() - 1; }

  uint8_t pick(render::SceneState anim, render::Mood mood, int wanted, render::Outcome outcome, render::StartCtx ctx,
               linkkit::Rng& rng, int loops, int turn) const override {
    return f->pick(anim, mood, wanted, outcome, ctx, rng, loops, turn);
  }
  void started(render::SceneState anim, render::Mood mood, uint8_t variant, render::Outcome outcome,
               render::StartCtx ctx) override {
    f->started(anim, mood, variant, outcome, ctx);
  }
  int plays(render::SceneState anim, uint8_t variant, int loops) const override {
    return f->plays(anim, variant, loops);
  }
  int variants(render::Mood mood, render::SceneState state) const override { return f->variants(mood, state); }
  uint32_t loopMs(render::Mood mood, render::SceneState state, int variant) const override {
    return f->loopMs(mood, state, variant);
  }
  render::Outcome outcome(render::Mood mood, render::SceneState state, int variant,
                          render::Outcome requested) const override {
    return f->outcome(mood, state, variant, requested);
  }
  uint32_t voiceMs(render::Mood mood, render::SceneState state, int variant) const override {
    return f->voiceMs(mood, state, variant);
  }
  uint32_t holdMs(render::Mood mood, int loops, uint32_t t) const override { return f->holdMs(mood, loops, t); }
  uint32_t designMs(uint32_t t) const override { return f->designMs(t); }
  bool blinking(uint32_t t) const override { return f->blinking(t); }
  render::SceneShow show(uint32_t t, bool mouthOpen, int dy) const override { return f->show(t, mouthOpen, dy); }
  bool draw(render::Canvas& canvas, render::Surface* native, const render::SceneShow& show, uint32_t t,
            const char* bubble, const render::SignShow& sign, const render::DoneShow& done, const render::Strip& strip,
            bool dirty) override {
    return f->draw(canvas, native, show, t, bubble, sign, done, strip, dirty);
  }
  int cues(uint32_t t, bool shown, voice::FxEvent* out, bool& changed) override {
    return f->cues(t, shown, out, changed);
  }
};

}  // namespace testface
