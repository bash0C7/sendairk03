# ESP32 / PicoRuby (mruby VM) の firmware 用 build_config。
# ATOM Matrix では上流未確認 (Phase 0 の spike 用)。ESP32-S3 系 (ATOMS3 Lite / CoreS3) ではこちらが使える。
# upstream の xtensa-esp-picoruby.rb を *.upstream.rb 経由で load し、gem を足すだけ。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/../build_config/xtensa-esp-picoruby.upstream.rb"

MRuby.each_target do |conf|
  next unless conf.name == "esp32-picoruby"

  conf.gem github: "bash0C7/picoruby-mpu6886", branch: "main"
  conf.gem github: "bash0C7/picoruby-vl53l0x", branch: "main"
  conf.gem github: "ksbmyk/picoruby-ws2812", branch: "main"

  conf.gem core: "picoruby-median_filter"
  conf.gem core: "picoruby-iir_filter"

  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
end
