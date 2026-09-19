# sendairk03

Sendai RubyKaigi 03「How to craft YOUR handmade PicoRuby Instrument」の楽器・VJ・web スライド・
Mac ローカルサーバのアプリケーションと、独自 mrbgem を管理する repo。
設計と決定事項の single source of truth は [docs/spec.md](docs/spec.md)。
wire protocol は [docs/wire-protocol.md](docs/wire-protocol.md)。実測は [docs/latency.md](docs/latency.md)。

開発 harness (bash0C7/R2P2-dev-harness) と Apple 向け harness (bash0C7/R2P2-darwin) は vendor/ に clone して
そのまま使う。その規律と実機の罠は vendor 側の文書をそのまま参照する (複製しない)。
vendor が無い session では最初に `rake vendor:setup_all` を回す (vendor が無いと下の @import は黙って空になり、harness の規律が読み込まれない)。

@vendor/R2P2-dev-harness/CLAUDE.md
@vendor/R2P2-darwin/CLAUDE.md

## vendor は生成物

- `vendor/{picoruby,R2P2-dev-harness,R2P2-ESP32,R2P2-darwin}` は commit しない・編集しない
- 変更経路は 3 つだけ: (a) `patches/` と `firmware-patches/` の patch (build 中だけ当てて戻す)
  (b) `build_config/` の overlay shim (`rake esp32:overlay` / harness の `vendor:overlay`)
  (c) `vendor/R2P2-darwin/rakelib/` へ生成する `.rake` (`rake darwin:sync`)
- 取り直しは `rake vendor:refresh_all`。picoruby の tree は 3 本ある (host/wasm 用、ESP32 の submodule、darwin の fork)。
  「常に最新」は host/wasm 用にだけ適用する。ESP32 は上流 submodule の pin、darwin は fork の `port-darwin` を使う。

## 完了の線引きは実機と実演

- `rake test` (host、両 VM) が green でも、ATOM Matrix で鳴るまで「動いた」と書かない
- ブラウザの挙動は Chrome で人が音を聞くまで green にしない

## session の作法

- 長時間かかる job (`esp32:build` / `wasm:build` / `vendor:setup_all`) は数分かかる。detach して回す
  (`nohup ... > <scratchpad>/<task>.log 2>&1 & disown`)。ログは log-reader に読ませる
- `rake esp32:monitor` を素で回さない (戻ってこない)。`bin/rake 'esp32:run[30]'` を使う。ログは
  `build/esp32/log/<日時>.log` に残るので、そのまま main context に貼らない
- ATOM のポートは glob でなく製品名で拾う (ESP32 は open でリセットされる。Pico を挿しているとポートの
  順序が変わる):
  `PORT=$(ioreg -w 0 -r -c IOUSBHostDevice -l | awk '/CP210|CH9102|USB Single Serial/,/IOCalloutDevice/' | sed -n 's/.*"IOCalloutDevice" = "\(.*\)"/\1/p' | head -1) bin/rake 'esp32:run[30]'`
  (要確認: ATOM の USB bridge の正確な製品名は bench で確認する)
- 生成物は commit しない: `vendor/` `build/` `tools/` `firmware-patches/harness-*.patch` `web/public/vendor/`
  `*.mrb` `*.log`
- serial log には Wi-Fi の PSK や token が混ざることがある。貼る前に該当行を取り除く。credential は repo に
  置かず env で渡す

## 板の事実 (間違えやすい)

- **ATOM Matrix (ESP32-PICO-D4) は FemtoRuby (mruby/c)。** PicoRuby (mruby) VM は上流未確認 (Phase 0 の spike のみ)。
  mruby/c にも `Task` (`Task.create` / `run` / `pass`) と `Task::Queue` はある。ATOM に無いのは `IRQ.start`
  (ISR 直結の dispatcher task。FemtoRuby では NotImplementedError) と `picoruby-drb`。gate は `IRQ.process` の polling か GPIO の read。
  DRb と `IRQ.start` を使う展示は Pico 2 W (rp2040) の仕事
- ESP32 はシリアルポートを開くとリセットされる (Web Serial の open でも)。ポートは glob でなく製品名から引く
- ESP32 の QEMU は ESP32-S3 のみ。ATOM (xtensa ESP32 classic) の代わりにはならない
- Web Serial / Web Bluetooth は Chrome 系のみ。`http://localhost` は secure context なので HTTPS は要らない
- `rake` の exe が PATH に無い環境 (rbenv shim 無しの CI、Claude Code の web session) では `bin/rake` を使う。本書と docs の `rake xxx` は全て `bin/rake xxx` と読み替えてよい
- `bin/rake` は `LC_ALL` が未設定のときだけ `C.UTF-8` を入れる。picotest の runner は日本語コメント入りの test file を CRuby で先に load するので、locale が C のままだと invalid byte sequence で落ちる

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
  `String#unpack` / `Class.new` / `Array#concat` / `**opts` (keyword splat と zsuper の組み合わせ) を使わない。
  gem 内の依存は明示的に `require` する (mruby/c は require されるまで他 gem の mrblib が見えない)。
  Float に頼らず整数演算。library code は while ループ (vendor/picoruby/AGENTS.md。test では検出できないので review で見る)。VM 側の subset 逸脱は `rake test:host_femto` が落とす
- **mruby/c の escaped closure**: 外側の block が返った後に呼ばれる内側の block が外側のローカル変数を掴んでいると
  VM が `mrbc_find_class_by_object: Invalid value type` で落ちる。callback の登録 (`runner.tick { }` /
  `button.irq { }`) は変数と同じスコープでフラットに書き、登録 block の中で別の callback を登録しない (`r.setup { |i| i.tick { ... } }` の形)。
  状態を渡すなら ivar か `capture:` 引数 (picoruby-irq の流儀)
- picotest の fake class は test file の **top level** で
  `begin; <gem の定数>; class Fake < …; rescue NameError; end` と書く。mruby/c に `Class.new` は無く、
  Ruby は method の中に class 定義を書けない。runner は test file を CRuby で先に load して class を数えるので、
  top level の定数参照は必ず `rescue NameError` で囲む (CRuby の下読みでは飛ばされ、target VM でだけ定義される)。
  gem の定数を継承しない plain な fake (例: `class InstrumentRunnerTestLink`) は rescue 不要。
  実例 gems/picoruby-instrument/test/runner_test.rb
- `spec.require_name` を必ず書く (harness の `test.rake` が mrbgem.rake から読む)

## session の役割分担 (model routing)

| 役 | model | 仕事 |
|---|---|---|
| main | (session 起動時に選ぶ) | 何を実行するかの決定、report の吟味 (「成功」を鵜呑みにせず tool 結果と突合)、scope と plan、user との対話。長い log を自分で読まない |
| `spec-reader` | Opus | 長い仕様・上流 (picoruby / R2P2-*) のコード・設計判断の解釈。コードは書かない |
| `coder` | Sonnet | gems/ examples/ web/ server/ build_config/ rakelib/ docs/ を書く。同じ turn で picotest も書く。vendor/ は触らない |
| `log-reader` | Sonnet | build log / link error / serial log / git log の解釈。事実と推論を分けて報告 |
| `executor` | Haiku | 決定論的なコマンド実行。verbatim で渡し、raw output をそのまま返す。解釈・要約・修正をしない |

agent の定義は `.claude/agents/`。main の model は session 起動時に選ぶ (CLAUDE.md からは設定できない)。
