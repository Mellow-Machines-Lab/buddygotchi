// The Waveshare ESP32-S3-Touch-AMOLED-2.06: its pin map
// and how the canvas sits on its screen. Only board/config.h includes this,
// for env amoled206.
#pragma once
#include <cstdint>

#include "render/canvas.h"

namespace pins {
// Screen, CO5300 AMOLED on quad SPI (SPI2).
constexpr int kLcdSclk = 11;
constexpr int kLcdCs = 12;
constexpr int kLcdReset = 8;
constexpr int kLcdIo0 = 4, kLcdIo1 = 5, kLcdIo2 = 6, kLcdIo3 = 7;

// The shared I2C bus: touch (FT3168), the ES8311 codec, the AXP2101 and the rest.
constexpr int kI2cSda = 15;
constexpr int kI2cScl = 14;
constexpr int kTouchIrq = 38;   // low while there's a touch to report
constexpr int kTouchReset = 9;  // low is reset

// The microSD slot, on SPI3: the voice file (board/card.cpp).
constexpr int kCardSpiBus = 1;  // HSPI in Arduino's S3 numbering: SPI3, as SPI2 is the screen's
constexpr int kCardSclk = 2;
constexpr int kCardMiso = 3;
constexpr int kCardMosi = 1;
constexpr int kCardCs = 17;

// Audio: I2S into the ES8311, then the NS4150B amp; amp enable is active high.
constexpr int kI2sMclk = 16;
constexpr int kI2sBclk = 41;
constexpr int kI2sWs = 45;
constexpr int kI2sDout = 40;
constexpr int kAmpEnable = 46;

// The main button: BOOT (IO0).
constexpr int kMainButton = 0;
}  // namespace pins

namespace board {

// The CO5300 AMOLED: 410×502, portrait, its columns 22 in from the
// controller's first. The 320×240 canvas is drawn 1.5 times as large
// (480×360) and turned a quarter, so Boop fills the screen held sideways;
// amoled206/display.cpp does the scaling and turning as it pushes.
constexpr uint32_t kSpiWriteHz = 40000000;
constexpr int kPanelWidth = 410, kPanelHeight = 502, kPanelOffsetX = 22;
// Which way up: true puts the canvas's top on the panel's left edge, so
// held sideways the USB-C port is on the left, as on the CYD.
constexpr bool kTopOnPanelLeft = true;
// Only names the touch calibration's screen (app::SavedTouchCal).
constexpr uint8_t kRotation = 0;
// Where the turned picture sits on the panel, in panel pixels: 360 wide
// (the canvas's rows) by 480 tall (its columns), centred. The CO5300 takes
// windows only at even addresses with even sizes, so both are even.
constexpr int kPicW = render::kHeight * 3 / 2, kPicH = render::kWidth * 3 / 2;
constexpr int kPicX = (kPanelWidth - kPicW) / 2 & ~1, kPicY = (kPanelHeight - kPicH) / 2 & ~1;
// A face that draws natively (the gel) gets the whole panel, landscape:
// 502 × 410, turned a quarter as it's pushed.
constexpr int kNativeWidth = kPanelHeight, kNativeHeight = kPanelWidth;

}  // namespace board
