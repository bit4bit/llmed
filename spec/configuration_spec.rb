# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'
require 'tmpdir'
require 'logger'
require 'stringio'

describe LLMed::Configuration do
  def build_configuration
    described_class.new(logger: Logger.new(StringIO.new))
  end

  it 'formats the default prompt with goals and changes sections' do
    config = build_configuration

    result = config.prompt(language: 'ruby',
                           source_code: 'SRC CODE',
                           code_comment_begin: '#',
                           code_comment_end: '',
                           update_context_digests: ['digest1'],
                           changes_of_contexts: "-: removed line\n+: added line",
                           goals: 'SHIP THE FEATURE')

    expect(result).to include('<goals>')
    expect(result).to include('</goals>')
    expect(result).to include('<changes>')
    expect(result).to include('</changes>')
    expect(result).to include('SHIP THE FEATURE')
    expect(result).to include('digest1')
    expect(result).to include('-: removed line')
  end

  it 'derives input variables from a prompt file' do
    Dir.mktmpdir do |dir|
      prompt_file = File.join(dir, 'prompt.txt')
      File.write(prompt_file, "Hello {language} from {source_code}\n")

      config = build_configuration
      config.set_prompt(file: prompt_file)

      result = config.prompt(language: 'ruby',
                             source_code: 'CODE',
                             code_comment_begin: '#',
                             code_comment_end: '',
                             update_context_digests: [],
                             changes_of_contexts: '',
                             goals: '')

      expect(result).to include('Hello ruby from CODE')
    end
  end

  it 'accepts a prompt file without braces and formats it as-is' do
    Dir.mktmpdir do |dir|
      prompt_file = File.join(dir, 'prompt.txt')
      File.write(prompt_file, "Just a plain prompt with no variables\n")

      config = build_configuration
      config.set_prompt(file: prompt_file)

      result = config.prompt(language: 'ruby',
                             source_code: 'SRC',
                             code_comment_begin: '#',
                             code_comment_end: '',
                             update_context_digests: [],
                             changes_of_contexts: '',
                             goals: '')

      expect(result).to include('Just a plain prompt with no variables')
    end
  end

  it 'formats a string prompt with the default input variables' do
    config = build_configuration
    config.set_prompt(
      'Answer in {language} for {source_code} wrapped with {code_comment_begin} and {code_comment_end}'
    )

    result = config.prompt(language: 'ruby',
                           source_code: 'CODE',
                           code_comment_begin: '//',
                           code_comment_end: '')

    expect(result).to include('Answer in ruby for CODE wrapped with // and ')
  end

  it 'raises for an unknown provider' do
    config = build_configuration
    config.set_llm(provider: :nope, api_key: 'k', model: 'm')

    expect { config.llm }.to raise_error(/not implemented provider/)
  end

  it 'raises when the provider is unset' do
    config = build_configuration

    expect { config.llm }.to raise_error(/Please set the provider/)
  end

  it 'raises when no language is assigned anywhere' do
    config = build_configuration

    expect { config.language(nil) }.to raise_error(/assign a language/)
  end
end

describe LLMed::LLM::OpenAI, '#source_code scrubbing (private API via #send)' do
  def build_provider
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: 'dummy',
      default_options: { chat_model: 'm' }
    )
  end

  it 'strips fences and one leading language tag' do
    provider = build_provider
    expect(provider.send(:source_code, "```ruby\nputs 1\n```")).to eq("puts 1\n")
  end

  it 'strips a numbered python language tag' do
    provider = build_provider
    expect(provider.send(:source_code, "```python3\nprint(1)\n```")).to eq("print(1)\n")
  end

  it 'leaves plain code untouched' do
    provider = build_provider
    expect(provider.send(:source_code, "puts 1\n")).to eq("puts 1\n")
  end

  it 'strips an html language tag' do
    provider = build_provider
    expect(provider.send(:source_code, "```html\n<p>x</p>\n```")).to eq("<p>x</p>\n")
  end
end
