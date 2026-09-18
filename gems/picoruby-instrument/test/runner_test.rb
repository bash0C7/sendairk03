# link gem の Loopback を fake に使う。picotest の runner は test file を CRuby でも load するので、
# CRuby 側で見つからない require は無視する (target VM では runner の Kernel#require が同じことをする)
begin
  require "instrument/link"
rescue LoadError
end
# Instrument::Runner のライフサイクル。link は gem 内の Loopback、idle は待たない subclass で差し替える。
#
# fake の作り方: mruby/c には Class.new が無く、Ruby は method の中に class を書けない。
# picotest の runner は test file をまず CRuby で load して test class を数えるので、top level で
# gem の定数に触ると CRuby 側で NameError になる。そこで begin/rescue NameError で囲んで
# 「gem が居る VM でだけ」fake class を定義する (CRuby の下読みでは黙って飛ばされる)。
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

class InstrumentRunnerTest < Picotest::Test
  def build(idle_ms = 0, binary = false)
    link = Instrument::Link::Loopback.new
    InstrumentRunnerTestFake.new(link: link, idle_ms: idle_ms, binary: binary)
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
    frames = r.link.written
    assert_equal 4, frames.size
    assert_equal 3, Instrument::Frame.decode(frames[3])[:seq]
    assert_equal 0, Instrument::Frame.decode(frames[3])[:gate]
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
    frames = r.link.written
    assert_equal 2, frames.size
    assert_equal 0, Instrument::Frame.decode(frames[1])[:gate]
  end

  def test_no_extra_gate_off_when_already_silent
    r = build
    r.run do |inst|
      inst.tick { |i| i.emit(gate: 0, note_milli: 0, depth: 0); i.stop }
    end
    assert_equal 1, r.link.written.size
  end

  def test_hooks_and_idle
    order = []
    r = build(5)
    r.run do |inst|
      inst.before_tick { order << :before }
      inst.tick { |i| order << :tick; i.stop }
      inst.after_tick { order << :after }
    end
    assert_equal [:before, :tick, :after], order
    assert_equal [5], r.idled
  end

  def test_binary_runner_emits_binary_frames
    r = build(0, true)
    r.run do |inst|
      inst.tick { |i| i.emit(gate: 1, note_milli: 60_000, depth: 100); i.stop }
    end
    frames = r.link.written
    assert_equal 11, frames[0].bytesize
    assert_equal 0xA5, frames[0].getbyte(0)
    assert_equal 0, Instrument::Frame.decode_binary(frames[1])[:gate]
  end
end
