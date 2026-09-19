# 配線 (発表 section 1「マイコンとセンサーの選び方」)

## 主役: M5 ATOM Matrix (ESP32-PICO-D4)

| 機能 | GPIO | 備考 |
|---|---|---|
| ボタン (gate) | 39 | 内蔵、`GPIO::IN \| GPIO::PULL_UP`。押下 = 0 |
| I2C SDA | 25 | 側面ヘッダー (内蔵 IMU と同じ I2C bus) |
| I2C SCL | 21 | 側面ヘッダー (内蔵 IMU と同じ I2C bus) |
| 内蔵 5x5 WS2812 | 27 | 使わない (16 連を外付けする) |
| WS2812 16 連 (外付け) | 32 | Grove ポート (G32)。`ksbmyk/picoruby-ws2812` (RMT)。5V / GND |
| PWM スピーカー | 33 | 副の音出し。圧電 or 小型スピーカー + 抵抗 |
| USB-UART console | — | 115200 baud。frame はここに流れる |

※ ピン割当は bench で確認する (Phase 1)

センサー (どちらも I2C、pure Ruby driver):

- **VL53L0X** ToF 距離 (0x29)。`bash0C7/picoruby-vl53l0x`。20〜1200mm、測定 ~25〜33ms
- **MPU6886** 6 軸 IMU (0x68)。`bash0C7/picoruby-mpu6886`。ATOM Matrix は内蔵

選定理由: 距離 = 手をかざす「音程」に直感的、傾き = 音色に直感的、ボタン = 発音の on/off。
すべて I2C で配線が 4 本 (VCC / GND / SDA / SCL) で済み、driver が pure Ruby なので firmware を変えずに差し替えられる。

## 副: Raspberry Pi Pico 2 W (rp2040 / RP2350)

BLE (cyw43) と PicoRuby VM (DRb / Task) の展示機。同じ gem と同じセンサー (I2C) を使う。
配線と焼き方は harness (`vendor/R2P2-dev-harness`) の `rake rp2040:*` に従う。

## ホスト

- Mac: Chrome (Web Serial / Web Bluetooth)。3.5mm はここから
- iPhone / Apple Watch: BLE central (CoreBluetooth)、AVAudioEngine
