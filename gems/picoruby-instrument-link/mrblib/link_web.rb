# ブラウザ側 (picoruby-wasm)。
#   webserial://?baud=115200   JS::WebSerial      (Chrome の Web Serial。requestPort はユーザー操作から)
#   webble://<name>            JS::BLE::UART      (Chrome の Web Bluetooth、NUS)
# どちらも接続はユーザーのクリックから始める必要があるので、new では繋がず #connect を呼ぶ。
module Instrument
  module Link
    begin
      JS::BLE::UART
      class WebBle < Base
        attr_reader :uart

        def initialize(host = "", params = {}, **opts)
          super
          @name = host.length == 0 ? "SendaiRK03" : host
          @uart = opts[:uart]
        end

        # クリックハンドラの中から呼ぶ (transient activation)
        def connect
          @uart ||= JS::BLE::UART.new(name_prefix: @name)
          @uart
        end

        def write(data)
          raise Error, "not connected" unless @uart
          @uart.write(data.to_s)
        end

        def read_nonblock(nbytes = 256)
          @uart ? @uart.read_nonblock(nbytes) : nil
        end

        def available
          @uart ? @uart.available : 0
        end

        def connected?
          @uart ? @uart.connected? : false
        end

        def close
          @uart&.close
          @uart = nil
        end
      end
      register "webble", WebBle
    rescue NameError
    end

    begin
      JS::WebSerial
      class WebSerial < Base
        attr_reader :port

        def initialize(host = "", params = {}, **opts)
          super
          @baud = param_int("baud", 115_200)
          @port = opts[:port]
          @rx = ""
        end

        # クリックハンドラ (async listener) の中から呼ぶ。JS::WebSerial.connect は requestPort → open まで行い
        # port を返す。受信は on_receive のブロックに chunk (binary String) で届く。ブロックが無ければ
        # 内部 buffer に溜めて read_nonblock で取り出す。
        def connect(&on_receive)
          port = JS::WebSerial.connect(baud_rate: @baud)
          port.on_receive do |data|
            if on_receive
              on_receive.call(data)
            else
              @rx << data
            end
          end
          @port = port
          port
        end

        def write(data)
          raise Error, "not connected" unless @port
          str = data.to_s
          @port.write_bytes(str)
          str.bytesize
        end

        def read_nonblock(nbytes = 256)
          return nil if @rx.length == 0
          n = nbytes < @rx.bytesize ? nbytes : @rx.bytesize
          out = @rx.byteslice(0, n)
          @rx = @rx.byteslice(n, @rx.bytesize - n) || ""
          out
        end

        def available
          @rx.bytesize
        end

        def connected?
          !@port.nil?
        end

        def close
          @port&.close
          @port = nil
        end
      end
      register "webserial", WebSerial
    rescue NameError
    end
  end
end
