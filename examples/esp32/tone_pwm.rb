# talk section 3「波としての出力」の最小形: 距離で PWM の周波数を変えるだけ (音程の計算も gem を使う)。
#   rake esp32:run[30] APP=tone_pwm
require "gpio"
require "i2c"
require "pwm"
require "vl53l0x"
require "instrument"

button = GPIO.new(39, GPIO::IN | GPIO::PULL_UP)
i2c = I2C.new(unit: :ESP32_I2C0, frequency: 100_000, sda_pin: 25, scl_pin: 21)
sleep_ms 50
tof = VL53L0X.new(i2c)
pwm = PWM.new(33, frequency: 440, duty: 0)
pitch = Instrument::PitchMapper.new(mode: :snap, scale: :major_pentatonic)
smoother = Instrument::Smoother.new(min: 20, max: 600)

while true
  dist = smoother.update(tof.read_distance)
  if button.read == 0 && dist
    hz = pitch.freq_milli(pitch.note_milli(dist)) / 1000
    pwm.frequency(hz)
    pwm.duty(50)
    puts "dist=#{dist} hz=#{hz}"
  else
    pwm.duty(0)
  end
end
