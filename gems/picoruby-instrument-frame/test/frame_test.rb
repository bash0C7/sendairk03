# Instrument::Frame の encode / decode。docs/wire-protocol.md の実行形。
# picotest の runner は test file をまず CRuby で load して class を数えるので、
# top level では gem の定数に触らない (method の中でだけ触る)。
class InstrumentFrameTest < Picotest::Test

  def test_ascii_round_trip
    str = Instrument::Frame.encode(gate: 1, note_milli: 60_500, depth: 312, dist: 250, tilt_x: -120, tilt_y: 45, seq: 1234)
    assert_equal "<V1,G:1,N:60500,D:312,M:250,X:-120,Y:45,S:1234>\n", str
    frame = Instrument::Frame.decode(str)
    assert_equal 1, frame[:gate]
    assert_equal 60_500, frame[:note_milli]
    assert_equal 312, frame[:depth]
    assert_equal 250, frame[:dist]
    assert_equal(-120, frame[:tilt_x])
    assert_equal 45, frame[:tilt_y]
    assert_equal 1234, frame[:seq]
  end

  def test_gate_accepts_booleans
    assert_equal "<V1,G:1,N:0,D:0,M:0,X:0,Y:0,S:0>\n", Instrument::Frame.encode(gate: true, note_milli: 0, depth: 0)
    assert_equal "<V1,G:0,N:0,D:0,M:0,X:0,Y:0,S:0>\n", Instrument::Frame.encode(gate: false, note_milli: 0, depth: 0)
  end

  def test_encode_clamps_and_wraps
    str = Instrument::Frame.encode(gate: 1, note_milli: 999_999, depth: -5, dist: 9000, tilt_x: -9999, tilt_y: 9999, seq: 10_001)
    assert_equal "<V1,G:1,N:127000,D:0,M:2000,X:-2000,Y:2000,S:1>\n", str
  end

  def test_decode_ignores_whitespace_and_unknown_keys
    frame = Instrument::Frame.decode("  <V1,G:0,N:48000,Q:7,S:9>\r\n")
    assert_equal 0, frame[:gate]
    assert_equal 48_000, frame[:note_milli]
    assert_equal 9, frame[:seq]
    assert_equal 0, frame[:depth]
  end

  def test_decode_rejects_garbage
    assert_nil Instrument::Frame.decode(nil)
    assert_nil Instrument::Frame.decode("")
    assert_nil Instrument::Frame.decode("<V2,G:1>")
    assert_nil Instrument::Frame.decode("<V1,G:x>")
    assert_nil Instrument::Frame.decode("<V1,G1>")
    assert_nil Instrument::Frame.decode("V1,G:1>")
    assert_nil Instrument::Frame.decode("<V1,N:-,S:1>")
  end

  def test_parse_int
    assert_equal 45, Instrument::Frame.parse_int("45")
    assert_equal(-120, Instrument::Frame.parse_int("-120"))
    assert_nil Instrument::Frame.parse_int("-")
    assert_nil Instrument::Frame.parse_int("1x")
    assert_nil Instrument::Frame.parse_int("")
  end

  def test_binary_round_trip
    bin = Instrument::Frame.encode_binary(gate: 1, note_milli: 60_500, depth: 1000, dist: 300, tilt_x: -1600, tilt_y: 800, seq: 300)
    assert_equal 11, bin.bytesize
    assert_equal 0xA5, bin.getbyte(0)
    frame = Instrument::Frame.decode_binary(bin)
    assert_equal 1, frame[:gate]
    assert_equal 60_500, frame[:note_milli]
    assert_equal 1000, frame[:depth]
    assert_equal 300, frame[:dist]
    assert_equal(-1600, frame[:tilt_x])
    assert_equal 800, frame[:tilt_y]
    assert_equal 44, frame[:seq] # 300 % 256
  end

  def test_binary_quantization_is_monotonic_and_bounded
    prev = -1
    d = 0
    while d <= 1000
      got = Instrument::Frame.decode_binary(Instrument::Frame.encode_binary(gate: 0, note_milli: 0, depth: d))[:depth]
      assert got >= prev
      assert got <= 1000
      prev = got
      d += 125
    end
  end

  def test_binary_rejects_bad_crc_and_magic
    bin = Instrument::Frame.encode_binary(gate: 1, note_milli: 1000, depth: 1)
    broken = bin.byteslice(0, 10) + ((bin.getbyte(10) ^ 0xFF).chr)
    assert_nil Instrument::Frame.decode_binary(broken)
    assert_nil Instrument::Frame.decode_binary("\x00" + bin.byteslice(1, 10))
    assert_nil Instrument::Frame.decode_binary(bin.byteslice(0, 5))
    assert_nil Instrument::Frame.decode_binary(nil)
  end

  def test_crc8_known_vector
    # CRC-8/SMBUS ("123456789") = 0xF4
    bytes = [49, 50, 51, 52, 53, 54, 55, 56, 57]
    assert_equal 0xF4, Instrument::Frame.crc8(bytes)
  end
end
