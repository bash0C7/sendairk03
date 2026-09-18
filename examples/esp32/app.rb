# M5 ATOM Matrix の楽器本体 (FemtoRuby / mruby/c)。起動時に /home/app.rb として自動実行される。
#
#   ボタン (GPIO39)         → gate   (押している間だけ鳴る。picoruby-ot の「鳴りっぱなし」を設計で解決)
#   VL53L0X ToF (I2C)       → 距離   → 音程 (Instrument::PitchMapper、デバイス側で MIDI note に変換)
#   MPU6886 IMU (I2C)       → 傾き   → depth (FM の深さなど音色側)
#   WS2812 16 連 (GPIO32)   → 音程 = 色相、gate = 明るさ
#   USB-UART console        → frame  <V1,G:1,N:60500,D:312,M:250,X:-120,Y:45,S:1234>  を ~40Hz で送る
#   PWM スピーカー (GPIO33)  → 副の音 (talk section 3「波としての出力」のデモ。USE_PWM=false で止める)
#
# 配線は docs/hardware.md、frame は docs/wire-protocol.md。
# ToF の測定周期 (~25-33ms) がペースメーカー。sleep で速度を落とさない (picoruby-ot の実測から)。
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
imu = MPU6886.new(i2c)
imu.accel_range = MPU6886::ACCEL_RANGE_2G
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

# gate が立ち上がった瞬間の姿勢を基準にする (演奏中の傾きだけを depth にする)
calibrate = nil
show_leds = nil

Instrument::Runner.new(link: link).run do |inst|
  inst.setup do
    tof.start_sampling(interval_ms: TOF_INTERVAL_MS)   # 背景 Task で測り続ける (mruby/c でも動く API)
    imu.start_sampling(interval_ms: 20)
    led.brightness = 40
    led.clear
    led.show
    puts "# sendairk03 instrument ready (ToF #{TOF_INTERVAL_MS}ms, frame #{FRAME_MS}ms)"
  end

  inst.tick do |i|
    now = Machine.board_millis

    # gate: 押している間だけ。edge は即時に frame を送る (ToF の周期を待たない)
    gate.update(button.read == 0)
    if gate.edge == :rising
      acc = imu.latest_acceleration || imu.acceleration
      base_x = (acc[:x] * 1000).to_i
      base_y = (acc[:y] * 1000).to_i
      base_z = (acc[:z] * 1000).to_i
    end

    if tof.fresh?
      dist = smoother.update(tof.latest_distance) || dist
    end
    note = pitch.note_milli(dist)

    if gate.on?
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

    sleep_ms 1   # 背景 Task (ToF / IMU sampler) に実行権を渡す
  end

  inst.teardown do
    pwm.duty(0) if pwm
    led.clear
    led.show
    tof.stop_sampling
    imu.stop_sampling
    puts "# instrument stopped"
  end
end
