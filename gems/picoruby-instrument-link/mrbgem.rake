MRuby::Gem::Specification.new('picoruby-instrument-link') do |spec|
  spec.license = 'MIT'
  spec.author  = 'bash0C7'
  spec.summary = 'One interface for every transport of the instrument frames: console, UART, BLE UART, Web Serial, Web Bluetooth, serial port'

  # Pure Ruby. Each transport class is defined only when its underlying class exists in the build
  # (UART, BLE::UART, JS::WebSerial, JS::BLE::UART, SerialPort), so the same gem compiles everywhere.
  spec.require_name = 'instrument/link'
end
