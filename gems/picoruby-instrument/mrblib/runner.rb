# 楽器の「器」。harness の USB::Peripheral と同じ形: setup / tick / teardown をブロックで受け、
# ループと後始末をここが持つ。アプリはセンサーを読んで emit するだけ。
#
#   runner = Instrument::Runner.new(link: link)
#   runner.setup    { |i| ... センサー初期化 ... }
#   runner.tick     { |i| i.emit(gate: g, note_milli: n, depth: d, dist: mm) }
#   runner.teardown { |i| ... LED 消灯など ... }
#   runner.run
#
# block はこのようにフラットに登録する。`run do |inst| inst.tick { ... } end` の入れ子も mruby では動くが、
# mruby/c (FemtoRuby = ATOM Matrix) では、外側の block が返った後に呼ばれる内側の block が外側の
# ローカル変数を掴んでいると VM が assertion で落ちる (escaped closure)。センサーや LED の変数は
# 登録した場所と同じスコープに置く。
#
# Runner が保証すること (= アプリに書かせないこと):
#   - seq の付番と frame 送出の一元化 (link.write)
#   - tick が raise しても、stop されても、必ず gate:0 の frame を 1 回送ってから teardown を呼ぶ (stuck note を残さない)
#   - before_tick / after_tick のフック (IRQ.process を挟む場所)
#   - idle(ms) は差し替え可能な seam (テストでは待たない)
require "instrument/frame"

module Instrument
  class Runner
    class Error < StandardError; end

    attr_reader :link, :seq, :ticks, :last_frame

    def initialize(link:, idle_ms: 0, binary: false)
      @link = link
      @idle_ms = idle_ms
      @binary = binary
      @seq = 0
      @ticks = 0
      @stopped = false
      @last_frame = nil
      @setup = nil
      @tick = nil
      @teardown = nil
      @before_tick = nil
      @after_tick = nil
    end

    def setup(&block);       @setup = block; end
    def tick(&block);        @tick = block; end
    def teardown(&block);    @teardown = block; end
    def before_tick(&block); @before_tick = block; end
    def after_tick(&block);  @after_tick = block; end

    def stop
      @stopped = true
    end

    def stopped?
      @stopped
    end

    # frame を 1 つ送る。seq はここで付ける。
    def emit(gate:, note_milli:, depth:, dist: 0, tilt_x: 0, tilt_y: 0)
      frame = if @binary
                Frame.encode_binary(gate: gate, note_milli: note_milli, depth: depth, dist: dist,
                                    tilt_x: tilt_x, tilt_y: tilt_y, seq: @seq)
              else
                Frame.encode(gate: gate, note_milli: note_milli, depth: depth, dist: dist,
                             tilt_x: tilt_x, tilt_y: tilt_y, seq: @seq)
              end
      @seq = (@seq + 1) % Frame::SEQ_WRAP
      @last_gate = Frame.gate_bit(gate)
      @last_frame = frame
      @link.write(frame)
      frame
    end

    def run(&block)
      block.call(self) if block
      raise Error, "tick block is required" unless @tick
      @stopped = false
      @setup&.call(self)
      begin
        until @stopped
          @before_tick&.call(self)
          @tick.call(self)
          @after_tick&.call(self)
          @ticks += 1
          idle(@idle_ms) if @idle_ms > 0
        end
      ensure
        silence
        @teardown&.call(self)
      end
      self
    end

    # 例外でも stop でも、最後に必ず gate:0 を送る。
    def silence
      return if @last_gate == 0 || @last_gate.nil?
      emit(gate: 0, note_milli: 0, depth: 0)
    end

    # seam: 実機では sleep_ms、テストでは差し替える
    def idle(ms)
      sleep_ms(ms)
    end
  end
end
