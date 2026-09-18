# M5 ATOM Matrix (ESP32-PICO-D4, FemtoRuby) 向け。vendor/R2P2-ESP32 の rake / idf.py を包む。
#
#   rake vendor:setup_all        # 取得 (一度だけ)
#   rake esp32:setup             # ESP-IDF の set-target と host tool build (一度だけ)
#   rake esp32:run APP=app       # sync → build → flash → monitor (壁時計で切る)
#
# ESP-IDF v5.5 を ~/esp/esp-idf (または IDF_PATH) に入れておく。PORT= でシリアルを指定できる。
# ATOM Matrix は FemtoRuby (mruby/c) のみ上流で確認済み。PICORB_VM=mruby は spike 用。
require "open3"

ESP32_BUILD_DIR = File.join(BUILD_DIR, "esp32")
ESP32_INPUT_GLOBS = %w[mrbgem.rake mrblib/**/*.rb src/**/* ports/**/* include/**/*].freeze

def require_esp32!
  raise "vendor/R2P2-ESP32 is not there. Run `rake vendor:setup_all` first." unless esp32_ready?
  raise "#{ESP32_PICORUBY} has no .git. Run `rake vendor:esp32` first." unless File.exist?(File.join(ESP32_PICORUBY, ".git"))
end

def esp32_build_config
  File.join(HARNESS_ROOT, "build_config", ESP32_OVERLAYS.values.find { |v| v.include?(ESP32_VM == "mruby" ? "picoruby" : "femtoruby") })
end

# build の間だけ patch を当て、必ず戻す。harness の with_firmware_patches と同じ形。
def with_patches(dir, patches)
  applied = []
  FileUtils.cd(dir) do
    patches.sort.each do |patch|
      next if system("git apply --reverse --check #{patch.shellescape} 2>/dev/null")
      sh "git apply #{patch.shellescape}"
      applied << patch
    end
  end
  yield
ensure
  FileUtils.cd(dir) do
    applied.reverse_each { |patch| sh "git apply --reverse #{patch.shellescape}" }
  end
end

def esp32_patches
  Dir[File.join(HARNESS_ROOT, "patches", "esp32", "*.patch")]
end

def esp32_picoruby_patches
  Dir[File.join(HARNESS_ROOT, "patches", "picoruby-esp32", "*.patch")]
end

def esp32_stamp
  parts = []
  parts << `git -C #{ESP32_DIR.shellescape} rev-parse HEAD`.strip
  parts << `git -C #{ESP32_PICORUBY.shellescape} rev-parse HEAD`.strip
  parts << "vm=#{ESP32_VM} target=#{ESP32_TARGET}"
  parts << Digest::SHA256.file(esp32_build_config).hexdigest
  (esp32_patches + esp32_picoruby_patches).sort.each { |p| parts << "#{File.basename(p)}:#{Digest::SHA256.file(p).hexdigest}" }
  HARNESS_GEMS.each do |gem|
    ESP32_INPUT_GLOBS.flat_map { |g| Dir[File.join(HARNESS_ROOT, "gems", gem, g)] }.sort.each do |f|
      next unless File.file?(f)
      parts << "#{f.delete_prefix(HARNESS_ROOT)}:#{Digest::SHA256.file(f).hexdigest}"
    end
  end
  Digest::SHA256.hexdigest(parts.join("\n"))
end

def esp32_stamp_file
  File.join(ESP32_BUILD_DIR, ".stamp-#{ESP32_VM}-#{ESP32_TARGET}")
end

def esp32_monitor_env
  env = {}
  env["PORT"] = ENV["PORT"] if ENV["PORT"]
  env
end

namespace :esp32 do
  # CMake が build_config の path を決め打つ (components/picoruby-esp32/CMakeLists.txt) ので、
  # harness の vendor:overlay と同じく、その名前の file を「本 repo の build_config を load するだけ」の
  # shim に置き換える。毎回貼り直す (refresh で HEAD が動いた後に *.upstream.rb が古いままになるのを防ぐ)。
  desc "Point R2P2-ESP32's build_config at this repo's build_config (generated shims)"
  task :overlay do
    require_esp32!
    ESP32_OVERLAYS.each do |rel, ours|
      original  = File.join(ESP32_DIR, rel)
      preserved = original.sub(/\.rb\z/, ".upstream.rb")
      unless File.exist?(original) || File.exist?(preserved)
        puts "R2P2-ESP32 has no #{rel}. Skipping."
        next
      end
      sh "git -C #{ESP32_DIR.shellescape} checkout -- #{rel.shellescape}"
      FileUtils.cp original, preserved
      File.write(original, <<~SHIM)
        #{ESP32_OVERLAY_MARKER}. Do not edit; `rake esp32:overlay` rewrites it.
        # The real content lives in the project at build_config/#{ours}.
        # The upstream original for this commit was preserved next to this file as
        # #{File.basename(preserved)}.
        load "#{File.join(HARNESS_ROOT, 'build_config', ours)}"
      SHIM
      puts "overlay written: #{original}"
    end
  end

  desc "One-time ESP-IDF setup for the target (env: IDF_TARGET, SDKCONFIG_DEFAULTS)"
  task setup: [:overlay] do
    esp_sh("rake setup_#{ESP32_TARGET}")
  end

  # storage/ は littlefs image として焼かれ、storage/home/app.rb が起動時に自動実行される。
  # board への upload の口は R2P2-ESP32 に無いので、焼き直しが唯一の経路。
  desc "Copy examples/esp32/*.rb into R2P2-ESP32/storage/home (APP=<name> becomes app.rb)"
  task :sync do
    require_esp32!
    app = ENV["APP"] || "app"
    src_dir = File.join(HARNESS_ROOT, "examples", "esp32")
    dst_dir = File.join(ESP32_DIR, "storage", "home")
    FileUtils.mkdir_p dst_dir
    Dir[File.join(dst_dir, "*.{rb,mrb}")].each { |f| FileUtils.rm_f f }
    sources = Dir[File.join(src_dir, "*.rb")].sort
    raise "no examples under #{src_dir}" if sources.empty?
    sources.each { |f| FileUtils.cp f, dst_dir }
    app_src = File.join(src_dir, "#{app}.rb")
    raise "#{app_src} is not there (APP=#{app})" unless File.exist?(app_src)
    FileUtils.cp app_src, File.join(dst_dir, "app.rb")
    puts "synced #{sources.size} file(s); app.rb <- #{app}.rb"
  end

  desc "Build the firmware (env: PICORB_VM=mrubyc|mruby, IDF_TARGET). Patches are applied only during the build"
  task build: [:overlay, :sync] do
    FileUtils.mkdir_p ESP32_BUILD_DIR
    wanted = esp32_stamp
    have = File.exist?(esp32_stamp_file) ? File.read(esp32_stamp_file).strip : nil
    if have != wanted
      puts "esp32: inputs changed (or first build); dropping stale build dirs"
      FileUtils.rm_rf File.join(ESP32_DIR, "build")
      %w[esp32-femtoruby esp32-picoruby].each { |n| FileUtils.rm_rf File.join(ESP32_PICORUBY, "build", n) }
    end
    with_patches(ESP32_DIR, esp32_patches) do
      with_patches(ESP32_PICORUBY, esp32_picoruby_patches) do
        esp_sh("idf.py build -DPICORB_VM=#{ESP32_VM == 'mruby' ? 'mruby' : 'mrubyc'}")
      end
    end
    File.write(esp32_stamp_file, wanted)
    puts "esp32: built (stamp #{wanted[0, 12]})"
  end

  desc "Print whether the last build is still valid for the current inputs"
  task :stamp do
    require_esp32!
    wanted = esp32_stamp
    have = File.exist?(esp32_stamp_file) ? File.read(esp32_stamp_file).strip : "(none)"
    puts "wanted: #{wanted}"
    puts "have:   #{have}"
    puts(wanted == have ? "up to date" : "stale")
  end

  desc "Flash the built firmware (all partitions incl. storage) via esptool (env: PORT)"
  task :flash do
    require_esp32!
    esp_sh("rake flash", esp32_monitor_env)
  end

  desc "Flash only the storage partition (examples), a few seconds (env: PORT)"
  task :storage do
    require_esp32!
    esp_sh("rake flash_storage", esp32_monitor_env)
  end

  desc "Open the serial monitor (Ctrl-] to quit) (env: PORT)"
  task :monitor do
    require_esp32!
    esp_sh("rake monitor", esp32_monitor_env)
  end

  desc "sync → build → flash → monitor for N seconds, log under build/esp32/log/ (env: APP, PORT)"
  task :run, [:seconds] do |_t, args|
    seconds = (args[:seconds] || "30").to_i
    Rake::Task["esp32:build"].invoke
    Rake::Task["esp32:flash"].invoke
    log_dir = File.join(ESP32_BUILD_DIR, "log")
    FileUtils.mkdir_p log_dir
    log = File.join(log_dir, Time.now.strftime("%Y%m%d-%H%M%S.log"))
    puts "monitoring #{seconds}s -> #{log}"
    # esp-idf-monitor は対話型。timeout で process group ごと止めて、出力は tee で残す。
    port = ENV["PORT"] ? "PORT=#{ENV['PORT'].shellescape} " : ""
    esp_sh("timeout --foreground #{seconds} #{port}rake monitor 2>&1 | tee #{log.shellescape}; true")
    puts File.exist?(log) ? "log: #{log} (#{File.size(log)} bytes)" : "no log written"
  end

  # upstream の qemu.rake は ESP32-S3 固定。ATOM (xtensa ESP32 classic) の代わりにはならない。
  desc "Boot the firmware on QEMU (ESP32-S3 only; not a stand-in for ATOM Matrix)"
  task :qemu do
    require_esp32!
    unless ESP32_TARGET == "esp32s3"
      raise "esp32:qemu only works with IDF_TARGET=esp32s3 (R2P2-ESP32's qemu.rake hardcodes it). " \
            "It does not emulate the ATOM Matrix (xtensa ESP32); use it only as a boot smoke test."
    end
    esp_sh("rake setup_qemu") unless File.directory?(File.join(ESP32_DIR, "build-qemu"))
    esp_sh("rake #{ESP32_VM == 'mruby' ? 'picoruby' : 'femtoruby'}:qemu")
  end
end
