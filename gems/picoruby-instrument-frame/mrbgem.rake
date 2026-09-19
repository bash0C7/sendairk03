MRuby::Gem::Specification.new('picoruby-instrument-frame') do |spec|
  spec.license = 'MIT'
  spec.author  = 'bash0C7'
  spec.summary = 'Wire protocol for the handmade instrument: ASCII v1 / binary v2 frames and a streaming reader'

  # Pure Ruby, no dependency. Runs on mruby (PicoRuby), mruby/c (FemtoRuby), wasm and darwin.
  # The spec is docs/wire-protocol.md; the tests here are its executable form.
  spec.require_name = 'instrument/frame'
end
