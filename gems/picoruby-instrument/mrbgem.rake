MRuby::Gem::Specification.new('picoruby-instrument') do |spec|
  spec.license = 'MIT'
  spec.author  = 'bash0C7'
  spec.summary = 'The shell of a handmade instrument: gate, smoothing, sensor -> pitch / depth mapping, and the run loop'

  # Pure Ruby. Runs on mruby (PicoRuby), mruby/c (FemtoRuby), wasm and darwin.
  # Sensors, LEDs and the link are injected by the app; this gem never touches hardware.
  spec.add_dependency 'picoruby-instrument-frame'
  spec.add_dependency 'picoruby-median_filter'
  spec.require_name = 'instrument'
end
