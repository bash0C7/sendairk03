# レイテンシー

目標: 手を動かしてから音が変わるまで、UART 経路で 40ms 以下、BLE 経路で 60ms 以下。
バジェットの最悪ケースは目標を超える。目標を守るのは ToF の timing budget を詰めた時だけ (改善順 ①)。
数字は実測したものだけ書く。改善しなかった変更は revert する。

## バジェット (設計時の見積もり、出典付き)

| hop | 時間 | 出典 |
|---|---|---|
| VL53L0X 測定 | 20–33ms | picoruby-ot 実測 (`2026-03-30-latency-tuning-design.md`) / driver の timing budget |
| MPU6886 / I2C 100kHz | <1ms | — |
| gate 検出 (GPIO read、main loop) | 0–2ms | app.rb は 1ms sleep のループでボタンを見る |
| Ruby loop 残り | <2ms | picoruby-ot 実測 |
| UART 115200 / 48B | 4.2ms | 計算 |
| (BLE NUS notify) | 7.5–30ms | 接続間隔依存 |
| ブラウザ受信 + parse | 0.7ms avg / 1.4ms p95 | picoruby-ot 実測 |
| WebAudio 反映 | 3–10ms | `latencyHint: 'interactive'` |
| 合計 UART / BLE | 28–54ms / 31–79ms | 行の単純和 (UART 行は例の 48B frame での値)。目標 (40 / 60ms) は最良ケースでしか満たさない |

## 測り方

- デバイス: frame の `S` (seq)。1 秒ごとに `<V1,T:uptime_us>` (Phase 3 で追加)
- ブラウザ: `on_receive` で `performance.now()`、`audioContext.currentTime + outputLatency`
- 物理 (真値): WS2812 を gate と同時に光らせ、マイクとカメラで同時録画 (240fps) して光と音の差を読む
- `rake 'latency:capture[30]'` → `build/latency/*.jsonl`、`rake latency:report` (Phase 3)

## 実測

(未計測。Phase 1 で UART 経路、Phase 3 で BLE 経路を埋める)

| 日付 | 経路 | 変更 | p50 | p95 | max | 備考 |
|---|---|---|---|---|---|---|
