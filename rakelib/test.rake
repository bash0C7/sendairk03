# harness の test.rake (test:host / test:examples) に足す分。
#   test:host_femto : ATOM Matrix は FemtoRuby (mruby/c) なので、HARNESS_GEMS を mruby/c の host VM でも回す
#   test:sources    : harness の test:examples は examples/ しか見ないので、web/ruby と server も compile に通す
#   test:gem_lists  : gems/* と Rakefile の HARNESS_GEMS / TARGET_ONLY_GEMS の対応を確かめる
require "pathname"

def femto_host_test_config
  File.join(HARNESS_ROOT, "build_config", "host-test-femtoruby.rb")
end

def femto_build_dir
  File.join(PICORUBY_SRC, "build-femto")
end

def femto_vm_path
  File.join(femto_build_dir, "host", "bin", "femtoruby")
end

# test:host と build/host を取り合わないよう MRUBY_BUILD_DIR で別 tree (build-femto) に建てる。
def build_femto_host_vm
  env = {
    "PICORB_DEBUG"    => "1",
    "MRUBY_CONFIG"    => femto_host_test_config,
    "MRUBY_BUILD_DIR" => femto_build_dir
  }
  vendor_rake(env, "all")
end

# MRUBY_BUILD_DIR で build 先を分けても、install (bin/mrbc) の宛先は MRUBY_ROOT/bin 固定
# (mruby/lib/mruby/build.rb の install_dir)。femto build の直後は bin/mrbc が femto 向けの mrbc に
# repoint されているので、test:host が壊れないよう host 向けに戻すか、無ければ消して再 build を促す。
def restore_host_mrbc!
  return unless vendor_ready?
  mrbc_link = File.join(PICORUBY_SRC, "bin", "mrbc")
  mrbc_host = File.join(PICORUBY_SRC, "build", "host", "bin", "mrbc")
  FileUtils.rm_f mrbc_link
  return unless File.exist?(mrbc_host)
  relative = Pathname.new(mrbc_host).relative_path_from(Pathname.new(File.dirname(mrbc_link)))
  File.symlink(relative.to_s, mrbc_link)
end

Rake::Task["clean"].enhance { FileUtils.rm_rf femto_build_dir if vendor_ready? } if Rake::Task.task_defined?("clean")

namespace :test do
  desc "Run the harness gems' picotest on the FemtoRuby (mruby/c) host VM (what ATOM Matrix runs)"
  task :host_femto do
    require_vendor!
    require_harness!
    FileUtils.mkdir_p File.join(BUILD_DIR, "test-femto")
    build_femto_host_vm unless ENV["SKIP_BUILD"]
    require picotest_path
    ENV["RUBY"] = femto_vm_path
    raise "#{femto_vm_path} is not there. Build failed?" unless File.executable?(femto_vm_path)

    failed = []
    HARNESS_GEMS.each do |name|
      gem_dir = File.join(HARNESS_ROOT, "gems", name)
      test_dir = File.join(gem_dir, "test")
      next unless File.directory?(test_dir)
      runner = Picotest::Runner.new(
        test_dir,
        tmpdir: File.join(BUILD_DIR, "test-femto"),
        require_name: require_name_of(name),
        load_path: gem_dir
      )
      failed << name unless runner.run == 0
    end
    raise "picotest (femtoruby) failed: #{failed.join(', ')}" unless failed.empty?
  ensure
    restore_host_mrbc!
  end

  desc "Compile web/ruby/**/*.rb and server/**/*.rb with the host mrbc (syntax check, no board)"
  task :sources do
    require_vendor!
    mrbc = File.join(PICORUBY_SRC, "build", "host", "bin", "mrbc")
    raise "#{mrbc} is not there. Run `rake test:host` first." unless File.executable?(mrbc)
    files = Dir[File.join(HARNESS_ROOT, "web", "ruby", "**", "*.rb")] +
            Dir[File.join(HARNESS_ROOT, "server", "**", "*.rb")]
    if files.empty?
      puts "test:sources: SKIP (no files under web/ruby or server yet)"
      next
    end
    out_dir = File.join(BUILD_DIR, "sources")
    FileUtils.mkdir_p out_dir
    files.sort.each do |path|
      rel = path.delete_prefix(HARNESS_ROOT + "/")
      out = File.join(out_dir, rel.tr("/", "__").sub(/\.rb\z/, ".mrb"))
      sh "#{mrbc.shellescape} -o #{out.shellescape} #{path.shellescape}"
    end
    puts "test:sources: #{files.size} file(s) compiled"
  end

  desc "Cross-check gems/* against Rakefile's HARNESS_GEMS / TARGET_ONLY_GEMS"
  task :gem_lists do
    known = HARNESS_GEMS + TARGET_ONLY_GEMS
    dirs = Dir[File.join(HARNESS_ROOT, "gems", "*")].select { |d| File.directory?(d) }.map { |d| File.basename(d) }
    unknown = dirs - known
    raise "gems/ has dir(s) not listed in HARNESS_GEMS or TARGET_ONLY_GEMS: #{unknown.join(', ')}" unless unknown.empty?
    missing = HARNESS_GEMS.reject { |name| File.directory?(File.join(HARNESS_ROOT, "gems", name)) }
    raise "HARNESS_GEMS lists gems/ that do not exist: #{missing.join(', ')}" unless missing.empty?
    puts "test:gem_lists: ok (#{dirs.size} dir(s) under gems/, #{known.size} listed)"
  end
end
