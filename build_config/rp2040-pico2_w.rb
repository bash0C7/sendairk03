# Pico 2 W の firmware 用 build_config。harness の vendor:overlay がこの名前を要求する
# (vendor/picoruby/build_config/r2p2-picoruby-pico2_w.rb の shim がここを load する)。
#
# upstream の r2p2-picoruby-pico2_w.rb を *.upstream.rb 経由で load し、gem を足すだけ。
# Pico 2 W は BLE (picoruby-ble / ble-uart の rp2040 port) と DRb (PicoRuby VM) の展示機。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/build_config/r2p2-picoruby-pico2_w.upstream.rb"

MRuby.each_target do |conf|
  next unless conf.name.start_with?("r2p2-picoruby-pico2_w")

  # harness docs/spec.md §6: mruby-compiler の Prism arena (既定 64KB) が heap 396KB の Pico 2 W を
  # 起動時に止める。harness は compiler の submodule を旧 pin に固定して逃げているが、本 repo は
  # 同じ vendor/picoruby を wasm/host と共有するので pin を当てず、arena を小さくする。
  # (R2P2-ESP32 が同じ define を 2048 で使っている。効かない場合は PIN_COMPILER=1 で rake setup)
  conf.cc.defines << "MRC_PRISM_ARENA_BLOCK=4096"

  # picoruby-ble / ble-uart / drb は upstream の pico2_w config (networking gembox 含む) に既に入っている
  conf.gem core: "picoruby-median_filter"
  conf.gem core: "picoruby-iir_filter"
  conf.gem github: "bash0C7/picoruby-mpu6886", branch: "main"
  conf.gem github: "bash0C7/picoruby-vl53l0x", branch: "main"

  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
  # picoruby-drb-ble は Phase 3 で足す (gems/picoruby-drb-ble)
end
