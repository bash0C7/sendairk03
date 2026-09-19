# iPhone / Apple Watch / macOS は vendor/R2P2-darwin の rake に委譲する。example と build_config は
# 本 repo に置き、`rake darwin:sync` で vendor へコピーする (symlink は xcodegen の相対 path が壊れるので
# コピー)。example の登録は vendor/R2P2-darwin/rakelib/ に生成する .rake で行う。

def require_darwin!
  raise "vendor/R2P2-darwin is not there. Run `rake vendor:setup_all` first." unless darwin_ready?
end

# コピー先が vendor の tracked file と衝突すると (b) の overlay 規律を破るので、
# 書く/消す前に必ず git ls-files で確認する。generated 側は sendairk03- prefix で衝突を避ける。
def refuse_tracked!(dir, rel)
  tracked = system("git", "-C", dir, "ls-files", "--error-unmatch", "--", rel, out: File::NULL, err: File::NULL)
  raise "#{rel} is tracked in #{dir}; refusing to overwrite/remove a tracked file" if tracked
end

namespace :darwin do
  desc "Fetch R2P2-darwin's own vendor/picoruby (fork bash0C7/picoruby, branch port-darwin)"
  task :setup do
    require_darwin!
    # 親 repo の PICORUBY_REPO/PICORUBY_REF (1 本目の tree 用) を漏らさない。3 本目は常に fork/port-darwin。
    env = {}
    env["PICORUBY_REPO"] = ENV["DARWIN_PICORUBY_REPO"] || "https://github.com/bash0C7/picoruby.git"
    env["PICORUBY_REF"]  = ENV["DARWIN_PICORUBY_REF"]  || "port-darwin"
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
        rel = File.join("examples", platform, "sendairk03-#{File.basename(src)}")
        refuse_tracked!(DARWIN_DIR, rel)
        dst = File.join(DARWIN_DIR, rel)
        FileUtils.rm_rf dst
        FileUtils.cp_r src, dst
        copied += 1
        puts "synced example: #{rel}"
      end
    end
    Dir[File.join(HARNESS_ROOT, "build_config", "darwin-*.rb")].sort.each do |src|
      rel = File.join("build_config", File.basename(src).sub(/\Adarwin-/, "r2p2-picoruby-sendairk03-"))
      refuse_tracked!(DARWIN_DIR, rel)
      dst = File.join(DARWIN_DIR, rel)
      FileUtils.cp src, dst
      copied += 1
      puts "synced build_config: #{File.basename(dst)}"
    end
    generated = File.join(HARNESS_ROOT, "examples", "darwin", "sendairk03.rake")
    if File.exist?(generated)
      rel = File.join("rakelib", "sendairk03.rake")
      refuse_tracked!(DARWIN_DIR, rel)
      FileUtils.mkdir_p File.join(DARWIN_DIR, "rakelib")
      FileUtils.cp generated, File.join(DARWIN_DIR, rel)
      puts "synced rakelib: sendairk03.rake"
    end
    puts "darwin:sync: #{copied} item(s)" unless copied.zero?
    puts "darwin:sync: nothing to sync yet (no examples/darwin/* nor build_config/darwin-*.rb)" if copied.zero?
  end

  desc "Run a rake task inside vendor/R2P2-darwin, e.g. rake 'darwin:run[ios:instrument:device:check]'"
  task :run, [:task] do |_t, args|
    require_darwin!
    raise "usage: rake darwin:run[<task>]" unless args[:task]
    rake_in(DARWIN_DIR, {}, args[:task])
  end
end
