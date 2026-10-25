// The MicroTech MTR024QV01A: its pin map, what's
// attached on this bench, and its panel settings. Only board/config.h
// includes this, for env cyd24.
#pragma once
#include <cstdint>

#include "render/canvas.h"

// Its env's name in firmware/platformio.ini, which hello's `board` says, so
// the Mac knows which firmware it takes.
constexpr const char* kBoardName = "cyd24";

namespace pins {
// Screen, ST7789 on SPI2 (HSPI).
constexpr int kLcdSclk = 14;
constexpr int kLcdMosi = 13;
constexpr int kLcdCs = 15;
constexpr int kLcdDc = 2;
constexpr int kBacklight = 21;  // high is on

// Touch, XPT2046, bit-banged on its own pins (cyd24/touch.cpp).
constexpr int kTouchSclk = 25;
constexpr int kTouchMosi = 32;
constexpr int kTouchMiso = 39;
constexpr int kTouchCs = 33;
constexpr int kTouchIrq = 36;  // low while pressed

// The microSD slot, on SPI3 (VSPI): the voice file (board/card.cpp).
constexpr int kCardSpiBus = 3;  // VSPI in Arduino's numbering
constexpr int kCardSclk = 18;
constexpr int kCardMiso = 19;
constexpr int kCardMosi = 23;
constexpr int kCardCs = 5;

// RGB LED, common anode: low is on.
constexpr int kLedRed = 22;
constexpr int kLedGreen = 16;
constexpr int kLedBlue = 17;

// Audio: DAC channel 2 into the amp; amp enable is active low.
constexpr int kDac = 26;
constexpr int kAmpEnable = 4;

// The main button. BOOT (IO0) on the v1 bench; an external button on IO35 later.
constexpr int kMainButton = 0;
}  // namespace pins

namespace board {

// Panel settings, confirmed on the real panel at bring-up.
constexpr uint32_t kSpiWriteHz = 80000000;  // over the ST7789's rating, clean on the bench board; 40 MHz is the step below
constexpr bool kInvert = true;
constexpr bool kBgr = false;

// The panel as it's built: 240×320, portrait. LovyanGFX needs these, not
// the canvas size.
constexpr int kPanelWidth = 240, kPanelHeight = 320;

// Which way up Boop is. LovyanGFX rotation, in quarter turns of the picture
// clockwise; the panel controller does the turning, so it costs no CPU.
// Boop sits sideways with USB-C on the LEFT, seen from the front, and the
// test pattern's USB-C bar and the webcam check assume it. Rotation 0 is
// portrait with USB-C at the bottom (confirmed at bring-up), so 3 should be
// that landscape; 1, half a turn from it, put USB-C on the right until
// 2026-09-29. If the board shows the pattern upside down (the UP arrow at
// the bottom, the bar away from the port), 3 was the wrong way round: change
// this to 1. The default touch map follows it, and a touch calibration saved
// for another rotation is ignored, so run `boopctl calibrate` again after
// changing it. Don't use 4–7: mirrored.
constexpr uint8_t kRotation = 3;

static_assert((kRotation & 1 ? kPanelHeight : kPanelWidth) == render::kWidth &&
                  (kRotation & 1 ? kPanelWidth : kPanelHeight) == render::kHeight,
              "kRotation must turn the panel to the canvas's shape");
// No native surface: the CYD pushes only the 8-bit canvas, so it builds
// only a face that draws it (the pixel face).
constexpr int kNativeWidth = 0, kNativeHeight = 0, kNativeCorner = 0;

}  // namespace board
