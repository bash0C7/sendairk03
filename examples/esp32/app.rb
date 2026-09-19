# M5 ATOM Matrix の楽器本体 (FemtoRuby / mruby/c)。storage/home/app.rb として起動時に自動実行される。
# ボタン → gate、ToF → 音程、IMU → depth、WS2812 → 色、USB-UART → frame を ~40Hz。
# 配線は docs/hardware.md、frame は docs/wire-protocol.md。
# ToF の測定周期 (~25-33ms) がペースメーカー。
require "gpio"
require "i2c"
require "pwm"
require "mpu6886"
require "vl53l0x"
require "ws2812"
require "instrument"
require "instrument/link"

BUTTON_PIN = 39
I2C_SDA    = 25
I2C_SCL    = 21
LED_PIN    = 32
LED_COUNT  = 16
PWM_PIN    = 33
USE_PWM    = true

# :tick (cooperative, no Task) | :sampler (driver の Task; Phase 1 で実機確認)
TOF_MODE = :tick

DIST_MIN = 30      # mm
DIST_MAX = 570     # mm  (30..570 → 2 オクターブ、約 23mm / 半音)
NOTE_MIN = 48      # C3
NOTE_MAX = 72      # C5
FRAME_MS = 25      # 40Hz。ToF が ~33ms なら ToF の周期に律速される
TOF_INTERVAL_MS = 33

# ---- ハードウェア ----
button = GPIO.new(BUTTON_PIN, GPIO::IN | GPIO::PULL_UP)
i2c = I2C.new(unit: :ESP32_I2C0, frequency: 100_000, sda_pin: I2C_SDA, scl_pin: I2C_SCL)
sleep_ms 50
begin
  imu = MPU6886.new(i2c)
rescue StandardError => e
  puts "# IMU not ready: #{e.message}"
  imu = nil
end
sleep_ms 50
tof = VL53L0X.new(i2c)
sleep_ms 50
led = WS2812.new(pin: LED_PIN, num: LED_COUNT)
pwm = USE_PWM ? PWM.new(PWM_PIN, frequency: 440, duty: 0) : nil

# ---- 楽器のロジック (gems/picoruby-instrument) ----
gate     = Instrument::Gate.new(mode: :momentary)
smoother = Instrument::Smoother.new(window: 3, alpha: 50, min: DIST_MIN - 10, max: DIST_MAX + 10)
pitch    = Instrument::PitchMapper.new(dist_min: DIST_MIN, dist_max: DIST_MAX, note_min: NOTE_MIN, note_max: NOTE_MAX,
                                       mode: :continuous, scale: :major_pentatonic)
depth_of = Instrument::DepthMapper.new(scale: 500, curve: :linear)
link     = Instrument::Link.open("console://")

base_x = 0
base_y = 0
base_z = 0
dist = DIST_MIN
note = NOTE_MIN * 1000
depth = 0
tilt_x = 0
tilt_y = 0
last_emit_ms = 0
last_tof_value = nil

# ---- run loop (gems/picoruby-instrument の Runner) ----
# block はフラットに登録する (escaped closure: docs/spec.md §7)
runner = Instrument::Runner.new(link: link)

runner.setup do
  if tof.ready?
    if TOF_MODE == :sampler
      tof.start_sampling(interval_ms: TOF_INTERVAL_MS)
    else
      tof.configure_sampling(interval_ms: TOF_INTERVAL_MS)
    end
  else
    puts "# ToF not ready (check wiring)"
  end
  if imu
    if TOF_MODE == :sampler
      imu.start_sampling(interval_ms: 20)
    else
      imu.configure_sampling(interval_ms: 20)
    end
  end
  led.brightness = 40
  led.clear
  puts "# sendairk03 instrument ready (ToF #{TOF_INTERVAL_MS}ms, frame #{FRAME_MS}ms)"
end

runner.tick do |i|
  now = Machine.board_millis

  # gate: 押している間だけ。edge は即時に frame を送る (ToF の周期を待たない)
  gate.update(button.read == 0)
  if gate.edge == :rising && imu
    # 立ち上がった瞬間の姿勢を基準にする (演奏中の傾きだけを depth にする)
    acc = imu.latest_acceleration || imu.acceleration
    base_x = (acc[:x] * 1000).to_i
    base_y = (acc[:y] * 1000).to_i
    base_z = (acc[:z] * 1000).to_i
  end

  if tof.ready?
    if TOF_MODE == :tick
      fresh = tof.tick(now)
    else
      current = tof.latest_distance
      fresh = current != last_tof_value
      last_tof_value = current
    end
    dist = smoother.update(tof.latest_distance) || dist if fresh
  end
  imu.tick(now) if imu && TOF_MODE == :tick
  note = pitch.note_milli(dist)

  if gate.on? && imu
    acc = imu.latest_acceleration || imu.acceleration
    tilt_x = (acc[:x] * 1000).to_i - base_x
    tilt_y = (acc[:y] * 1000).to_i - base_y
    depth = depth_of.depth(tilt_x, tilt_y, (acc[:z] * 1000).to_i - base_z)
  end

  if gate.changed? || (now - last_emit_ms) >= FRAME_MS
    i.emit(gate: gate.on?, note_milli: note, depth: depth, dist: dist, tilt_x: tilt_x, tilt_y: tilt_y)
    last_emit_ms = now

    if pwm
      if gate.on?
        pwm.frequency(pitch.freq_milli(note) / 1000)
        pwm.duty(50)
      else
        pwm.duty(0)
      end
    end

    hue = (note - NOTE_MIN * 1000) * 300 / ((NOTE_MAX - NOTE_MIN) * 1000)   # 0..300 (赤→紫)
    bright = gate.on? ? 100 : 25
    k = 0
    while k < LED_COUNT
      led.set_hsb(k, hue, 90, bright)
      k += 1
    end
    led.show
  end

  sleep_ms 1 if TOF_MODE == :sampler   # 背景 Task (ToF / IMU sampler) に実行権を渡す
end

runner.teardown do
  pwm.duty(0) if pwm
  led.clear
  if TOF_MODE == :sampler
    tof.stop_sampling
    imu.stop_sampling if imu
  end
  puts "# instrument stopped"
end

runner.run
