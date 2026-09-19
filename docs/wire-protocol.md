# Wire protocol

デバイス (ATOM Matrix / Pico 2 W) からホスト (Chrome / iPhone / Watch / Mac) へ流れる frame。
実装と test は `gems/picoruby-instrument-frame`。この文書と test は 1:1 で、片方だけ変えない。

## 値 (全て Integer)

| field | 範囲 | 意味 |
|---|---|---|
| gate | 0 / 1 | 発音中か。ボタン |
| note_milli | 0..127000 | MIDI note x1000。**音程はデバイス側で決める** |
| depth | 0..1000 | 音色側のパラメータ (FM depth 等) x1000 |
| dist | 0..2000 | 生の距離 mm。VJ と debug 用 |
| tilt_x / tilt_y | -2000..2000 | gate 立ち上がり時を基準にした加速度差 x1000 |
| seq | 0..10239 巡回 | 欠落検出とレイテンシー計測 |

## v1 ASCII (UART / 人が読む / 発表で画面に出す)

```
<V1,G:1,N:60500,D:312,M:250,X:-120,Y:45,S:1234>\n
```

- `<` で始まり `>` で終わる。改行は任意。field は `KEY:INT` を `,` で区切る。先頭 field は version `V1`
- KEY: `G`=gate `N`=note_milli `D`=depth `M`=dist `X`/`Y`=tilt `S`=seq。未知の KEY は無視 (前方に field を足せる)
- 可変長: 例の frame で 47 byte (改行込み 48)、値が最大のとき 55 byte (改行込み 56)。40Hz で 1.3–2.2 kB/s。115200 baud (11.5 kB/s) で余裕、921600 なら送出 0.5ms
- version が違う frame は捨てる (`parse_errors` に数える)

## v2 binary (BLE NUS / 1 notification = 20B に収める) — 11 byte

```
0xA5 | (2<<4)|gate | note_deci u16LE | depth u8 | tilt_x i8 | tilt_y i8 | dist u16LE | seq u8 | crc8
```

- note_deci = note_milli / 10 (0..12700)、depth u8 = depth*255/1000、tilt i8 = round(tilt/16)、
  seq u8 = seq % 256 (SEQ_WRAP 10_240 は 256 の倍数なので折り返しで偽の gap が出ない)
- crc8 は CRC-8 (poly 0x07, init 0) で先頭 10 byte
- gate の edge は即時に 1 frame、pitch は次の connection interval に相乗り
- `decode_binary` は ASCII の `decode` と同じく note_milli / dist を範囲内に clamp する

## Reader

`Instrument::Frame::Reader.new(mode: :auto)` は先頭 byte で判別する (`<` = ASCII、`0xA5` = binary)。
1 byte ずつ届いても frame を切り出す。ゴミは次の先頭まで捨てて `dropped` に数える。閉じない frame は
`max_buffer` (既定 4096) を超えた分から捨てる。ASCII は開いたまま 64 byte を超えると先頭の `<` ごと
捨てる (`dropped` に数える) ので、迷子の `<` が reader を stall させない。`>` に続く CR/LF の連続
(ESP-IDF の stdout は CRLF で出す) はまとめて読み捨てる。

## 逆方向 (ホスト → デバイス)

v1 では使わない。Pico 2 W では DRb (`druby+ble://`) が制御チャネル (scale / mode / transpose の差し替え)。
