# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'
require 'logger'
require 'stringio'
require 'json'

describe LLMed do
  before do
    logger = Logger.new(STDOUT)
    @llmed = LLMed.new(logger: logger, output_dir: '/tmp', release_dir: '/tmp')
  end

  it 'configuration' do
    @llmed.set_language 'ruby'
    @llmed.set_llm provider: :openai, api_key: 'key', model: 'model'
  end

  it 'prompt from file' do
    output = StringIO.new
    @llmed.set_language :ruby
    @llmed.set_llm(provider: :test, api_key: '', model: '')
    @llmed.set_prompt(file: './spec/external_prompt.pllmed')
    @llmed.application('demo', output_file: output) {}
    @llmed.compile

    expect(output.string).to including('LLMED external prompt')
  end

  it 'compile application skip context' do
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    fake = StringIO.new
    @llmed.application 'demo', output_file: fake do
      context('main', :skip) { from_file('./spec/hiworld.cllmed') }
    end
    @llmed.compile

    expect(fake.string).not_to including('hola mundo')
  end

  it 'compile application to file with statistics' do
    output_file = `mktemp`.chomp
    output_stats = "#{output_file}.statistics"
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    @llmed.application 'demo', output_file: output_file do
      context('main') { from_file('./spec/hiworld.cllmed') }
    end
    @llmed.compile

    expect(File.read(output_file)).to including("puts 'hola mundo'")
    stats = JSON.load(File.open(output_stats))

    expect(stats).to include(
      'provider' => 'openai',
      'model' => 'gpt-4o-mini',
      'release' => nil
    )
    expect(stats['duration_seconds']).to be > 0
  end

  it 'compile application to STDOUT' do
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    fake = StringIO.new
    @llmed.application 'demo', output_file: fake do
      context('main') { from_file('./spec/hiworld.cllmed') }
    end
    @llmed.compile

    expect(fake.string).to including("puts 'hola mundo'")
  end

  it 'compile application to release' do
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    output_file = `mktemp`.chomp
    release_file = "#{output_file}.release"

    # first iteration
    @llmed.application 'demo', output_file: output_file do
      context('main') { "Show to the user 'hola mundo'" }
    end
    @llmed.compile

    # once agree create release
    @llmed.application 'demo', release: 1, output_file: output_file do
      context('main') { "Show to the user 'hola mundo'" }
    end
    @llmed.compile

    expect(File.exist?(release_file))
    expect(File.read(release_file)).to including("puts 'hola mundo'")
  end

  it 'compile application connecting applications through output' do
    tempfile = `mktemp`.chomp
    tempfile_bye = `mktemp`.chomp
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'

    @llmed.application 'main', output_file: tempfile do
      context 'main' do
        llm <<-LLM
        Imprimir mensaje 'hola mundo'.
        LLM
      end
    end

    @llmed.application 'demo', output_file: tempfile_bye do
      context('source main') { from_source_code(tempfile) }

      context('adicionar despedida') do
        <<-LLM
        Adicionar imprimir mensaje 'bye mundo'.
        LLM
      end
    end

    @llmed.compile

    expect(File.read(tempfile_bye)).to including("puts 'hola mundo'")
    expect(File.read(tempfile_bye)).to including("puts 'bye mundo'")
  end

  it 'compile application including context' do
    tempfile = `mktemp`.chomp
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    @llmed.application 'demo', output_file: tempfile do
      context('main') { from_file('./spec/hiworld.cllmed') }
    end

    @llmed.compile

    expect(File.read(tempfile)).to including("puts 'hola mundo'")
  end

  it 'compile application with implicit language' do
    tempfile = `mktemp`.chomp
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.set_language 'ruby'
    @llmed.application 'demo', output_file: tempfile do
      context 'main' do
        llm <<-LLM
        Codigo que imprima 'hola mundo'.
        LLM
      end
    end
    @llmed.compile

    expect(File.read(tempfile)).to including("puts 'hola mundo'")
  end

  it 'compile application with explicit language' do
    tempfile = `mktemp`.chomp
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.application 'demo', language: 'ruby', output_file: tempfile do
      context 'main' do
        llm <<-LLM
        Codigo que imprima 'hola mundo'.
        LLM
      end
    end
    @llmed.compile

    expect(File.read(tempfile)).to including("puts 'hola mundo'")
  end

  it 'compile application from string' do
    tempfile = `mktemp`.chomp
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
    @llmed.eval_source <<-SOURCE
    application "demo", language: 'ruby', output_file: '#{tempfile}' do
      context "main" do
        llm <<-LLM
        Codigo ruby que imprima 'hola mundo'.
        LLM
      end
    end
    SOURCE

    @llmed.compile

    expect(File.read(tempfile)).to including("puts 'hola mundo'")
  end

  context 'multiple applications' do
    it 'ruby and python' do
      tempfile_ruby = `mktemp`.chomp
      tempfile_python = `mktemp`.chomp
      @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')
      @llmed.application 'demo', language: 'ruby', output_file: tempfile_ruby do
        context 'main' do
          llm <<-LLM
        Codigo que imprima 'hola mundo'.
          LLM
        end
      end

      @llmed.application 'demo python', language: 'python', output_file: tempfile_python do
        context 'main' do
          llm <<-LLM
        Codigo que imprima 'hola mundo'.
          LLM
        end
      end

      @llmed.compile

      expect(File.read(tempfile_ruby)).to including("puts 'hola mundo'")
      expect(File.read(tempfile_python)).to including("print('hola mundo')")
    end
  end
end
