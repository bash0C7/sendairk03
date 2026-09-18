# 楽器の wire protocol。docs/wire-protocol.md が仕様、この file と test/ がその実行形。
#
#   v1 ASCII  : "<V1,G:1,N:60500,D:312,M:250,X:-120,Y:45,S:1234>\n"   UART / 人が読む
#   v2 binary : 11 bytes, 0xA5 先頭                                  BLE (1 notification = 20B に収める)
#
# 値はすべて Integer (mruby/c でも同じ結果になるように Float を使わない)。
#   gate       0 | 1            発音中か
#   note_milli 0..127000        MIDI note x1000 (音程はデバイス側で決める)
#   depth      0..1000          FM depth 等の 0.0..1.0 x1000
#   dist       0..2000          生の距離 mm (VJ / debug 用)
#   tilt_x/y   -2000..2000      加速度差 x1000
#   seq        0..9999 (巡回)   欠落検出とレイテンシー計測
#
# library code は AGENTS.md に倣い while ループで書く (block iterator は ireps を増やす)。
module Instrument
  module Frame
    VERSION = 1
    ASCII_HEAD = "<V1,"
    BINARY_MAGIC = 0xA5
    BINARY_VER = 2
    BINARY_SIZE = 11

    NOTE_MAX  = 127_000
    DEPTH_MAX = 1000
    DIST_MAX  = 2000
    TILT_MIN  = -2000
    TILT_MAX  = 2000
    SEQ_WRAP  = 10_000

    KEYS = [:gate, :note_milli, :depth, :dist, :tilt_x, :tilt_y, :seq]

    def self.clamp(v, lo, hi)
      return lo if v < lo
      return hi if v > hi
      v
    end

    def self.gate_bit(gate)
      (gate == true || gate == 1) ? 1 : 0
    end

    # ASCII v1 frame。改行付き。
    def self.encode(gate:, note_milli:, depth:, dist: 0, tilt_x: 0, tilt_y: 0, seq: 0)
      g = gate_bit(gate)
      n = clamp(note_milli.to_i, 0, NOTE_MAX)
      d = clamp(depth.to_i, 0, DEPTH_MAX)
      m = clamp(dist.to_i, 0, DIST_MAX)
      x = clamp(tilt_x.to_i, TILT_MIN, TILT_MAX)
      y = clamp(tilt_y.to_i, TILT_MIN, TILT_MAX)
      s = seq.to_i % SEQ_WRAP
      "<V1,G:#{g},N:#{n},D:#{d},M:#{m},X:#{x},Y:#{y},S:#{s}>\n"
    end

    # "<...>" (前後の空白・改行は許す) を Hash に。壊れていれば nil。
    def self.decode(str)
      return nil if str.nil?
      s = str.strip
      return nil if s.length < 6
      return nil unless s.getbyte(0) == 60 && s.getbyte(s.length - 1) == 62 # '<' '>'
      body = s[1, s.length - 2]
      return nil if body.nil?
      fields = body.split(",")
      return nil if fields[0] != "V1"
      result = { gate: 0, note_milli: 0, depth: 0, dist: 0, tilt_x: 0, tilt_y: 0, seq: 0 }
      i = 1
      size = fields.size
      while i < size
        field = fields[i]
        colon = field.index(":")
        return nil unless colon
        key = field[0, colon]
        value = parse_int(field[(colon + 1)..-1])
        return nil if value.nil?
        case key
        when "G" then result[:gate] = value == 0 ? 0 : 1
        when "N" then result[:note_milli] = clamp(value, 0, NOTE_MAX)
        when "D" then result[:depth] = clamp(value, 0, DEPTH_MAX)
        when "M" then result[:dist] = clamp(value, 0, DIST_MAX)
        when "X" then result[:tilt_x] = clamp(value, TILT_MIN, TILT_MAX)
        when "Y" then result[:tilt_y] = clamp(value, TILT_MIN, TILT_MAX)
        when "S" then result[:seq] = value % SEQ_WRAP
        else
          # 未知の key は無視する (将来の field を足しても古い reader が落ちないように)
        end
        i += 1
      end
      result
    end

    # "-123" / "45" だけを Integer にする。to_i はゴミを 0 にして黙るので使わない。
    def self.parse_int(s)
      return nil if s.nil? || s.length == 0
      i = 0
      neg = false
      if s.getbyte(0) == 45 # '-'
        neg = true
        i = 1
        return nil if s.length == 1
      end
      value = 0
      len = s.length
      while i < len
        b = s.getbyte(i)
        return nil if b.nil? || b < 48 || b > 57
        value = value * 10 + (b - 48)
        i += 1
      end
      neg ? -value : value
    end

    # binary v2: magic | ver<<4|gate | note_deci u16LE | depth u8 | tilt_x i8 | tilt_y i8 | dist u16LE | seq u8 | crc8
    def self.encode_binary(gate:, note_milli:, depth:, dist: 0, tilt_x: 0, tilt_y: 0, seq: 0)
      note_deci = clamp(note_milli.to_i, 0, NOTE_MAX) / 10
      depth_u8  = clamp(depth.to_i, 0, DEPTH_MAX) * 255 / DEPTH_MAX
      tx = clamp(tilt_x.to_i, TILT_MIN, TILT_MAX) / 16
      ty = clamp(tilt_y.to_i, TILT_MIN, TILT_MAX) / 16
      m  = clamp(dist.to_i, 0, DIST_MAX)
      bytes = [
        BINARY_MAGIC,
        (BINARY_VER << 4) | gate_bit(gate),
        note_deci & 0xFF, (note_deci >> 8) & 0xFF,
        depth_u8 & 0xFF,
        tx & 0xFF, ty & 0xFF,
        m & 0xFF, (m >> 8) & 0xFF,
        seq.to_i & 0xFF
      ]
      bytes << crc8(bytes)
      out = ""
      i = 0
      while i < BINARY_SIZE
        out << bytes[i].chr
        i += 1
      end
      out
    end

    # 11 byte の String を Hash に。magic / version / crc が合わなければ nil。
    def self.decode_binary(str)
      return nil if str.nil? || str.bytesize < BINARY_SIZE
      return nil unless str.getbyte(0) == BINARY_MAGIC
      vf = str.getbyte(1)
      return nil unless (vf >> 4) == BINARY_VER
      bytes = []
      i = 0
      while i < BINARY_SIZE - 1
        bytes << str.getbyte(i)
        i += 1
      end
      return nil unless crc8(bytes) == str.getbyte(BINARY_SIZE - 1)
      note_deci = bytes[2] | (bytes[3] << 8)
      {
        gate: vf & 1,
        note_milli: note_deci * 10,
        depth: bytes[4] * DEPTH_MAX / 255,
        dist: bytes[7] | (bytes[8] << 8),
        tilt_x: signed8(bytes[5]) * 16,
        tilt_y: signed8(bytes[6]) * 16,
        seq: bytes[9]
      }
    end

    def self.signed8(b)
      b > 127 ? b - 256 : b
    end

    # CRC-8 (poly 0x07, init 0)。整数演算だけ。
    def self.crc8(bytes)
      crc = 0
      i = 0
      size = bytes.size
      while i < size
        crc ^= bytes[i]
        bit = 0
        while bit < 8
          crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF
          bit += 1
        end
        i += 1
      end
      crc
    end
  end
end
