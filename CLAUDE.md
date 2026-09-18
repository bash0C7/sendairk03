# sendairk03

Sendai RubyKaigi 03「How to craft YOUR handmade PicoRuby Instrument」の楽器・VJ・web スライド・
Mac ローカルサーバのアプリケーションと、独自 mrbgem を管理する repo。
設計と決定事項の single source of truth は [docs/spec.md](docs/spec.md)。
wire protocol は [docs/wire-protocol.md](docs/wire-protocol.md)。実測は [docs/latency.md](docs/latency.md)。

開発 harness (bash0C7/R2P2-dev-harness) と Apple 向け harness (bash0C7/R2P2-darwin) は vendor/ に clone して
そのまま使う。その規律と実機の罠は vendor 側の文書をそのまま参照する (複製しない)。
vendor が無い session では最初に `rake vendor:setup_all` を回す (import は無いまま静かに空になる)。

@vendor/R2P2-dev-harness/CLAUDE.md
@vendor/R2P2-darwin/CLAUDE.md

## vendor は生成物

- `vendor/{picoruby,R2P2-dev-harness,R2P2-ESP32,R2P2-darwin}` は commit しない・編集しない
- 変更経路は 3 つだけ: (a) `patches/` と `firmware-patches/` の patch (build 中だけ当てて戻す)
  (b) `build_config/` の overlay shim (`rake esp32:overlay` / harness の `vendor:overlay`)
  (c) `vendor/R2P2-darwin/rakelib/` へ生成する `.rake` (`rake darwin:sync`)
- 取り直しは `rake vendor:refresh_all`。picoruby の tree は 3 本ある (host/wasm 用、ESP32 の submodule、darwin の fork)。
  「常に最新」は host/wasm 用にだけ適用する。ESP32 は上流 submodule の pin、darwin は fork の `port-darwin`

## 完了の線引きは実機と実演

- `rake test` (host、両 VM) が green でも、ATOM Matrix で鳴るまで「動いた」と書かない
- ブラウザの挙動は Chrome で人が音を聞くまで green にしない
- 実機・実会場が無い session (CI、web session) では、その旨を 1 行報告して完了宣言を保留する
- 進捗報告は必ず tool の結果に紐づける。未検証は未検証と書く。失敗は出力付きでそのまま報告する

## 板の事実 (間違えやすい)

- **ATOM Matrix (ESP32-PICO-D4) は FemtoRuby (mruby/c)。** PicoRuby (mruby) VM は上流未確認 (Phase 0 の spike のみ)。
  → `Task` / `Task::Queue` / `IRQ.start` (ISR 直結の event bridge) / `picoruby-drb` は ATOM では使えない。
  gate は `IRQ.process` の polling か GPIO の read。DRb と Task を使う展示は Pico 2 W (rp2040) の仕事
- ESP32 はシリアルポートを開くとリセットされる (Web Serial の open でも)。ポートは glob でなく製品名から引く
- ESP32 の QEMU は ESP32-S3 のみ。ATOM (xtensa ESP32 classic) の代わりにはならない
- Web Serial / Web Bluetooth は Chrome 系のみ。`http://localhost` は secure context なので HTTPS は要らない
- `rake` の exe が PATH に無い環境では `bin/rake` (rubygems の rake を load する)。ruby の locale は `LC_ALL=C.UTF-8` (bin/rake が既定で設定) (日本語コメントを含む
  test file を picotest の runner が CRuby で先に load する)

## 音の経路を壊さない

- frame の仕様は docs/wire-protocol.md。`gems/picoruby-instrument-frame` の test と 1:1 で、片方だけ変えない
- 音程はデバイス側で決める (frame は gate / MIDI note x1000 / depth を運ぶ)。ホストは波を作るだけ
- ブラウザの Ruby→JS 呼び出しは frame あたり 1 回・スカラー 8 個まで。毎フレーム配列を渡さない
  (`JS::Bridge.to_js` は要素ごとに push する)
- WebAudio は `cancelAndHoldAtTime` + `setTargetAtTime`。`cancelScheduledValues` は portamento を壊す。
  glide の時定数は frame 周期 x 0.8
- gate off は必ず送る。teardown でも例外でも (`Instrument::Runner#silence` の責務)。stuck note を残さない

## gem の書き方

- `HARNESS_GEMS` (Rakefile) は host で compile できる pure Ruby の gem だけ。target 専用は `TARGET_ONLY_GEMS` で、
  build_config 側にだけ書く。間違えると `rake test:host` の host VM build ごと壊れる
- ATOM で動く gem は mruby/c の subset で書く: `defined?` / `Hash#fetch` / inline rescue / `proc` / `lambda` /
  `String#unpack` を使わない。Float に頼らず整数演算。library code は while ループ (vendor/picoruby/AGENTS.md)。
  `rake test:host_femto` が担保する
- picotest の fake は method の中で `Class.new` する。runner は test file を CRuby で先に load して class を数えるので、
  top level で VM 専用の定数に触ると NameError で落ちる
- `spec.require_name` を必ず書く (harness の `test.rake` が mrbgem.rake から読む)

## session の役割分担 (model routing)

| 役 | model | 仕事 |
|---|---|---|
| main | Fable | 何を実行するかの決定、report の吟味 (「成功」を鵜呑みにせず tool 結果と突合)、scope と plan、user との対話。長い log を自分で読まない |
| `spec-reader` | Opus | 長い仕様・上流 (picoruby / R2P2-*) のコード・設計判断の解釈。コードは書かない |
| `coder` | Sonnet | gems/ examples/ web/ server/ build_config/ rakelib/ を書く。同じ turn で picotest も書く。vendor/ は触らない |
| `log-reader` | Sonnet | build log / link error / serial log / git log の解釈。事実と推論を分けて報告 |
| `executor` | Haiku | 決定論的なコマンド実行。verbatim で渡し、raw output をそのまま返す。解釈・要約・修正をしない |

agent の定義は `.claude/agents/`。main の model は session 起動時に選ぶ (CLAUDE.md からは設定できない)。
