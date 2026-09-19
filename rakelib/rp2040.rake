# Pico 2 W は harness の rakelib/rp2040.rake をそのまま使う。tools/pico2w/*.rb と
# firmware-patches/*.patch を HARNESS_ROOT 直下に期待するので、揃っていない時は
# rp2040:check_inputs が (load 時ではなく実行時に) 落とす。
harness_rp2040 = File.join(HARNESS_DIR, "rakelib", "rp2040.rake")

if File.exist?(harness_rp2040)
  load harness_rp2040

  desc "Guard: tools/pico2w and firmware-patches/harness-*.patch must be synced from the harness"
  task "rp2040:check_inputs" do
    tools_ok   = File.directory?(File.join(HARNESS_ROOT, "tools", "pico2w"))
    patches_ok = Dir[File.join(HARNESS_ROOT, "firmware-patches", "harness-*.patch")].any?
    unless tools_ok && patches_ok
      raise "tools/pico2w or firmware-patches/harness-*.patch is missing. Run `bin/rake vendor:sync_tools`."
    end
  end

  %w[setup build stamp firmware flash upload run reboot verify].each do |name|
    task_name = "rp2040:#{name}"
    Rake::Task[task_name].enhance(["rp2040:check_inputs"]) if Rake::Task.task_defined?(task_name)
  end
else
  namespace :rp2040 do
    %w[setup build stamp firmware flash upload run reboot verify].each do |name|
      task name do
        raise "rp2040:#{name} is not available: run `bin/rake vendor:setup_all` first " \
              "(needs vendor/R2P2-dev-harness)."
      end
    end
  end
end
