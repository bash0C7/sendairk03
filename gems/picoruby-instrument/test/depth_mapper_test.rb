class InstrumentDepthMapperTest < Picotest::Test
  def test_linear_manhattan
    dm = Instrument::DepthMapper.new(scale: 500)
    assert_equal 0, dm.depth(0, 0, 0)
    assert_equal 500, dm.depth(100, -100, 50)
    assert_equal 1000, dm.depth(500, 0, 0)
    assert_equal 1000, dm.depth(9999, 0, 0)
  end

  def test_curves
    sq = Instrument::DepthMapper.new(scale: 1000, curve: :square)
    assert_equal 250, sq.depth(500)
    rt = Instrument::DepthMapper.new(scale: 1000, curve: :sqrt)
    assert_equal 707, rt.depth(500)
    assert_equal 1000, rt.depth(1000)
    assert_equal 0, rt.depth(0)
  end

  def test_validation
    assert_raise(ArgumentError) { Instrument::DepthMapper.new(scale: 0) }
    assert_raise(ArgumentError) { Instrument::DepthMapper.new(curve: :cubic) }
  end
end
