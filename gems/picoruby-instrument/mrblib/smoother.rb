# 距離センサーの平滑化: median (外れ値) → EMA (追従)。整数演算だけ。
#
#   s = Instrument::Smoother.new(window: 3, alpha: 50, min: 30, max: 570)
#   s.update(raw_mm)  # => 平滑化した値。範囲外の raw は捨てて前の値を返す (nil にはしない)
#   s.in_range?       # => 直前の raw が [min, max] に入っていたか
#
# alpha は 0..100 (%)。100 なら EMA なし。picoruby-ot の実測では 50 が追従とノイズの折り合い。
module Instrument
  class Smoother
    attr_reader :value, :alpha, :min, :max

    def initialize(window: 3, alpha: 50, min: nil, max: nil)
      raise ArgumentError, "alpha must be 1..100" unless alpha.is_a?(Integer) && alpha >= 1 && alpha <= 100
      @median = MedianFilter.new(window: window)
      @alpha = alpha
      @min = min
      @max = max
      @value = nil
      @in_range = false
    end

    def in_range?
      @in_range
    end

    def update(raw)
      if raw.nil? || (@min && raw < @min) || (@max && raw > @max)
        @in_range = false
        return @value
      end
      @in_range = true
      med = @median.update(raw.to_i)
      if @value.nil?
        @value = med
      else
        @value = @value + (med - @value) * @alpha / 100
      end
      @value
    end

    def reset
      @median.reset
      @value = nil
      @in_range = false
      nil
    end
  end
end
