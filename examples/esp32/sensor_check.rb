# 配線チェック用。センサーの生値を 1 行ずつ出すだけ。楽器のロジックは使わない。
#   bin/rake 'esp32:run[20]' APP=sensor_check
require "gpio"
require "i2c"
require "mpu6886"
require "vl53l0x"

button = GPIO.new(39, GPIO::IN | GPIO::PULL_UP)
i2c = I2C.new(unit: :ESP32_I2C0, frequency: 100_000, sda_pin: 25, scl_pin: 21)
sleep_ms 50
imu = MPU6886.new(i2c)
sleep_ms 50
tof = VL53L0X.new(i2c)
sleep_ms 50

puts "# sensor_check: button / ToF mm / accel milliG"
n = 0
while n < 400
  d = tof.read_distance
  a = imu.acceleration
  puts "btn=#{button.read} dist=#{d} ax=#{(a[:x] * 1000).to_i} ay=#{(a[:y] * 1000).to_i} az=#{(a[:z] * 1000).to_i}"
  n += 1
end
