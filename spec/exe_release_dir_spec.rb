# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'bundler'

RSpec.describe 'exe release dir colocation' do
  repo = File.expand_path('..', __dir__)
  gem_home = File.expand_path('../vendor/gems', __dir__)

  def run_exe(repo, gem_home, chdir, args, stdin: nil)
    env = {
      'GEM_HOME' => gem_home,
      'LLMED_PROVIDER_API_KEY' => '',
      'LLMED_PROVIDER_MODEL' => 'test-model',
      'LLMED_PROVIDER_URI_BASE' => 'https://example.invalid/v1'
    }
    out = +''
    err = +''
    status = nil
    Bundler.with_unbundled_env do
      Open3.popen3(env, RbConfig.ruby, '-r', File.join(repo, 'spec/support/notify_neutralizer.rb'), '-I', File.join(repo, 'lib'), *args, chdir: chdir) do |i, o, e, t|
        if stdin
          i.write(stdin)
          i.close
        else
          i.close
        end
        out = o.read
        err = e.read
        status = t.value
      end
    end
    [status, out, err]
  end

  doc_content = <<~DOC
    <!--
    #!environment llm_provider test
    #!environment language ruby
    #!environment output_file out.rb
    #!environment release 1
    -->

    # Main

    Show hi.
  DOC

  it 'places release artifacts beside the doc for file invocation (exe/llmed.literate)' do
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, 'sub'))
      doc = File.join(tmp, 'sub', 'doc.llmed.md')
      File.write(doc, doc_content)

      status, _out, err = run_exe(repo, gem_home, tmp, [File.join(repo, 'exe', 'llmed.literate'), 'sub/doc.llmed.md'])
      puts "exe/llmed.literate stderr: #{err}" unless status.success?
      expect(status.success?).to be(true), "exe failed: #{err}"

      expect(File.exist?(File.join(tmp, 'sub', 'out.rb.r1ruby.cache'))).to be(true)
      expect(File.exist?(File.join(tmp, 'llmed-out', 'out.rb.r1ruby.cache'))).to be(false)
    end
  end

  it 'places release artifacts beside the source for file invocation (exe/llmed)' do
    Dir.mktmpdir do |tmp|
      FileUtils.mkdir_p(File.join(tmp, 'sub'))
      source = File.join(tmp, 'sub', 'app.llmed')
      File.write(source, <<~SRC)
        set_llm provider: :test, api_key: '', model: ''

        application "app", release: 1, language: :ruby, output_file: 'app.rb' do
          context "main" do
            "Show hi."
          end
        end
      SRC

      status, _out, err = run_exe(repo, gem_home, tmp, [File.join(repo, 'exe', 'llmed'), 'sub/app.llmed'])
      puts "exe/llmed stderr: #{err}" unless status.success?
      expect(status.success?).to be(true), "exe failed: #{err}"

      expect(File.exist?(File.join(tmp, 'sub', 'app.rb.r1ruby.cache'))).to be(true)
      expect(File.exist?(File.join(tmp, 'llmed-out', 'app.rb.r1ruby.cache'))).to be(false)
    end
  end

  it 'keeps the default output dir for stdin invocation (regression guard)' do
    Dir.mktmpdir do |tmp|
      status, _out, err = run_exe(repo, gem_home, tmp, [File.join(repo, 'exe', 'llmed.literate')], stdin: doc_content)
      puts "stdin stderr: #{err}" unless status.success?
      expect(status.success?).to be(true), "exe failed: #{err}"
      expect(File.exist?(File.join(tmp, 'llmed-out', 'out.rb.r1ruby.cache'))).to be(true)
    end
  end
end
