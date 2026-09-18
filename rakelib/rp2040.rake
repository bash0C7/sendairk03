# Pico 2 W は harness の rakelib/rp2040.rake をそのまま使う。
# その file は tools/pico2w/*.rb と firmware-patches/*.patch を HARNESS_ROOT 直下に期待するので、
# `rake vendor:sync_tools` の複製が揃っている時だけ load する。揃っていない時に load すると
# patch が黙って未適用になる (Machine.usb_boot 無し firmware = 無人 flash 不能) ので、落とす。
harness_rp2040 = File.join(HARNESS_DIR, "rakelib", "rp2040.rake")
tools_ok   = File.directory?(File.join(HARNESS_ROOT, "tools", "pico2w"))
patches_ok = Dir[File.join(HARNESS_ROOT, "firmware-patches", "harness-*.patch")].any?

if File.exist?(harness_rp2040) && tools_ok && patches_ok
  load harness_rp2040
else
  namespace :rp2040 do
    %w[setup build stamp firmware flash upload run reboot verify].each do |name|
      task name do
        raise "rp2040:#{name} is not available: run `rake vendor:setup_all` " \
              "(needs vendor/R2P2-dev-harness, tools/pico2w/ and firmware-patches/harness-*.patch)"
      end
    end
  end
end
