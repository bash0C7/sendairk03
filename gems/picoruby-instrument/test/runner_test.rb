# Instrument::Runner のライフサイクル。idle は待たない subclass で差し替える。
#
# fake の作り方: gem の定数 (Instrument::Runner) は CRuby の下読みでは無いので
# begin/rescue NameError で囲む。plain な fake (InstrumentRunnerTestLink) はそのままで良い。

begin
  Instrument::Runner
  class InstrumentRunnerTestFake < Instrument::Runner
    attr_reader :idled
    def idle(ms)
      @idled ||= []
      @idled << ms
    end
  end
rescue NameError
  # CRuby の下読み。target VM では定義される
end

# gem の定数を継承しない plain な fake なので rescue は要らない。
class InstrumentRunnerTestLink
  attr_reader :written

  def initialize
    @written = []
  end

  def write(data)
    @written << data
    data.to_s.bytesize
  end
end

# G1: silence (teardown 内の link.write) が例外を投げても teardown は必ず走ることを見るための fake。
class InstrumentRunnerTestRaisingLink
  def write(_data)
    raise RuntimeError, "link down"
  end
end

class InstrumentRunnerTest < Picotest::Test
  def build(idle_ms = 0, binary = false)
    link = InstrumentRunnerTestLink.new
    InstrumentRunnerTestFake.new(link: link, idle_ms: idle_ms, binary: binary)
  end

  def test_run_requires_a_tick_block
    assert_raise(Instrument::Runner::Error) { build.run }
  end

  def test_setup_tick_teardown_order_and_seq
    log = []
    r = build
    r.setup    { log << :setup }
    r.tick     { |i| log << :tick; i.emit(gate: 1, note_milli: 60_000, depth: 0); i.stop if i.ticks >= 2 }
    r.teardown { log << :teardown }
    r.run
    assert_equal [:setup, :tick, :tick, :tick, :teardown], log
    # 3 tick emit + 最後の gate:0 = 4 frame、seq は 0,1,2,3
    frames = r.link.written
    assert_equal 4, frames.size
    assert_equal 3, Instrument::Frame.decode(frames[3])[:seq]
    assert_equal 0, Instrument::Frame.decode(frames[3])[:gate]
  end

  def test_gate_off_is_sent_even_when_tick_raises
    r = build
    r.tick { |i| i.emit(gate: 1, note_milli: 1000, depth: 0); raise "sensor died" }
    raised = false
    begin
      r.run
    rescue RuntimeError
      raised = true
    end
    assert_equal true, raised
    frames = r.link.written
    assert_equal 2, frames.size
    assert_equal 0, Instrument::Frame.decode(frames[1])[:gate]
  end

  def test_no_extra_gate_off_when_already_silent
    r = build
    r.tick { |i| i.emit(gate: 0, note_milli: 0, depth: 0); i.stop }
    r.run
    assert_equal 1, r.link.written.size
  end

  def test_hooks_and_idle
    order = []
    r = build(5)
    r.before_tick { order << :before }
    r.tick { |i| order << :tick; i.stop }
    r.after_tick { order << :after }
    r.run
    assert_equal [:before, :tick, :after], order
    assert_equal [5], r.idled
  end

  def test_binary_runner_emits_binary_frames
    r = build(0, true)
    r.tick { |i| i.emit(gate: 1, note_milli: 60_000, depth: 100); i.stop }
    r.run
    frames = r.link.written
    assert_equal 11, frames[0].bytesize
    assert_equal 0xA5, frames[0].getbyte(0)
    assert_equal 0, Instrument::Frame.decode_binary(frames[1])[:gate]
  end

  # T11a (G1): link が既に落ちていて silence (gate:0 の送出) が例外を投げても、
  # teardown は必ず呼ばれ、RuntimeError が外へ伝わること。
  def test_teardown_runs_even_when_link_write_raises
    link = InstrumentRunnerTestRaisingLink.new
    r = InstrumentRunnerTestFake.new(link: link, idle_ms: 0, binary: false)
    teardown_ran = false
    r.tick { |i| i.emit(gate: 1, note_milli: 1000, depth: 0); raise "sensor died" }
    r.teardown { teardown_ran = true }
    raised = nil
    begin
      r.run
    rescue RuntimeError => e
      raised = e
    end
    assert_not_nil raised
    assert_equal true, teardown_ran
  end
end
