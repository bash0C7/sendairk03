# Instrument::Runner のライフサイクル。link は fake、idle は待たない。
# fake は method の中で Class.new する (picotest の runner が CRuby で先に load するため)。
class InstrumentRunnerTest < Picotest::Test
  def fake_link
    Class.new do
      attr_reader :frames
      def initialize; @frames = []; end
      def write(s); @frames << s; s.bytesize; end
    end.new
  end

  def build(link: fake_link, **opts)
    klass = Class.new(Instrument::Runner) do
      attr_reader :idled
      def idle(ms); (@idled ||= []) << ms; end
    end
    klass.new(link: link, **opts)
  end

  def test_run_requires_a_tick_block
    assert_raise(Instrument::Runner::Error) { build.run }
  end

  def test_setup_tick_teardown_order_and_seq
    log = []
    r = build
    r.run do |inst|
      inst.setup    { log << :setup }
      inst.tick     { |i| log << :tick; i.emit(gate: 1, note_milli: 60_000, depth: 0); i.stop if i.ticks >= 2 }
      inst.teardown { log << :teardown }
    end
    assert_equal [:setup, :tick, :tick, :tick, :teardown], log
    # 3 tick emit + 最後の gate:0 = 4 frame、seq は 0,1,2,3
    assert_equal 4, r.link.frames.size
    assert_equal 3, Instrument::Frame.decode(r.link.frames[3])[:seq]
    assert_equal 0, Instrument::Frame.decode(r.link.frames[3])[:gate]
  end

  def test_gate_off_is_sent_even_when_tick_raises
    r = build
    raised = false
    begin
      r.run do |inst|
        inst.tick { |i| i.emit(gate: 1, note_milli: 1000, depth: 0); raise "sensor died" }
      end
    rescue RuntimeError
      raised = true
    end
    assert_equal true, raised
    assert_equal 2, r.link.frames.size
    assert_equal 0, Instrument::Frame.decode(r.link.frames[1])[:gate]
  end

  def test_no_extra_gate_off_when_already_silent
    r = build
    r.run do |inst|
      inst.tick { |i| i.emit(gate: 0, note_milli: 0, depth: 0); i.stop }
    end
    assert_equal 1, r.link.frames.size
  end

  def test_hooks_and_idle
    order = []
    r = build(idle_ms: 5)
    r.run do |inst|
      inst.before_tick { order << :before }
      inst.tick { |i| order << :tick; i.stop }
      inst.after_tick { order << :after }
    end
    assert_equal [:before, :tick, :after], order
    assert_equal [5], r.idled
  end

  def test_binary_runner_emits_binary_frames
    r = build(binary: true)
    r.run do |inst|
      inst.tick { |i| i.emit(gate: 1, note_milli: 60_000, depth: 100); i.stop }
    end
    assert_equal 11, r.link.frames[0].bytesize
    assert_equal 0xA5, r.link.frames[0].getbyte(0)
    assert_equal 0, Instrument::Frame.decode_binary(r.link.frames[1])[:gate]
  end
end
