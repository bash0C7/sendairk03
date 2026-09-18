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
  conf.gem github: "bash0C7/picoruby-mpu6886", branch: "main"
  conf.gem github: "bash0C7/picoruby-vl53l0x", branch: "main"
  conf.gem github: "ksbmyk/picoruby-ws2812", branch: "main"   # RMTDriver + WS2812 (要 picoruby-rmt: upstream config に入っている)

  # 上流の filter
  conf.gem core: "picoruby-median_filter"
  conf.gem core: "picoruby-iir_filter"

  # 本 repo の gem (Rakefile の HARNESS_GEMS と同じ並び。別プロセスなので literal で書く)
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
end
