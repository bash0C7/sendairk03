# ブラウザ側 (web/) が使う PicoRuby.wasm。本 repo の gem を含めた build が要るので CDN の npm は使わず、
# vendor/picoruby を build_config/wasm.rb (upstream の picoruby-wasm.rb + 自前 gem) で build して
# web/public/vendor/ に置く。brotli は build の最後にしか呼ばれないので、emcc と一緒に事前確認する。

WASM_DIST_DIR = File.join(HARNESS_ROOT, "web", "public", "vendor")

def wasm_build_config
  File.join(HARNESS_ROOT, "build_config", "wasm.rb")
end

def wasm_npm_dir
  File.join(PICORUBY_SRC, "mrbgems", "picoruby-wasm", "npm", "picoruby")
end

namespace :wasm do
  desc "Build PicoRuby.wasm with this repo's gems (env: PICORB_DEBUG=1 for the debug build)"
  task :build do
    require_vendor!
    %w[emcc brotli].each do |tool|
      raise "#{tool} is not on PATH (install Emscripten + brotli; source emsdk_env.sh)" unless system("which #{tool} >/dev/null 2>&1")
    end
    env = { "MRUBY_CONFIG" => wasm_build_config }
    env["PICORB_DEBUG"] = "1" if ENV["PICORB_DEBUG"]
    vendor_rake(env, "all")
  end

  desc "Copy the built picoruby.js / picoruby.wasm / init.iife.js into web/public/vendor/"
  task :dist do
    require_vendor!
    variant = ENV["PICORB_DEBUG"] ? "debug" : "dist"
    src_dir = File.join(wasm_npm_dir, variant)
    FileUtils.mkdir_p WASM_DIST_DIR
    %w[picoruby.js picoruby.wasm].each do |f|
      src = File.join(src_dir, f)
      raise "#{src} is not there. Run `rake wasm:build` first." unless File.exist?(src)
      FileUtils.cp src, WASM_DIST_DIR
    end
    init = [File.join(src_dir, "init.iife.js"), File.join(wasm_npm_dir, "init.iife.js")].find { |f| File.exist?(f) }
    raise "init.iife.js not found under #{wasm_npm_dir}" unless init
    FileUtils.cp init, WASM_DIST_DIR
    puts "wasm:dist -> #{WASM_DIST_DIR} (#{variant})"
  end
end
