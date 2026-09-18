class InstrumentPitchMapperTest < Picotest::Test
  def mapper(**opts)
    Instrument::PitchMapper.new(**opts)
  end

  def test_continuous_is_linear_between_the_ends
    pm = mapper(dist_min: 30, dist_max: 570, note_min: 48, note_max: 72)
    assert_equal 48_000, pm.note_milli(30)
    assert_equal 72_000, pm.note_milli(570)
    assert_equal 60_000, pm.note_milli(300)
  end

  def test_out_of_range_sticks_to_the_ends
    pm = mapper
    assert_equal 48_000, pm.note_milli(0)
    assert_equal 72_000, pm.note_milli(9999)
    assert_equal false, pm.in_range?(0)
    assert_equal true, pm.in_range?(300)
    assert_equal false, pm.in_range?(nil)
  end

  def test_snap_to_major_pentatonic
    pm = mapper(mode: :snap, scale: :major_pentatonic)
    # 300mm → 60.0 (C4) はそのまま。61 (C#) は C か D に寄る
    assert_equal 60_000, pm.note_milli(300)
    pm2 = mapper(dist_min: 0, dist_max: 120, note_min: 0, note_max: 120, mode: :snap, scale: :major_pentatonic)
    assert_equal 60_000, pm2.note_milli(61)   # C# は C(60) と D(62) から同距離。同距離なら低いほう (最初に見つかった最短)
    assert_equal 62_000, pm2.note_milli(63)   # D# → D(62) と E(64) の同距離、低いほう
    assert_equal 64_000, pm2.note_milli(65)   # F は pentatonic に無い → E(64) と G(67) のうち近い E
  end

  def test_snap_prefers_the_nearest_degree
    pm = mapper(dist_min: 0, dist_max: 120, note_min: 0, note_max: 120, mode: :snap, scale: :major)
    assert_equal 64_000, pm.note_milli(64)    # E は major に居る
    assert_equal 65_000, pm.note_milli(66)    # F# → F(65) か G(67): 同距離なら低いほう
    assert_equal 71_000, pm.note_milli(71)    # B
    assert_equal 72_000, pm.note_milli(72)    # C (次のオクターブ)
  end

  def test_transpose_shifts_the_note
    pm = mapper(transpose: 12)
    assert_equal 72_000, pm.note_milli(300)
    pm.transpose = -12
    assert_equal 48_000, pm.note_milli(300)
  end

  def test_freq_of_a4_and_octaves
    pm = mapper
    assert_equal 440_000, pm.freq_milli(69_000)
    assert_equal 880_000, pm.freq_milli(81_000)
    assert_equal 220_000, pm.freq_milli(57_000)
  end

  def test_freq_of_middle_c_and_half_semitone
    pm = mapper
    c4 = pm.freq_milli(60_000)
    assert c4 >= 261_600 && c4 <= 261_700   # 261.63 Hz
    half = pm.freq_milli(69_500)            # A4 + 50 cents ≈ 452.89 Hz (線形補間なので ±0.1%)
    assert half >= 452_400 && half <= 453_400
  end

  def test_setters_validate
    pm = mapper
    assert_raise(ArgumentError) { pm.mode = :random }
    assert_raise(ArgumentError) { pm.scale = :dorian }
    assert_raise(ArgumentError) { mapper(dist_min: 100, dist_max: 50) }
    pm.mode = :snap
    pm.scale = :minor_pentatonic
    assert_equal :minor_pentatonic, pm.scale
  end
end
