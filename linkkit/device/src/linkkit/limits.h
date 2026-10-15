// The protocol's numbers (linkkit/SPEC.md §9), in one place: the kit's
// code and its tests use these names, and the Swift host library keeps
// the same values.
#pragma once
#include <cstddef>
#include <cstdint>

namespace linkkit {

constexpr int kVersion = 1;               // hello.kit (§6)
constexpr size_t kMaxLine = 512;          // a message, each way, without its newline (§2)
constexpr int kMaxDoes = 32;              // names in hello.does (§3)
constexpr int kMaxWaiting = 4;            // `do`s waiting in the queue (§4)
constexpr uint32_t kDefaultTtlMs = 5000;  // a `next` `do`'s wait, when it gives none (§3)
constexpr uint32_t kMaxTtlMs = 60000;     // the longest `ttl` (§3)
constexpr int32_t kMaxId = 2147483647;    // ids are 1..kMaxId (§3)
constexpr uint32_t kHostGoneMs = 30000;   // no message from the host this long: it's gone (§5)
constexpr uint32_t kHelloMs = 60000;      // hello again this often (§5)
constexpr uint32_t kThawMs = 60000;       // a tool's frozen clock runs again after this long with no dbg.* (§7)

}  // namespace linkkit
