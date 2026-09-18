# 設計仕様 (single source of truth)

決定済みの事項だけを書く。未決は末尾に集める。実機の罠は vendor 側の文書
(`vendor/R2P2-dev-harness/docs/spec.md` §6、`vendor/R2P2-darwin/CLAUDE.md`) をそのまま参照する。

## 1. 何を作るのか

Sendai RubyKaigi 03 の 15 分発表「How to craft YOUR handmade PicoRuby Instrument」のための、

1. **楽器**: M5 ATOM Matrix (ESP32-PICO-D4、FemtoRuby) + VL53L0X ToF + MPU6886 IMU + ボタン gate + WS2812
2. **音の出口**: Mac の Chrome (picoruby-wasm + funicular、WebAudio、3.5mm) と iPhone / Apple Watch (AVAudioEngine)
3. **VJ**: three.js のビジュアライザーと web スライド (同じ SPA)
4. **配信**: PicoRuby で書いたローカル静的 web サーバー (Mac)
5. **無線と分散**: Pico 2 W (PicoRuby VM) の BLE NUS と、dRuby over BLE の制御チャネル実験

発表の 3 章にそのまま対応させる: (1) マイコンとセンサーの選び方 = `docs/hardware.md`、
(2) 音程の作り方 = `gems/picoruby-instrument` の `PitchMapper` (デバイス側で MIDI note を決める)、
(3) 波としての出力 = ESP32 の PWM (副) とホストの WebAudio / AVAudioEngine (主)。

## 2. 決定事項

| 項目 | 決定 | 根拠 |
|---|---|---|
| 主役 MCU | ATOM Matrix、**FemtoRuby (mruby/c)** | R2P2-ESP32 の Supported Devices で ATOM は mruby/c のみ確認済 |
| DRb / Task / ISR 直結 | **Pico 2 W** で展示 | picoruby-drb は mruby VM 限定。picoruby-ble の rp2040 port は上流にある |
| gate | ボタン (GPIO39) = 発音。`Instrument::Gate` (momentary / toggle / latch) | picoruby-ot の always-on drone の教訓 |
| 音程 | **デバイス側で決める**。frame は MIDI note x1000 を運ぶ | 発表 section 2 の主張。ホストは波を作るだけ |
| 音程の mode | continuous (portamento) と snap (音階吸着) を切替可能 | picoruby-ot で scale snap が未実装のまま event に臨んだ |
| 平滑化 | median (window 3) → EMA (alpha 50%) | 20mm 外れ値と追従の両立 |
| 通信 (本番) | UART (USB CDC) の ASCII frame v1、~40Hz | 人が読める = 画面に出せる。UART で余裕 |
| 通信 (無線) | BLE NUS の binary frame v2 (11B、1 notification) | 20B chunk に収める |
| DRb over BLE | 演奏経路には使わない。`instrument.scale = :minor_pentatonic` の**制御チャネル**として 1 回見せる | 1 RPC が 8 message 以上 = 100ms 超 |
| Mac の音 | Chrome の Web Serial → picoruby-wasm SPA → WebAudio 1 voice | 自前 Mac + Chrome。最短で音が出る |
| Mac の PicoRuby からの USB シリアル | `picoruby-serialport` (termios) を作る (Phase 2)。picoruby-uart の posix port は stub | 「全部 PicoRuby」のネタ兼 fallback |
| iPhone / Watch | BLE central (fork port-darwin の CoreBluetooth) → `picoruby-darwin-synth` (AVAudioSourceNode)。**Watch の発音は必須** | ユーザー決定。Watch 音声は前例が無いので Phase 4 冒頭で spike |
| LED | 外付け WS2812 16 連 (GPIO32)、`ksbmyk/picoruby-ws2812` | picoruby-ot と同配線 |
| vendor | 4 tree を `vendor/` に。編集は patch / overlay shim / 生成 rake のみ | harness の規律 |
| picoruby の pin | host/wasm = master 最新。ESP32 = 上流 submodule の pin。darwin = fork `port-darwin` | ESP32 の CMake は submodule の tree と結合 |
| compiler の pin | 当てない (`SUBMODULE_PINS = {}`)。rp2040 は `MRC_PRISM_ARENA_BLOCK=4096` を define | 同じ tree を wasm が使う |
| 完了の線引き | 実機で鳴る + Chrome で聞こえる。host の test は必要条件 | harness §5 と同じ |
| CI | host 層のみ (両 VM の picotest + compile)。ESP-IDF / Xcode / emscripten は載せない | 誰も直さない赤を作らない |

## 3. 置き場所

```
gems/picoruby-instrument-frame   wire protocol。pure Ruby、全 target
gems/picoruby-instrument         器: Runner / Gate / Smoother / PitchMapper / DepthMapper。pure Ruby、全 target
gems/picoruby-instrument-link    console / uart / ble / webserial / webble / serial の同型 interface
gems/picoruby-serialport         C (posix / darwin termios)。host と darwin のみ         (Phase 2)
gems/picoruby-drb-ble            DRb transport druby+ble://。rp2040 と wasm のみ           (Phase 3)
gems/picoruby-darwin-synth       iOS / watchOS 共用 AVAudioSourceNode synth               (Phase 4)
examples/esp32/                  ATOM Matrix。app.rb が起動時に走る
examples/rp2040/                 Pico 2 W: BLE peripheral と DRb server                    (Phase 3)
examples/darwin/{ios,watchos,macos}/                                                        (Phase 4)
web/                             funicular SPA: synth / VJ / slides                          (Phase 1-2)
server/                          PicoRuby の静的 HTTP server と serial→WebSocket relay       (Phase 2)
build_config/                    upstream の build_config を load して gem を足すだけ
rakelib/                         vendor / test / esp32 / rp2040 / darwin / wasm
patches/{esp32,picoruby-esp32}/  R2P2-ESP32 とその picoruby submodule に build 中だけ当てる patch
firmware-patches/                rp2040 用。harness の patch は `rake vendor:sync_tools` が harness-*.patch として複製 (gitignore)
tools/                           harness の tools/ の複製 (gitignore)
vendor/                          生成物。commit しない
```

`HARNESS_GEMS` (Rakefile) は host で compile できる gem だけ。target 専用は `TARGET_ONLY_GEMS` で build_config 側にだけ書く。

## 4. rake の共通インタフェース

| task | 意味 |
|---|---|
| `rake vendor:setup_all` / `vendor:refresh_all` | 4 tree の取得 / 更新。harness の `setup` / `refresh` を内包 |
| `rake test` | `test:host` (mruby) + `test:examples` + `test:sources` + `test:host_femto` (mruby/c)。board 無しはここまで |
| `rake esp32:setup` / `sync` / `build` / `flash` / `storage` / `monitor` / `run[secs]` / `stamp` / `qemu` | ATOM Matrix |
| `rake rp2040:*` | harness の rp2040.rake をそのまま (tools / patches の複製が揃っている時だけ load) |
| `rake darwin:setup` / `sync` / `run[task]` | R2P2-darwin へ委譲 |
| `rake wasm:build` / `dist` | picoruby-wasm を本 repo の gem 入りで build し web/public/vendor/ へ |

未実装の task は黙って通ったふりをせずに落とす (harness と同じ)。

## 5. テストの範囲

- **host 層** (`rake test`, CI): picotest。frame の往復、Reader の分割到着、Gate / Smoother / PitchMapper / DepthMapper の
  数値、Runner のライフサイクル (teardown・例外時の gate:0)。mruby と mruby/c の両方で回す
- **実機層**: `rake esp32:run` の monitor に frame が 30fps 以上で流れ、Chrome で「かざして押すと鳴り、離すと止まる」。
  Pico 2 W は harness の `rp2040:run`。iPhone / Watch は R2P2-darwin の `device:check` → `observe`
- **レイテンシー**: `docs/latency.md` に before / after の数字を残す。改善しない変更は revert する

## 6. フェーズ

| Phase | 内容 | green |
|---|---|---|
| 0 | 足場 (この commit)。Rakefile / rakelib / build_config / gem 3 本 / examples / docs / CI | `rake test` green、CI green |
| 0b | ATOM に `PICORB_VM=mruby` を 1 回 spike | boot する / しない (しなければ FemtoRuby 確定) |
| 1 | 最初の音: ATOM → UART → Chrome の synth。Web Serial のジェスチャ検証 | 実機で鳴る |
| 2 | VJ (three.js) / slides / PicoRuby 静的 server / `picoruby-serialport` | `/vj` 60fps、`curl localhost:8080/` |
| 3 | Pico 2 W: BLE NUS、binary frame、`picoruby-drb-ble`、`latency:*` | UART と BLE の p50/p95 表、DRb 往復時間 |
| 4 | iPhone / Watch (Watch 音声 spike を最初に) | 実機で音 |
| 5 | async_port (core1 sampling) / AOT。数字が改善しなければ revert | latency.md |

## 7. 未決

- ATOM Matrix で PicoRuby (mruby) VM が boot するか (0b)。boot すれば DRb を ATOM でも狙う
- `MRC_PRISM_ARENA_BLOCK` の override が vendor の mruby-compiler で効くか (効かなければ `PIN_COMPILER=1`)
- `JS::WebSerial.connect` が async listener からの transient activation を満たすか (Phase 1 最初の検証)
- Watch の AVAudioSourceNode 常時再生 (Phase 4 spike)
- ESP32 の BLE: 上流未 merge (picoruby#427 / R2P2-ESP32#135)。ATOM は FemtoRuby なので frame push のみ、Phase 3 の後の stretch
