# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'
require 'tmpdir'

describe LLMed::LiterateProgramming, '.execute' do
  it 'routes application directives and leaves others in the environment' do
    code = <<~MD
      #% a comment

      #!environment language ruby
      #!environment output_file x.rb
      #!environment llm_provider openai

      # Main
      Show hi.
    MD

    contexts = nil
    application_args = nil
    environment = nil
    described_class.execute(code) do |ctxs, args, env|
      contexts = ctxs
      application_args = args
      environment = env
    end

    expect(application_args).to eq(language: 'ruby', output_file: 'x.rb')

    expect(environment).to have_key(:llm_provider)
    expect(environment[:llm_provider]).to eq('openai')
    expect(environment).not_to have_key('llm_provider')

    expect(contexts.size).to eq(1)
    expect(contexts.first[:title]).to eq('Main')
    expect(contexts.first[:content]).to include('Show hi.')
    expect(contexts.first[:content]).not_to include('#% a comment')
    expect(contexts.first[:content]).not_to include('#!environment')
  end

  it 'inlines a relative markdown link by fetching the file' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'thefile.rb'), "puts 'linked'\n")

      Dir.chdir(dir) do
        code = <<~MD
          # Src
          [src](thefile.rb)
        MD

        contexts = nil
        described_class.execute(code) do |ctxs, _args, _env|
          contexts = ctxs
        end

        expect(contexts.size).to eq(1)
        expect(contexts.first[:title]).to eq('Src')
        expect(contexts.first[:content]).to include("puts 'linked'")
      end
    end
  end
end
