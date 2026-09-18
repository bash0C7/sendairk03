# 発表構成 (15 分)

タイトル: How to craft YOUR handmade PicoRuby Instrument
対象: Lチカのコードが読める人。音楽の知識は不要。

| 分 | 内容 | デモ / 見せるもの |
|---|---|---|
| 0–1 | 自己紹介、Lチカの次のキャズム、楽器という答え | ジョイフル明和 / RubyIlluminations の写真 |
| 1–4 | **1. マイコンとセンサーの選び方** | ATOM Matrix + Grove の配線 (docs/hardware.md)。I2C 4 本で済む話 |
| 4–8 | **2. 音程の作り方** | `PitchMapper#note_milli` のコード。距離 → MIDI note → Hz。continuous と snap の違いを鳴らして聞かせる |
| 8–11 | **3. 波としての出力** | ESP32 の PWM で鳴る音 (小) → Chrome の WebAudio で鳴る音 (3.5mm)。frame が画面に流れる |
| 11–13 | 演奏デモ | VJ 画面。ボタンで鳴らし、手で音程、傾きで音色。(余裕があれば BLE / iPhone) |
| 13–15 | この後すぐ作る方法 | repo の README、`rake esp32:run`、Pico 2 W でも同じ gem が動くこと |

スライドは web/ の `/slides/:n` (picoruby-markdown)。同じ SPA なので VJ 画面とワンキーで行き来する。
会場には 3.5mm ステレオミニジャックを依頼済み。
