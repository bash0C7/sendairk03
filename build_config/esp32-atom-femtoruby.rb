# M5 ATOM Matrix (ESP32-PICO-D4) / FemtoRuby (mruby/c) の firmware 用 build_config。
#
# R2P2-ESP32 の components/picoruby-esp32/build_config/xtensa-esp-femtoruby.rb を
# `rake esp32:overlay` が *.upstream.rb に退避し、その名前の file を「この file を load するだけ」の
# shim にする。upstream の内容は複製しない。build 名 ("esp32-femtoruby") は変えない
# (CMake が build/<name>/lib/libmruby.a を名前で探す)。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/../build_config/xtensa-esp-femtoruby.upstream.rb"

MRuby.each_target do |conf|
  next unless conf.name == "esp32-femtoruby"

  # センサーと LED (pure Ruby driver)
  # SHA で固定する (build 時に main を解決させない。更新は SHA を書き換える)
  conf.gem github: "bash0C7/picoruby-mpu6886", checksum_hash: "dd87ad2bb5a41c0f14cd2b69adb5b1ed26590e47"
  conf.gem github: "bash0C7/picoruby-vl53l0x", checksum_hash: "7eb786b02837e9548033348e02de57e92dc0fc86"
  conf.gem github: "ksbmyk/picoruby-ws2812", checksum_hash: "6f0b6d2a3b8f726472c5dedcc621eda04292460d"   # RMTDriver + WS2812 (要 picoruby-rmt: upstream config に入っている)

  # 上流の filter
  conf.gem core: "picoruby-median_filter"
  conf.gem core: "picoruby-iir_filter"

  # 本 repo の gem (別プロセスなので HARNESS_GEMS は見えない。literal で並べる)
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
end
