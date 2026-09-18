# byte stream から frame を切り出す streaming parser。UART / BLE / Web Serial のどれでも同じ。
#
#   reader = Instrument::Frame::Reader.new          # mode: :auto (先頭 byte で ASCII / binary を判別)
#   reader.feed(chunk)   # => [Hash, ...]  chunk は何 byte でもよい (1 byte ずつでも frame が出る)
#   reader.dropped       # 捨てた byte 数 (ゴミ / buffer 溢れ)
#   reader.parse_errors  # 形は合っていたが decode できなかった frame 数 (version 違い / crc)
module Instrument
  module Frame
    class Reader
      LT = 60      # '<'
      GT = 62      # '>'
      LF = 10      # "\n"

      attr_reader :dropped, :parse_errors, :mode

      def initialize(mode: :auto, max_buffer: 4096)
        unless mode == :auto || mode == :ascii || mode == :binary
          raise ArgumentError, "mode must be :auto, :ascii or :binary"
        end
        @mode = mode
        @max_buffer = max_buffer
        @buffer = ""
        @dropped = 0
        @parse_errors = 0
      end

      def buffered
        @buffer.bytesize
      end

      def reset
        @buffer = ""
        nil
      end

      def feed(chunk)
        frames = []
        return frames if chunk.nil? || chunk.length == 0
        @buffer << chunk
        while @buffer.bytesize > 0
          b0 = @buffer.getbyte(0)
          if b0 == LT && @mode != :binary
            break unless take_ascii(frames)
          elsif b0 == BINARY_MAGIC && @mode != :ascii
            break unless take_binary(frames)
          else
            skip_garbage
          end
        end
        if @buffer.bytesize > @max_buffer
          # 閉じない frame が溜まった。古いほうを捨てて先頭を同期し直す
          over = @buffer.bytesize - @max_buffer
          @buffer = @buffer.byteslice(over, @max_buffer) || ""
          @dropped += over
        end
        frames
      end

      private

      # '<' から '>' まで。'>' がまだ無ければ false (次の feed を待つ)。
      def take_ascii(frames)
        close = find_byte(GT)
        return false unless close
        frame = @buffer.byteslice(0, close + 1)
        rest = @buffer.byteslice(close + 1, @buffer.bytesize - close - 1) || ""
        rest = rest.byteslice(1, rest.bytesize - 1) || "" if rest.getbyte(0) == LF
        @buffer = rest
        decoded = Frame.decode(frame)
        if decoded
          frames << decoded
        else
          @parse_errors += 1
        end
        true
      end

      # 0xA5 から 11 byte。足りなければ false。crc が合わなければ 1 byte 捨てて同期し直す。
      def take_binary(frames)
        return false if @buffer.bytesize < BINARY_SIZE
        decoded = Frame.decode_binary(@buffer.byteslice(0, BINARY_SIZE))
        if decoded
          frames << decoded
          @buffer = @buffer.byteslice(BINARY_SIZE, @buffer.bytesize - BINARY_SIZE) || ""
        else
          @parse_errors += 1
          @buffer = @buffer.byteslice(1, @buffer.bytesize - 1) || ""
          @dropped += 1
        end
        true
      end

      # 先頭から byte を走査する (String#index は encoding によって char 単位になる)。
      def find_byte(target)
        i = 0
        size = @buffer.bytesize
        while i < size
          return i if @buffer.getbyte(i) == target
          i += 1
        end
        nil
      end

      # 次の frame 先頭 ('<' か 0xA5) まで捨てる。
      def skip_garbage
        i = 1
        size = @buffer.bytesize
        while i < size
          b = @buffer.getbyte(i)
          break if (b == LT && @mode != :binary) || (b == BINARY_MAGIC && @mode != :ascii)
          i += 1
        end
        @dropped += i
        @buffer = @buffer.byteslice(i, size - i) || ""
      end
    end
  end
end
