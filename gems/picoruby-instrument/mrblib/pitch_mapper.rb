# 距離 (mm) → 音程。talk の section 2「音程の作り方」の本体。
#
#   pm = Instrument::PitchMapper.new(dist_min: 30, dist_max: 570, note_min: 48, note_max: 72,
#                                    mode: :continuous, scale: :major_pentatonic, transpose: 0)
#   pm.note_milli(dist_mm)      # => MIDI note x1000 (mode :continuous は連続値、:snap は音階に吸着)
#   pm.freq_milli(note_milli)   # => Hz x1000 (440 * 2 ** ((n - 69) / 12))
#
# mode / scale / transpose は attr_accessor。DRb 越しに差し替える口でもある。
# 整数演算だけで書く (mruby/c と mruby で同じ結果になる)。2 の冪乗は 1/12 刻みの表で引く。
module Instrument
  class PitchMapper
    MODES = [:continuous, :snap]
    # 2 ** (i / 1200.0) * 1_000_000 (i = 0..1199 cents) は表が大きいので、
    # 半音 (2 ** (k/12)) の 12 個と cents の線形補間で近似する。誤差は 0.1% 未満。
    SEMITONE_RATIO_MILLIONS = [
      1_000_000, 1_059_463, 1_122_462, 1_189_207, 1_259_921, 1_334_840,
      1_414_214, 1_498_307, 1_587_401, 1_681_793, 1_781_797, 1_887_749
    ]
    A4_MILLIHZ = 440_000

    attr_reader :dist_min, :dist_max, :note_min, :note_max, :mode, :scale, :transpose

    def initialize(dist_min: 30, dist_max: 570, note_min: 48, note_max: 72,
                   mode: :continuous, scale: :major_pentatonic, transpose: 0)
      raise ArgumentError, "dist_min must be < dist_max" unless dist_min < dist_max
      raise ArgumentError, "note_min must be < note_max" unless note_min < note_max
      @dist_min = dist_min
      @dist_max = dist_max
      @note_min = note_min
      @note_max = note_max
      @transpose = transpose
      self.mode = mode
      self.scale = scale
    end

    def mode=(value)
      raise ArgumentError, "mode must be one of #{MODES.inspect}" unless MODES.include?(value)
      @mode = value
      value
    end

    def scale=(value)
      raise ArgumentError, "unknown scale #{value.inspect}" unless SCALES[value]
      @scale = value
      @degrees = SCALES[value]
      value
    end

    def transpose=(value)
      @transpose = value.to_i
      value
    end

    def in_range?(dist_mm)
      !dist_mm.nil? && dist_mm >= @dist_min && dist_mm <= @dist_max
    end

    # 範囲外は端に張り付ける (鳴らすかどうかは Gate が決めるので、ここでは nil を返さない)
    def note_milli(dist_mm)
      d = dist_mm.to_i
      d = @dist_min if d < @dist_min
      d = @dist_max if d > @dist_max
      span = @dist_max - @dist_min
      raw = @note_min * 1000 + (d - @dist_min) * (@note_max - @note_min) * 1000 / span
      raw += @transpose * 1000
      @mode == :snap ? snap(raw) : raw
    end

    # note_milli (MIDI x1000) → 周波数 mHz。
    def freq_milli(note_milli)
      milli = note_milli - 69_000
      octaves = 0
      while milli < 0
        milli += 12_000
        octaves -= 1
      end
      while milli >= 12_000
        milli -= 12_000
        octaves += 1
      end
      semi = milli / 1000
      frac = milli - semi * 1000           # 0..999 (1/1000 semitone)
      lo = SEMITONE_RATIO_MILLIONS[semi]
      hi = semi == 11 ? 2_000_000 : SEMITONE_RATIO_MILLIONS[semi + 1]
      ratio = lo + (hi - lo) * frac / 1000 # x1_000_000
      freq = A4_MILLIHZ * ratio / 1_000_000
      if octaves > 0
        freq = freq << octaves
      elsif octaves < 0
        freq = freq >> (-octaves)
      end
      freq
    end

    private

    def snap(raw_milli)
      note = (raw_milli + 500) / 1000
      octave = note / 12
      pc = note - octave * 12
      degrees = @degrees
      best = nil
      best_dist = 99
      i = 0
      size = degrees.size
      while i < size
        deg = degrees[i]
        # 同じ度数を 1 オクターブ下/上でも試す (B と C の跨ぎ)
        k = -1
        while k <= 1
          cand = deg + k * 12
          dist = (cand - pc).abs
          if dist < best_dist
            best_dist = dist
            best = cand
          end
          k += 1
        end
        i += 1
      end
      (octave * 12 + best) * 1000
    end
  end
end
