# frame の出入り口を 1 つの interface にする。リンクを差し替えてもアプリを書き直さないための層。
#
#   link = Instrument::Link.open("console://")                      # ESP32 の USB-UART console (Kernel#puts)
#   link = Instrument::Link.open("uart://1?baud=921600&tx=32&rx=33") # UART.new(unit: "UART1", ...)
#   link = Instrument::Link.open("ble://SendaiRK03")                 # BLE::UART peripheral (rp2040)
#   link = Instrument::Link.open("webserial://?baud=115200")         # ブラウザ Web Serial
#   link = Instrument::Link.open("webble://SendaiRK03")              # ブラウザ Web Bluetooth (NUS)
#   link = Instrument::Link.open("serial:///dev/cu.usbserial-1?baud=115200")  # Mac の picoruby-serialport
#
#   link.write(str) / link.puts(str) / link.read_nonblock(n) / link.available / link.connected? / link.close
#
# 各 transport は下の class が build に居る時だけ定義される (link_*.rb を参照)。
module Instrument
  module Link
    class Error < StandardError; end

    SCHEMES = {}

    # "scheme://host?k=v&k2=v2" を { scheme:, host:, params: {} } に。URI gem は使わない (mruby/c に無い)。
    def self.parse(spec)
      raise Error, "link spec must be a String" unless spec.is_a?(String)
      sep = spec.index("://")
      raise Error, "link spec needs scheme://: #{spec}" unless sep
      scheme = spec[0, sep]
      rest = spec[(sep + 3)..-1] || ""
      q = rest.index("?")
      host = q ? rest[0, q] : rest
      query = q ? (rest[(q + 1)..-1] || "") : ""
      params = {}
      pairs = query.split("&")
      i = 0
      size = pairs.size
      while i < size
        pair = pairs[i]
        eq = pair.index("=")
        if eq
          params[pair[0, eq]] = pair[(eq + 1)..-1] || ""
        elsif pair.length > 0
          params[pair] = ""
        end
        i += 1
      end
      { scheme: scheme, host: host, params: params }
    end

    def self.register(scheme, klass)
      SCHEMES[scheme] = klass
    end

    def self.open(spec, **opts)
      parsed = parse(spec)
      klass = SCHEMES[parsed[:scheme]]
      raise Error, "no transport for #{parsed[:scheme]}:// in this build (have: #{SCHEMES.keys.sort.join(', ')})" unless klass
      klass.new(parsed[:host], parsed[:params], **opts)
    end

    # 全 transport の共通 interface。IO 風 (write / read_nonblock / available) にしておくと
    # Frame::Reader と DRb の transport がそのまま乗る。
    class Base
      def initialize(host = "", params = {}, **_opts)
        @host = host
        @params = params
      end

      def write(_data)
        raise Error, "#{self.class} does not implement write"
      end

      def puts(data)
        str = data.to_s
        write(str)
        write("\n") unless str.end_with?("\n")
        nil
      end

      def read_nonblock(_nbytes = 256)
        nil
      end

      def available
        0
      end

      def available?
        available > 0
      end

      def connected?
        true
      end

      def close
        nil
      end

      private

      def param_int(key, default)
        v = @params[key]
        v.nil? || v.length == 0 ? default : v.to_i
      end
    end

    # 標準出力に流す。ESP32 の USB-UART console はこれ (picoruby-ot の otmeiwa.rb と同じ経路)。
    # 受信側は無い (console は shell が握っている)。
    class Console < Base
      def write(data)
        str = data.to_s
        print str
        str.bytesize
      end
    end
    register "console", Console

    # メモリ上の擬似リンク。テストと、ブラウザ内でのループバックに使う。
    class Loopback < Base
      attr_reader :written

      def initialize(host = "", params = {}, **opts)
        super
        @written = []
        @rx = ""
      end

      def write(data)
        str = data.to_s
        @written << str
        str.bytesize
      end

      # 相手側から届いた振りをする
      def inject(data)
        @rx << data.to_s
        nil
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
    end
    register "loopback", Loopback
  end
end
