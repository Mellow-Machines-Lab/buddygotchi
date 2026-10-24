#include "board.h"

#include <cstdio>
#include <cstring>

namespace sim {

void Board::setCard(Card* card, bool out) {
  card_ = card;
  if (!out) hal_.insertCard(card);
}

void Board::input(const char* line) {
  int a = 0, b = 0, c = 0;
  if (std::sscanf(line, "touch %d %d", &a, &b) == 2) hal_.setTouch(true, a, b);
  else if (std::sscanf(line, "motion %d %d %d", &a, &b, &c) == 3) hal_.setMotion(a, b, c);
  else if (!std::strncmp(line, "release", 7)) hal_.setTouch(false);
  else if (std::sscanf(line, "boot %d", &a) == 1) hal_.setBoot(a != 0);
  else if (!std::strncmp(line, "card in", 7)) hal_.insertCard(card_);
  else if (!std::strncmp(line, "card out", 8)) hal_.ejectCard();
}

std::string Board::parts() const {
  char s[160];
  std::snprintf(s, sizeof(s), "{\"led\":%u,\"backlight\":%u,\"amp\":%s,\"card\":\"%s\"}", unsigned(hal_.led),
                unsigned(hal_.backlight), hal_.amp ? "true" : "false", hal_.card);
  return s;
}

}  // namespace sim
