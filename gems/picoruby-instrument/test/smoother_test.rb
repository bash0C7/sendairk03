class InstrumentSmootherTest < Picotest::Test
  def test_first_sample_passes_through
    s = Instrument::Smoother.new
    assert_equal 100, s.update(100)
    assert_equal true, s.in_range?
  end

  def test_ema_follows_with_alpha
    s = Instrument::Smoother.new(window: 1, alpha: 50)
    s.update(100)
    assert_equal 150, s.update(200)
    assert_equal 175, s.update(200)
  end

  def test_median_rejects_a_single_spike
    s = Instrument::Smoother.new(window: 3, alpha: 100)
    s.update(100)
    s.update(100)
    assert_equal 100, s.update(20)   # spike (ToF の 20mm 外れ値) は消える
    assert_equal 100, s.update(100)
  end

  def test_out_of_range_keeps_the_previous_value
    s = Instrument::Smoother.new(alpha: 100, min: 30, max: 570)
    s.update(100)
    assert_equal 100, s.update(8190)
    assert_equal false, s.in_range?
    assert_equal 100, s.update(nil)
    assert_equal 100, s.update(10)
  end

  def test_reset_forgets
    s = Instrument::Smoother.new
    s.update(100)
    s.reset
    assert_nil s.value
    assert_equal 5, s.update(5)
  end

  def test_rejects_bad_alpha
    assert_raise(ArgumentError) { Instrument::Smoother.new(alpha: 0) }
  end
end
