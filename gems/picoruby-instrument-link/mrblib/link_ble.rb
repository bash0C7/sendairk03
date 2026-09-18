# ble://<name>   デバイス側の BLE::UART (Nordic UART Service) peripheral。picoruby-ble-uart が居る時だけ。
#
# BLE::UART#start はイベントループを所有するので、ここでは start を呼ばない。
# アプリ側で `link.uart.start { runner_tick }` のように回す (examples/rp2040/ble_instrument.rb)。
module Instrument
  module Link
    begin
      BLE::UART
      class BleUart < Base
        attr_reader :uart

        def initialize(host = "", params = {}, opts = {})
          super(host, params, opts)
          name = host.length == 0 ? "SendaiRK03" : host
          @uart = opts[:uart] || BLE::UART.new(role: :peripheral, name: name)
        end

        def write(data)
          @uart.write(data.to_s)
        end

        def read_nonblock(nbytes = 256)
          @uart.read_nonblock(nbytes)
        end

        def available
          @uart.available
        end

        def connected?
          @uart.connected?
        end
      end
      register "ble", BleUart
    rescue NameError
      # この build に BLE::UART は居ない
    end
  end
end
