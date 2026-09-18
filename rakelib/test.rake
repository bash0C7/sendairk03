# harness の test.rake (test:host / test:examples) に足す分。
#   test:host_femto : ATOM Matrix は FemtoRuby (mruby/c) なので、HARNESS_GEMS を mruby/c の host VM でも回す
#   test:sources    : harness の test:examples は examples/ しか見ないので、web/ruby と server も compile に通す

def femto_host_test_config
  File.join(HARNESS_ROOT, "build_config", "host-test-femtoruby.rb")
end

def femto_vm_path
  File.join(PICORUBY_SRC, "build", "host", "bin", "femtoruby")
end

# picoruby (mruby) と femtoruby (mruby/c) の host build は同じ build/host を使う。
# CFLAGS の違いを mruby の build system は追わないので、必ず clean してから建てる。
def build_femto_host_vm
  env = { "PICORB_DEBUG" => "1", "MRUBY_CONFIG" => femto_host_test_config }
  vendor_rake(env, "clean")
  vendor_rake(env, "all")
end

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
    # femtoruby の残骸が build/host に残ると、次の test:host が SKIP_BUILD で古い VM を掴む。
    # KEEP_FEMTO_BUILD=1 の時だけ残す。
    if vendor_ready? && !ENV["KEEP_FEMTO_BUILD"] && !ENV["SKIP_BUILD"]
      vendor_rake({ "PICORB_DEBUG" => "1", "MRUBY_CONFIG" => femto_host_test_config }, "clean")
    end
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
end
