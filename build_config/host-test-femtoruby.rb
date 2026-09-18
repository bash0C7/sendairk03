# ホスト (mruby/c VM = FemtoRuby) でテストを回すための build_config。
# ATOM Matrix は FemtoRuby なので、gem が mruby/c の subset に収まっていることをここで担保する。
# upstream の build_config/femtoruby-test.rb をそのまま読み込み、本 repo の gem を足すだけ。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/build_config/femtoruby-test.rb"

MRuby.each_target do |conf|
  conf.gem core: "picoruby-median_filter"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
end
