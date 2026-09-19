# ホスト (mruby VM = PicoRuby) でテストを回すための build_config。
#
#   MRUBY_CONFIG=<repo>/build_config/host-test.rb rake all   # vendor/picoruby の中で
#
# MRUBY_ROOT は vendor/picoruby の Rakefile がこの config を load する前に定義する。
# 別プロセスで load されるので Rakefile の HARNESS_GEMS は見えない。gem は literal で列挙する。

SENDAI_ROOT = File.expand_path("..", __dir__)

load "#{MRUBY_ROOT}/build_config/picoruby-test.rb"  # そのまま読み込み、本 repo の gem を gemdir: で足すだけ

MRuby.each_target do |conf|
  conf.gem core: "picoruby-median_filter"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-frame"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument"
  conf.gem gemdir: "#{SENDAI_ROOT}/gems/picoruby-instrument-link"
end
