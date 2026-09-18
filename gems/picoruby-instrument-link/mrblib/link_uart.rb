# uart://<unit>?baud=115200&tx=<pin>&rx=<pin>   (picoruby-uart が build に居る時だけ)
module Instrument
  module Link
    begin
      UART
      class Uart < Base
        def initialize(host = "", params = {}, **opts)
          super
          unit = host.length == 0 ? "UART1" : (host =~ /\A\d+\z/ ? "UART#{host}" : host)
          @uart = UART.new(
            unit: unit,
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
          @uart.read(nbytes)
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
