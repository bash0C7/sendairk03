# iPhone / Apple Watch / macOS は vendor/R2P2-darwin の rake に委譲する。
# example と build_config は本 repo の examples/darwin/ と build_config/darwin-*.rb に置き、
# `rake darwin:sync` で vendor へコピーする (symlink は xcodegen の相対 path が壊れるのでコピー)。
# vendor 側の tracked file は書き換えない。example の登録は vendor/R2P2-darwin/rakelib/ に
# 生成する .rake で行う (Phase 4 で example と一緒に足す)。

def require_darwin!
  raise "vendor/R2P2-darwin is not there. Run `rake vendor:setup_all` first." unless darwin_ready?
end

namespace :darwin do
  desc "Fetch R2P2-darwin's own vendor/picoruby (fork bash0C7/picoruby, branch port-darwin)"
  task :setup do
    require_darwin!
    env = {}
    env["PICORUBY_REPO"] = ENV["DARWIN_PICORUBY_REPO"] if ENV["DARWIN_PICORUBY_REPO"]
    env["PICORUBY_REF"]  = ENV["DARWIN_PICORUBY_REF"]  if ENV["DARWIN_PICORUBY_REF"]
    task_name = File.directory?(File.join(DARWIN_PICORUBY, ".git")) ? "refresh" : "setup"
    rake_in(DARWIN_DIR, env, task_name)
  end

  desc "Copy examples/darwin/** and build_config/darwin-*.rb into vendor/R2P2-darwin"
  task :sync do
    require_darwin!
    copied = 0
    %w[ios watchos macos].each do |platform|
      Dir[File.join(HARNESS_ROOT, "examples", "darwin", platform, "*")].sort.each do |src|
        next unless File.directory?(src)
        dst = File.join(DARWIN_DIR, "examples", platform, File.basename(src))
        FileUtils.rm_rf dst
        FileUtils.cp_r src, dst
        copied += 1
        puts "synced example: #{platform}/#{File.basename(src)}"
      end
    end
    Dir[File.join(HARNESS_ROOT, "build_config", "darwin-*.rb")].sort.each do |src|
      dst = File.join(DARWIN_DIR, "build_config", File.basename(src).sub(/\Adarwin-/, "r2p2-picoruby-"))
      FileUtils.cp src, dst
      copied += 1
      puts "synced build_config: #{File.basename(dst)}"
    end
    generated = File.join(HARNESS_ROOT, "examples", "darwin", "sendairk03.rake")
    if File.exist?(generated)
      FileUtils.mkdir_p File.join(DARWIN_DIR, "rakelib")
      FileUtils.cp generated, File.join(DARWIN_DIR, "rakelib", "sendairk03.rake")
      puts "synced rakelib: sendairk03.rake"
    end
    puts "darwin:sync: #{copied} item(s)" if copied.zero?
    puts "darwin:sync: nothing to sync yet (no examples/darwin/* nor build_config/darwin-*.rb)" if copied.zero?
  end

  desc "Run a rake task inside vendor/R2P2-darwin, e.g. rake darwin:run[ios:instrument:device:check]"
  task :run, [:task] do |_t, args|
    require_darwin!
    raise "usage: rake darwin:run[<task>]" unless args[:task]
    rake_in(DARWIN_DIR, {}, args[:task])
  end
end
