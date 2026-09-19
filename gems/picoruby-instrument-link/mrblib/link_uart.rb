# uart://<unit>?baud=921600&tx=<pin>&rx=<pin>   (unit は port の完全名。picoruby-uart が build に居る時だけ)
# host は ESP32_UART1 / RP2040_UART1 のように port の受け付ける完全名をそのまま渡す (数字だけの短縮形は無い)。
module Instrument
  module Link
    begin
      UART
      class Uart < Base
        def initialize(host = "", params = {}, opts = {})
          super(host, params, opts)
          raise Error, "uart:// needs a unit name, e.g. uart://ESP32_UART1?..." if host.length == 0
          @uart = UART.new(
            unit: host,
            txd_pin: param_int("tx", -1),
            rxd_pin: param_int("rx", -1),
            baudrate: param_int("baud", 115_200)
          )
        end

        def write(data)
          str = data.to_s
          @uart.write(str)
          str.bytesize
        end

        def read_nonblock(nbytes = 256)
          @uart.readpartial(nbytes)
        end

        def available
          @uart.bytes_available
        end
      end
      register "uart", Uart
    rescue NameError
      # この build に UART は居ない (host / wasm / darwin)
    end
  end
end
