class InstrumentGateTest < Picotest::Test
  def test_momentary_follows_the_button
    g = Instrument::Gate.new
    assert_equal false, g.update(false)
    assert_nil g.edge
    assert_equal true, g.update(true)
    assert_equal :rising, g.edge
    assert_equal true, g.update(true)
    assert_nil g.edge
    assert_equal false, g.update(false)
    assert_equal :falling, g.edge
  end

  def test_toggle_flips_on_each_press
    g = Instrument::Gate.new(mode: :toggle)
    assert_equal true, g.update(true)
    assert_equal true, g.update(true)   # held: no change
    assert_equal true, g.update(false)
    assert_equal false, g.update(true)
    assert_equal :falling, g.edge
  end

  def test_latch_stays_on
    g = Instrument::Gate.new(mode: :latch)
    g.update(true)
    assert_equal true, g.update(false)
    assert_equal false, g.release
    assert_equal :falling, g.edge
  end

  def test_rejects_unknown_mode
    assert_raise(ArgumentError) { Instrument::Gate.new(mode: :hold) }
  end
end
