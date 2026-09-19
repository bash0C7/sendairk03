# Pico 2 W の firmware 用 build_config。harness の vendor:overlay がこの名前を要求する
# (vendor/picoruby/build_config/r2p2-picoruby-pico2_w.rb の shim がここを load する)。
#
# upstream の r2p2-picoruby-pico2_w.rb を *.upstream.rb 経由で load し、gem を足すだけ。
# Pico 2 W は BLE (picoruby-ble / ble-uart の rp2040 port) と DRb (PicoRuby VM) の展示機。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/build_config/r2p2-picoruby-pico2_w.upstream.rb"

MRuby.each_target do |conf|
  next unless conf.name.start_with?("r2p2-picoruby-pico2_w")

  # Prism arena は upstream の config が MRC_PRISM_ARENA_BLOCK=2048 を define 済 (compiler の pin は不要)

  # picoruby-ble / ble-uart / drb は upstream の pico2_w config (networking gembox 含む) に既に入っている
  conf.gem core: "picoruby-median_filter"
  conf.gem core: "picoruby-iir_filter"
  # SHA で固定する (build 時に main を解決させない。更新は SHA を書き換える)
  conf.gem github: "bash0C7/picoruby-mpu6886", checksum_hash: "dd87ad2bb5a41c0f14cd2b69adb5b1ed26590e47"
  conf.gem github: "bash0C7/picoruby-vl53l0x", checksum_hash: "7eb786b02837e9548033348e02de57e92dc0fc86"

  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
  # picoruby-drb-ble は Phase 3 で足す (gems/picoruby-drb-ble)
end
