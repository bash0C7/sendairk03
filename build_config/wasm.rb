# ブラウザ側 (web/) の PicoRuby.wasm 用 build_config。
# upstream の build_config/picoruby-wasm.rb (funicular / drb / markdown 同梱) を load し、
# 本 repo の gem を足すだけ。build 名は upstream のまま (picoruby-wasm mrbgem が
# npm/picoruby/{dist,debug} へ成果物を置く条件になっている)。
#
#   MRUBY_CONFIG=<repo>/build_config/wasm.rb rake all   # vendor/picoruby の中で (要 emcc)

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/build_config/picoruby-wasm.rb"

MRuby.each_target do |conf|
  next unless conf.name.start_with?("picoruby-wasm")
  conf.gem core: "picoruby-median_filter"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
  # picoruby-drb-ble は Phase 3 で足す
end
