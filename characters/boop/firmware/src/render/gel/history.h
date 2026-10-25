// The engine's bounded histories: the latest N records, the
// oldest dropped first, in a fixed table inside the engine, so remembering
// never touches the heap. An identity is kept as the 64-bit FNV-1a key of
// its string, since it's only ever compared: the board
// kept 64 of each as heap strings, about 25 KB of internal RAM once full.
#pragma once
#include <array>
#include <cstdint>
#include <string>
namespace render::gel {
// The key of `s`, continuing from `h` (so a key of a + b is identityKey(b, identityKey(a))).
inline uint64_t identityKey(const std::string& s, uint64_t h = 1469598103934665603ull) {
  for (unsigned char c : s) h = (h ^ c) * 1099511628211ull;
  return h;
}
template <class T, int N>
class History {
 public:
  int size() const { return count_; }
  // Adds one, dropping the oldest when it's full.
  void add(const T& item) {
    items_[(first_ + count_) % N] = item;
    if (count_ < N)
      ++count_;
    else
      first_ = (first_ + 1) % N;
  }
  // The oldest that matches, or null.
  template <class Match>
  T* find(Match match) {
    for (int i = 0; i < count_; ++i)
      if (T& item = items_[(first_ + i) % N]; match(item)) return &item;
    return nullptr;
  }

 private:
  std::array<T, N> items_{};
  int first_ = 0, count_ = 0;
};
}  // namespace render::gel
