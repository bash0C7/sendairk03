# sendairk03

Sendai RubyKaigi 03「How to craft YOUR handmade PicoRuby Instrument」のための repo。
PicoRuby で作る手づくり楽器 (M5 ATOM Matrix)、その音を鳴らす Mac / iPhone / Apple Watch 側、
three.js の VJ ビジュアライザーと web スライド、Mac ローカルの web サーバー、そして独自 mrbgem。

- 設計と決定事項: [docs/spec.md](docs/spec.md)
- 配線: [docs/hardware.md](docs/hardware.md)
- wire protocol: [docs/wire-protocol.md](docs/wire-protocol.md)
- レイテンシーの実測: [docs/latency.md](docs/latency.md)
- 発表の構成: [docs/talk-outline.md](docs/talk-outline.md)

## 使う

```sh
bin/rake vendor:setup_all   # vendor/ に harness / picoruby / R2P2-ESP32 / R2P2-darwin を取る
bin/rake test                                   # host の picotest (mruby と mruby/c) + example / web / server の compile
bin/rake -T                                       # 何ができるか
```

ATOM Matrix (ESP-IDF v5.5 と USB 接続):

```sh
bin/rake esp32:setup                            # 一度だけ
bin/rake esp32:run[30] APP=app                # sync → build → flash → 30 秒 monitor
```

## 中身

| 場所 | 何 |
|---|---|
| `gems/picoruby-instrument-frame` | wire protocol (ASCII v1 / binary v2) と streaming reader。pure Ruby |
| `gems/picoruby-instrument` | 楽器の器: gate / smoother / 距離→音程 / 傾き→depth / run loop。pure Ruby |
| `gems/picoruby-instrument-link` | console / UART / BLE / Web Serial / Web Bluetooth / serial port を同じ interface に |
| `examples/esp32/` | ATOM Matrix のアプリ (`app.rb` が起動時に走る) |
| `examples/rp2040/` | Pico 2 W: BLE と DRb の展示 (Phase 3) |
| `examples/darwin/` | iPhone / Apple Watch / macOS (Phase 4) |
| `web/` | picoruby-wasm + funicular の SPA: synth / VJ / slides (Phase 1-2) |
| `server/` | PicoRuby 製のローカル静的 web サーバー (Phase 2) |
| `build_config/` | upstream の build_config を load して gem を足すだけの config |
| `rakelib/` | vendor の取得、ESP32 / rp2040 / darwin / wasm の task |
| `vendor/` | 生成物。commit しない (`.gitignore`) |

完了の線引きは実機。`rake test` が green でも、ATOM Matrix で鳴って Chrome で聞こえるまで「動いた」とは書かない。

## License

MIT
