# serial://<path>?baud=115200   Mac / Linux の picoruby-serialport (termios)。Phase 2 で gem を作る。
module Instrument
  module Link
    begin
      SerialPort
      class Serial < Base
        attr_reader :port

        def initialize(host = "", params = {}, opts = {})
          super(host, params, opts)
          raise Error, "serial:// needs a device path" if host.length == 0
          path = host.start_with?("/") ? host : "/dev/#{host}"
          @port = opts[:port] || SerialPort.open(path, baudrate: param_int("baud", 115_200))
        end

        def write(data)
          @port.write(data.to_s)
        end

        def read_nonblock(nbytes = 256)
          @port.read_nonblock(nbytes)
        end

        def available
          @port.available
        end

        def connected?
          !@port.closed?
        end

        def close
          @port.close
        end
      end
      register "serial", Serial
    rescue NameError
      # この build に SerialPort は居ない
    end
  end
end
