// The simulated board's sound: the same sound the boards' task runs
// (app/sound.h), with the chunks handed to whoever plays them. A thread
// paces them where there are threads (live.cpp); in the browser the audio
// asks for each (web.cpp).
#pragma once
#include <deque>
#include <mutex>

#include "app/sound.h"
#include "sim_hal.h"

namespace sim {

class ChunkSpeaker : public Speaker, protected app::Sound::Out {
 public:
  explicit ChunkSpeaker(SimHal& hal) : hal_(hal), sound_(*this) { sound_.ready(); }

  void say(const voice::Line& l) override { send({app::Sound::Kind::kSay, l, {}}); }
  void hush() override { send({app::Sound::Kind::kHush, {}, {}}); }
  void effect(const voice::Effect& e) override { send({app::Sound::Kind::kEffect, {}, e}); }
  void stopEffects() override { send({app::Sound::Kind::kStopEffects, {}, {}}); }
  app::AudioOut stats() override { return sound_.stats(); }

  // What the board's task does each time round: the lines and effects
  // waiting, then one chunk made and written (Out::write, the subclass's).
  void step() {
    for (;;) {
      app::Sound::Cmd c;
      {
        std::lock_guard<std::mutex> l(queueLock_);
        if (queue_.empty()) break;
        c = queue_.front();
        queue_.pop_front();
      }
      sound_.apply(c);
    }
    sound_.step();
  }

 protected:
  void amp(bool on) override { hal_.amp = on; }
  void lock() override { statsLock_.lock(); }
  void unlock() override { statsLock_.unlock(); }
  SimHal& hal_;

 private:
  // As deep as the board's queue; when it's full the newest wins.
  static constexpr size_t kQueue = 8;

  void send(const app::Sound::Cmd& c) {
    std::lock_guard<std::mutex> l(queueLock_);
    if (queue_.size() >= kQueue) queue_.pop_front();
    queue_.push_back(c);
  }

  app::Sound sound_;
  std::mutex queueLock_, statsLock_;
  std::deque<app::Sound::Cmd> queue_;
};

}  // namespace sim
