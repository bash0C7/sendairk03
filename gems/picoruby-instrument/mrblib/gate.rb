# 発音 gate。ボタンの生の論理値を食わせて「今鳴らすか」を返す。
# picoruby-ot の「鳴りっぱなし」を設計で殺す部品: 音程 / depth と発音を分離する。
#
#   gate = Instrument::Gate.new(mode: :momentary)   # :momentary 押している間 / :toggle 押すたび反転 / :latch 一度押したら鳴り続ける
#   gate.update(pressed)  # => 今 on か
#   gate.edge             # => :rising | :falling | nil  (直前の update で変わったか)
module Instrument
  class Gate
    MODES = [:momentary, :toggle, :latch]

    attr_reader :mode

    def initialize(mode: :momentary)
      self.mode = mode
      @on = false
      @prev_pressed = false
      @edge = nil
    end

    def mode=(value)
      raise ArgumentError, "mode must be one of #{MODES.inspect}" unless MODES.include?(value)
      @mode = value
      value
    end

    def on?
      @on
    end

    def edge
      @edge
    end

    def changed?
      !@edge.nil?
    end

    # pressed: true/false (pull-up なら GPIO の read == 0 を渡す)
    def update(pressed)
      pressed = pressed ? true : false
      was_on = @on
      case @mode
      when :momentary
        @on = pressed
      when :toggle
        @on = !@on if pressed && !@prev_pressed
      when :latch
        @on = true if pressed
      end
      @prev_pressed = pressed
      @edge = if @on && !was_on
                :rising
              elsif !@on && was_on
                :falling
              else
                nil
              end
      @on
    end

    # 強制 off (teardown / 例外時)。edge は :falling になる
    def release
      was_on = @on
      @on = false
      @prev_pressed = false
      @edge = was_on ? :falling : nil
      false
    end
  end
end
