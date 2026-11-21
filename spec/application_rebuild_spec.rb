# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'
require 'tmpdir'
require 'digest'
require 'logger'
require 'stringio'

# rebuild? and digests_of_context_to_update are private, tested via #send
describe LLMed::Application, 'release rebuild engine (private API via #send)' do
  def build_application(dir, &block)
    LLMed::Application.new(
      name: 'rebuild',
      language: :ruby,
      output_file: 'rebuild.rb',
      block: block,
      logger: Logger.new(StringIO.new),
      release: 1,
      release_dir: dir,
      output_dir: dir
    ).tap(&:evaluate)
  end

  def marker(name, digest)
    "#<llmed-code context='#{name}' digest='#{digest}' after=''>\ncode\n#</llmed-code>"
  end

  def write_cache(app, content)
    File.write(app.send(:release_source_code).to_s, content)
  end

  it 'reports nothing to rebuild when the release cache is missing' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
        context('deps') { 'content A' }
      end

      expect(File.exist?(app.send(:release_source_code).to_s)).to be false
      expect(app.send(:digests_of_context_to_update)).to eq []
      expect(app.send(:rebuild?)).to be true
    end
  end

  it 'rebuilds when the release cache has no llmed-code markers' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
        context('deps') { 'content A' }
      end

      write_cache(app, 'garbage without any markers')
      expect(app.send(:release_contexts)).to eq({})
      expect(app.send(:rebuild?)).to be true
    end
  end

  it 'reports no changes when every context digest matches the release' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
        context('deps') { 'content A' }
      end

      deps_digest = Digest::SHA256.hexdigest('deps.content A')
      write_cache(app, marker('deps', deps_digest))

      expect(app.send(:digests_of_context_to_update)).to eq []
      expect(app.send(:rebuild?)).to be false
    end
  end

  it 'rebuilds only the last context when it changed' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
        context('deps') { 'content A' }
        context('main') { 'content B' }
      end

      deps_digest = Digest::SHA256.hexdigest('deps.content A')
      write_cache(app, [
                    marker('deps', deps_digest),
                    marker('main', 'OLDMAIN')
                  ].join("\n"))

      expect(app.send(:digests_of_context_to_update)).to eq(['OLDMAIN'])
      expect(app.send(:rebuild?)).to be true
    end
  end

  it 'cascades the rebuild from the first changed context to the end' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
context('deps') { 'content A' }
        context('api') { 'content B' }
        context('main') { 'content C' }
      end

      write_cache(app, [
                    marker('deps', 'OLDDEPS'),
                    marker('api', 'OLD API-MARKER'),
                    marker('main', 'OLD MAIN-MARKER')
                  ].join("\n"))

      expect(app.send(:digests_of_context_to_update)).to eq(
        ['OLDDEPS', 'OLD API-MARKER', 'OLD MAIN-MARKER']
      )
      expect(app.send(:rebuild?)).to be true
    end
  end

  it 'rebuilds a newly added context with its user digest' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
        context('deps') { 'content A' }
        context('main') { 'content B' }
      end

      deps_digest = Digest::SHA256.hexdigest('deps.content A')
      write_cache(app, marker('deps', deps_digest))

      expect(app.send(:digests_of_context_to_update)).to eq(
        [Digest::SHA256.hexdigest('main.content B')]
      )
      expect(app.send(:rebuild?)).to be true
    end
  end

  it 'reports an added context before the changed one in mixed order' do
    Dir.mktmpdir do |dir|
      app = build_application(dir) do
context('new') { 'brand new' }
        context('deps') { 'content A' }
      end

      write_cache(app, marker('deps', 'OLDDEPS'))

      expect(app.send(:digests_of_context_to_update)).to eq(
        [Digest::SHA256.hexdigest('new.brand new'), 'OLDDEPS']
      )
      expect(app.send(:rebuild?)).to be true
    end
  end
end
