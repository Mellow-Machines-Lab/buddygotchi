// The ESP32-S3's other core as a drawing helper (render/helper.h): a task
// on core 0, above the frames' sender and below the voice and Bluetooth,
// that runs what the loop hands it while the loop, on core 1, draws the
// rest of the frame.
#include "render/helper.h"

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

namespace board {

namespace {
constexpr UBaseType_t kPriority = 2;  // the frames' sender is 1 (display.cpp)
constexpr uint32_t kStack = 4096;
TaskHandle_t task = nullptr;
SemaphoreHandle_t done = nullptr;
void (*job)(void*) = nullptr;
void* arg = nullptr;

void run(void*) {
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    job(arg);
    xSemaphoreGive(done);
  }
}
void start(void (*j)(void*), void* a) {
  job = j, arg = a;
  xTaskNotifyGive(task);
}
void join() { xSemaphoreTake(done, portMAX_DELAY); }
uint32_t now() { return micros(); }
}  // namespace

void startHelper() {
  done = xSemaphoreCreateBinary();
  if (done && xTaskCreatePinnedToCore(run, "draw", kStack, nullptr, kPriority, &task, 0) == pdPASS)
    render::helper = {start, join, now};
}

}  // namespace board
