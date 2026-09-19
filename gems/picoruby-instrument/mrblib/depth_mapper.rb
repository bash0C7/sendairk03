# 傾き (加速度差) → depth (0..1000)。FM depth / filter 開度など「音色」側のパラメータに使う。
#
#   dm = Instrument::DepthMapper.new(scale: 500, curve: :linear)
#   dm.depth(ax, ay, az)   # => 0..1000   (|ax|+|ay|+|az| を scale で割った 0..1 を x1000)
#
# curve: :linear / :square (ゆっくり立ち上がる) / :sqrt (すぐ立ち上がる)
module Instrument
  class DepthMapper
    CURVES = [:linear, :square, :sqrt]

    attr_reader :scale, :curve

    def initialize(scale: 500, curve: :linear)
      raise ArgumentError, "scale must be a positive Integer" unless scale.is_a?(Integer) && scale > 0
      self.curve = curve
      @scale = scale
    end

    def curve=(value)
      raise ArgumentError, "curve must be one of #{CURVES.inspect}" unless CURVES.include?(value)
      @curve = value
      value
    end

    def depth(ax, ay = 0, az = 0)
      mag = ax.to_i.abs + ay.to_i.abs + az.to_i.abs
      d = mag * 1000 / @scale
      d = 1000 if d > 1000
      case @curve
      when :square then d * d / 1000
      when :sqrt   then isqrt(d * 1000)
      else d
      end
    end

    private

    # 整数平方根 (Newton 法)。n <= 1_000_000
    def isqrt(n)
      return 0 if n <= 0
      x = n
      y = (x + 1) / 2
      while y < x
        x = y
        y = (x + n / x) / 2
      end
      x
    end
  end
end
