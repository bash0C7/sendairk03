# vendor/ の 4 tree (picoruby / R2P2-dev-harness / R2P2-ESP32 / R2P2-darwin) を取得・更新する。
# picoruby そのものは harness の `setup` / `refresh` (vendor/R2P2-dev-harness/rakelib/vendor.rake) が
# 取るので、ここでは harness を先に clone して、その task を呼ぶ。

def git_clone_shallow(repo, ref, dir)
  FileUtils.mkdir_p File.dirname(dir)
  sh "git clone --depth 1 --branch #{ref.shellescape} #{repo.shellescape} #{dir.shellescape}"
end

def git_refresh_shallow(dir, ref)
  FileUtils.cd(dir) do
    sh "git fetch --depth 1 origin #{ref.shellescape}"
    sh "git checkout --detach FETCH_HEAD"
  end
end

def esp32_ready?
  File.directory?(File.join(ESP32_DIR, ".git"))
end

def darwin_ready?
  File.directory?(File.join(DARWIN_DIR, ".git"))
end

# ESP32 の picoruby submodule は upstream の pin に従う。host build と同じ submodule だけ取る
# (pico-sdk は ESP32 に要らない)。ESP32_PICORUBY_REF を指定した時だけ pin から動かす
# (BLE の PR branch を当てるときに使う)。
def esp32_init_submodules
  FileUtils.cd(ESP32_DIR) do
    sh "git submodule update --init --depth 1 components/picoruby-esp32/picoruby"
  end
  if (ref = ENV["ESP32_PICORUBY_REF"])
    repo = ENV["ESP32_PICORUBY_REPO"] || "https://github.com/bash0C7/picoruby.git"
    FileUtils.cd(ESP32_PICORUBY) do
      sh "git fetch --depth 1 #{repo.shellescape} #{ref.shellescape}"
      sh "git checkout --detach FETCH_HEAD"
    end
  end
  FileUtils.cd(ESP32_PICORUBY) do
    sh "git submodule update --init --depth 1 #{HOST_SUBMODULES.map(&:shellescape).join(' ')}"
  end
end

namespace :vendor do
  desc "Clone R2P2-dev-harness into vendor/ (env: HARNESS_REPO / HARNESS_REF)"
  task :harness do
    if harness_ready?
      puts "vendor/R2P2-dev-harness is already there."
    else
      git_clone_shallow(HARNESS_REPO, HARNESS_REF, HARNESS_DIR)
    end
    load_harness_rakelib!
  end

  desc "Clone R2P2-ESP32 into vendor/ and init its picoruby submodule (env: ESP32_REPO / ESP32_REF / ESP32_PICORUBY_REF)"
  task :esp32 do
    if esp32_ready?
      puts "vendor/R2P2-ESP32 is already there."
    else
      git_clone_shallow(ESP32_REPO, ESP32_REF, ESP32_DIR)
    end
    esp32_init_submodules
    Rake::Task["esp32:overlay"].invoke
  end

  desc "Clone R2P2-darwin into vendor/ (its own vendor/picoruby is fetched by `rake darwin:setup`)"
  task :darwin do
    if darwin_ready?
      puts "vendor/R2P2-darwin is already there."
    else
      git_clone_shallow(DARWIN_REPO, DARWIN_REF, DARWIN_DIR)
    end
  end

  # harness の rp2040.rake は tools/pico2w/*.rb と firmware-patches/*.patch を HARNESS_ROOT 直下に
  # 期待する (rp2040.rake:84,109,135,197,211 / 224,289)。vendor 側にしか実体が無いので複製する。
  # patch は Dir[] が空だと黙って未適用になる (= Machine.usb_boot 無し firmware) ので、
  # 複製が無いときは rakelib/rp2040.rake が rp2040:* を load せずに落とす。
  desc "Copy the harness's tools/ and firmware-patches/*.patch into this repo (both gitignored)"
  task :sync_tools do
    require_harness!
    tools_src = File.join(HARNESS_DIR, "tools")
    tools_dst = File.join(HARNESS_ROOT, "tools")
    FileUtils.rm_rf tools_dst
    FileUtils.cp_r tools_src, tools_dst
    patches_dst = File.join(HARNESS_ROOT, "firmware-patches")
    FileUtils.mkdir_p patches_dst
    Dir[File.join(patches_dst, "harness-*.patch")].each { |f| FileUtils.rm_f f }
    Dir[File.join(HARNESS_DIR, "firmware-patches", "*.patch")].sort.each do |patch|
      FileUtils.cp patch, File.join(patches_dst, "harness-#{File.basename(patch)}")
    end
    puts "synced: #{tools_dst}, #{Dir[File.join(patches_dst, 'harness-*.patch')].size} harness patch(es)"
  end

  desc "Fetch every vendor tree: harness, picoruby (harness `setup`), R2P2-ESP32, R2P2-darwin, then sync tools"
  task setup_all: [:harness] do
    Rake::Task["setup"].invoke          # harness: vendor/picoruby + submodules + overlay shim
    Rake::Task["vendor:sync_tools"].invoke
    Rake::Task["vendor:esp32"].invoke unless ENV["SKIP_ESP32"]
    Rake::Task["vendor:darwin"].invoke unless ENV["SKIP_DARWIN"]
  end

  desc "Re-fetch every vendor tree at its ref and re-apply overlays"
  task :refresh_all do
    require_harness!
    git_refresh_shallow(HARNESS_DIR, HARNESS_REF)
    load_harness_rakelib!
    Rake::Task["refresh"].invoke        # harness: vendor/picoruby
    Rake::Task["vendor:sync_tools"].invoke
    if esp32_ready?
      ESP32_OVERLAYS.each_key do |rel|
        path = File.join(ESP32_DIR, rel)
        sh "git -C #{ESP32_DIR.shellescape} checkout -- #{rel.shellescape}" if File.exist?(path)
      end
      git_refresh_shallow(ESP32_DIR, ESP32_REF)
      esp32_init_submodules
      Rake::Task["esp32:overlay"].invoke
    end
    git_refresh_shallow(DARWIN_DIR, DARWIN_REF) if darwin_ready?
  end
end
