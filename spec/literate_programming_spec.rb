# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'

describe LLMed::LiterateProgramming do
  before do
    logger = Logger.new($stdout)
    @llmed = LLMed.new(logger: logger, output_dir: '/tmp', release_dir: '/tmp')
  end

  it 'execute literate include resource' do
    @llmed.set_language 'ruby'
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')

    code = <<~CODE
      # Main

      [hiworld](./spec/hiworld.cllmed)

    CODE
    fake = StringIO.new
    described_class.execute(code, output_file: fake) do |contexts, application_args, _environment|
      @llmed.application('test', **application_args) do
        contexts.each do |lcontext|
          context(lcontext[:title]) { lcontext[:content] }
        end
      end
    end

    @llmed.compile
    expect(fake.string).to including('hola mundo')
  end

  it 'execute literate' do
    @llmed.set_language 'ruby'
    @llmed.set_llm(provider: :openai, api_key: ENV.fetch('OPENAI_API_KEY', nil), model: 'gpt-4o-mini')

    code = <<~CODE
      # Main
      Show to the user 'hola mundo'.
    CODE
    fake = StringIO.new
    described_class.execute(code, output_file: fake) do |contexts, application_args, _environment|
      @llmed.application('test', **application_args) do
        contexts.each do |lcontext|
          context(lcontext[:title]) { lcontext[:content] }
        end
      end
    end

    @llmed.compile
    expect(fake.string).to including('hola mundo')
  end
end
