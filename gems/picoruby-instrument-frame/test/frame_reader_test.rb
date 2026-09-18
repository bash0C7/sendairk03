# Instrument::Frame::Reader: 分割到着、ゴミ混入、binary との混在、buffer cap。
class InstrumentFrameReaderTest < Picotest::Test

  def test_one_frame_in_one_chunk
    reader = Instrument::Frame::Reader.new
    frames = reader.feed("<V1,G:1,N:60000,D:1,M:0,X:0,Y:0,S:1>\n")
    assert_equal 1, frames.size
    assert_equal 60_000, frames[0][:note_milli]
    assert_equal 0, reader.buffered
  end

  def test_byte_by_byte_arrival
    reader = Instrument::Frame::Reader.new
    str = Instrument::Frame.encode(gate: 1, note_milli: 60_000, depth: 1, seq: 7)
    got = []
    i = 0
    while i < str.length
      got = got + reader.feed(str[i, 1])
      i += 1
    end
    assert_equal 1, got.size
    assert_equal 7, got[0][:seq]
  end

  def test_two_frames_and_a_partial
    reader = Instrument::Frame::Reader.new
    a = Instrument::Frame.encode(gate: 1, note_milli: 1, depth: 0, seq: 1)
    b = Instrument::Frame.encode(gate: 1, note_milli: 2, depth: 0, seq: 2)
    frames = reader.feed(a + b + "<V1,G:1")
    assert_equal 2, frames.size
    assert_equal [1, 2], [frames[0][:seq], frames[1][:seq]]
    frames = reader.feed(",N:3,D:0,M:0,X:0,Y:0,S:3>\n")
    assert_equal 1, frames.size
    assert_equal 3, frames[0][:seq]
  end

  def test_garbage_is_dropped_and_counted
    reader = Instrument::Frame::Reader.new
    frames = reader.feed("boot log\r\n" + Instrument::Frame.encode(gate: 0, note_milli: 0, depth: 0, seq: 5))
    assert_equal 1, frames.size
    assert_equal 10, reader.dropped
    assert_equal 0, reader.parse_errors
  end

  def test_malformed_frame_counts_as_parse_error
    reader = Instrument::Frame::Reader.new
    frames = reader.feed("<V9,G:1>\n" + Instrument::Frame.encode(gate: 0, note_milli: 0, depth: 0, seq: 6))
    assert_equal 1, frames.size
    assert_equal 6, frames[0][:seq]
    assert_equal 1, reader.parse_errors
  end

  def test_binary_and_ascii_mixed_in_auto_mode
    reader = Instrument::Frame::Reader.new
    bin = Instrument::Frame.encode_binary(gate: 1, note_milli: 50_000, depth: 500, seq: 9)
    asc = Instrument::Frame.encode(gate: 0, note_milli: 51_000, depth: 0, seq: 10)
    frames = reader.feed(bin + asc + bin.byteslice(0, 4))
    assert_equal 2, frames.size
    assert_equal 50_000, frames[0][:note_milli]
    assert_equal 51_000, frames[1][:note_milli]
    assert_equal 4, reader.buffered
    frames = reader.feed(bin.byteslice(4, 7))
    assert_equal 1, frames.size
    assert_equal 9, frames[0][:seq]
  end

  def test_binary_resyncs_after_a_corrupt_byte
    reader = Instrument::Frame::Reader.new(mode: :binary)
    bin = Instrument::Frame.encode_binary(gate: 1, note_milli: 50_000, depth: 500, seq: 9)
    corrupt = 0xA5.chr + "\x01\x02" + bin
    frames = reader.feed(corrupt)
    assert_equal 1, frames.size
    assert_equal 9, frames[0][:seq]
    assert reader.parse_errors >= 1
  end

  def test_ascii_mode_treats_binary_as_garbage
    reader = Instrument::Frame::Reader.new(mode: :ascii)
    bin = Instrument::Frame.encode_binary(gate: 1, note_milli: 50_000, depth: 500, seq: 9)
    frames = reader.feed(bin + Instrument::Frame.encode(gate: 0, note_milli: 0, depth: 0, seq: 1))
    assert_equal 1, frames.size
    assert_equal 1, frames[0][:seq]
    assert_equal 11, reader.dropped
  end

  def test_unclosed_frame_is_capped
    reader = Instrument::Frame::Reader.new(max_buffer: 32)
    frames = reader.feed("<V1," + ("x" * 60))
    assert_equal 0, frames.size
    assert_equal 32, reader.buffered
    assert_equal 32, reader.dropped
  end

  def test_rejects_unknown_mode
    assert_raise(ArgumentError) { Instrument::Frame::Reader.new(mode: :hex) }
  end
end
