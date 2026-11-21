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
