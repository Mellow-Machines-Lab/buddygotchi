#include "board.h"

#include <cstdio>
#include <cstring>

namespace sim {

void Board::setCard(Card* card, bool out) {
  card_ = card;
  if (!out) hal_.insertCard(card), board_.helloChanged();
}

void Board::input(const char* line) {
  int a = 0, b = 0, c = 0;
  if (std::sscanf(line, "touch %d %d", &a, &b) == 2) hal_.setTouch(true, a, b);
  else if (std::sscanf(line, "motion %d %d %d", &a, &b, &c) == 3) hal_.setMotion(a, b, c);
  else if (!std::strncmp(line, "release", 7)) hal_.setTouch(false);
  else if (std::sscanf(line, "boot %d", &a) == 1) hal_.setBoot(a != 0);
  // A card in or out is another voice, or none: the hello says so again.
  else if (!std::strncmp(line, "card in", 7)) hal_.insertCard(card_), board_.helloChanged();
  else if (!std::strncmp(line, "card out", 8)) hal_.ejectCard(), board_.helloChanged();
}

std::string Board::parts() const {
  char led[32] = "", s[160];
  if (hal_.hasLed) std::snprintf(led, sizeof(led), "\"led\":%u,", unsigned(hal_.led));
  std::snprintf(s, sizeof(s), "{%s\"backlight\":%u,\"amp\":%s,\"card\":\"%s\"}", led, unsigned(hal_.backlight),
                hal_.amp ? "true" : "false", hal_.card);
  return s;
}

}  // namespace sim
