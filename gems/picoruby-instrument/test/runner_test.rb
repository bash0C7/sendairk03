# Instrument::Runner のライフサイクル。link は gem 内の Loopback、idle は待たない subclass で差し替える。
#
# fake の作り方: mruby/c には Class.new が無く、Ruby は method の中に class を書けない。
# picotest の runner は test file をまず CRuby で load して test class を数えるので、top level で
# gem の定数に触ると CRuby 側で NameError になる。そこで begin/rescue NameError で囲んで
# 「gem が居る VM でだけ」fake class を定義する (CRuby の下読みでは黙って飛ばされる)。
#
# block の登録はフラットに書く (r.tick { ... } を method の直下で)。mruby/c では
# `r.run { |inst| inst.tick { log << :x } }` のように入れ子にした内側の block が外側の block より
# 長生きして外側のローカル変数を掴むと VM が落ちる (docs/spec.md「mruby/c の制約」)。
begin
  require "instrument/link"
rescue LoadError
end

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

  # run にブロックを渡す形も動く。ただし内側の block は外側のローカルを掴まない (mruby/c の制約)
  def test_run_with_a_configuration_block
    r = build
    r.run { |inst| inst.tick { |i| i.emit(gate: 1, note_milli: 1000, depth: 0); i.stop } }
    assert_equal 2, r.link.written.size
    assert_equal 1, r.ticks
  end
end
