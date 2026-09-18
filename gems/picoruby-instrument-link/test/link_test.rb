# Instrument::Link: spec の parse と、host で動く transport (Loopback / Console)。
# UART / BLE / Web / Serial の class は host の build に居ないので、ここでは「無いなら open が落ちる」だけを見る。
# frame gem は link gem の optional な相手。mruby/c では require されるまで見えないので test 側で読む
# (CRuby の下読みでは見つからないので LoadError を無視する)
begin
  require "instrument/frame"
rescue LoadError
end

class InstrumentLinkTest < Picotest::Test
  def test_parse_scheme_host_and_params
    p = Instrument::Link.parse("uart://1?baud=921600&tx=32&rx=33")
    assert_equal "uart", p[:scheme]
    assert_equal "1", p[:host]
    assert_equal "921600", p[:params]["baud"]
    assert_equal "33", p[:params]["rx"]
  end

  def test_parse_without_query_or_host
    p = Instrument::Link.parse("console://")
    assert_equal "console", p[:scheme]
    assert_equal "", p[:host]
    assert_equal 0, p[:params].size
    p = Instrument::Link.parse("serial:///dev/cu.usbserial-1?baud=115200")
    assert_equal "/dev/cu.usbserial-1", p[:host]
  end

  def test_parse_rejects_bad_spec
    assert_raise(Instrument::Link::Error) { Instrument::Link.parse("no-scheme") }
    assert_raise(Instrument::Link::Error) { Instrument::Link.parse(nil) }
  end

  def test_open_unknown_scheme_names_the_available_ones
    raised = nil
    begin
      Instrument::Link.open("carrierpigeon://x")
    rescue Instrument::Link::Error => e
      raised = e
    end
    assert_not_nil raised
    assert raised.message.include?("loopback")
  end

  def test_loopback_round_trip
    link = Instrument::Link.open("loopback://")
    assert_equal 5, link.write("hello")
    link.puts("x")
    assert_equal ["hello", "x", "\n"], link.written
    assert_equal 0, link.available
    link.inject("<V1,G:1")
    link.inject(">\n")
    assert_equal true, link.available?
    assert_equal "<V1,", link.read_nonblock(4)
    assert_equal "G:1>\n", link.read_nonblock(100)
    assert_nil link.read_nonblock
    assert_equal true, link.connected?
  end

  def test_loopback_feeds_a_frame_reader
    link = Instrument::Link.open("loopback://")
    reader = Instrument::Frame::Reader.new
    link.inject(Instrument::Frame.encode(gate: 1, note_milli: 60_000, depth: 10, seq: 3))
    frames = reader.feed(link.read_nonblock(1024))
    assert_equal 1, frames.size
    assert_equal 3, frames[0][:seq]
  end

  def test_console_writes_to_stdout
    link = Instrument::Link.open("console://")
    assert_equal 0, link.write("")
    assert_equal 0, link.available
  end

  def test_base_write_is_abstract
    assert_raise(Instrument::Link::Error) { Instrument::Link::Base.new.write("x") }
  end
end
