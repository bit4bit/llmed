# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'
require 'tmpdir'
require 'fileutils'

describe LLMed::Application::Snapshot do
  it 'creates missing parent directory when syncing' do
    Dir.mktmpdir do |dir|
      snapshot_file = File.join(dir, 'nested-subdir', 'deeper', 'demo.ollmed.snapshot')
      snapshot = described_class.new(snapshot_file)

      snapshot.sync([])

      expect(File.exist?(snapshot_file)).to be true
    end
  end

  it 'syncs into an existing directory' do
    Dir.mktmpdir do |dir|
      snapshot_file = File.join(dir, 'demo.ollmed.snapshot')
      snapshot = described_class.new(snapshot_file)

      snapshot.sync([])

      expect(File.exist?(snapshot_file)).to be true
    end
  end
end

describe LLMed::Application::Snapshot, 'diff, round-trip and refresh' do
  SnapContext = Struct.new(:name, :raw)

  it 'round-trips unchanged content as no diff and reports line changes otherwise' do
    Dir.mktmpdir do |dir|
      snapshot_file = File.join(dir, 'demo.ollmed.snapshot')

      described_class.new(snapshot_file).sync([SnapContext.new('main', "line1\nline2\n")])

      fresh = described_class.new(snapshot_file)
      # sync loads the JSON file when it exists, ignoring the default
      fresh.sync([])
      expect(fresh.diff([SnapContext.new('main', "line1\nline2\n")])).to eq({})

      changed = fresh.diff([SnapContext.new('main', "line1\nline3\n")])
      expect(changed).to have_key('main')
      expect(changed['main']).to include(['-:', 'line2'], ['+:', 'line3'])
    end
  end

  it 'reports a context missing from the snapshot as all additions' do
    Dir.mktmpdir do |dir|
      snapshot_file = File.join(dir, 'demo.ollmed.snapshot')

      described_class.new(snapshot_file).sync([SnapContext.new('main', "line1\n")])

      fresh = described_class.new(snapshot_file)
      # sync loads the JSON file when it exists, ignoring the default
      fresh.sync([])
      diffs = fresh.diff([SnapContext.new('other', "alpha\nbeta\n")])

      expect(diffs).to have_key('other')
      expect(diffs['other']).to all(include('+:'))
      expect(diffs['other']).to include(['+:', 'alpha'], ['+:', 'beta'])
    end
  end

  it 'refresh replaces the snapshot with the new version' do
    Dir.mktmpdir do |dir|
      snapshot_file = File.join(dir, 'demo.ollmed.snapshot')

      snapshot = described_class.new(snapshot_file)
      snapshot.sync([SnapContext.new('main', "first version\n")])
      snapshot.refresh([SnapContext.new('main', "second version\n")])

      fresh = described_class.new(snapshot_file)
      # sync loads the JSON file when it exists, ignoring the default
      fresh.sync([])
      expect(fresh.diff([SnapContext.new('main', "second version\n")])).to eq({})
      expect(fresh.diff([SnapContext.new('main', "first version\n")])).not_to eq({})
    end
  end
end
