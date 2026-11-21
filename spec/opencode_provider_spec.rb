# frozen_string_literal: true

require 'llmed'
require 'open3'
require 'logger'
require 'stringio'

describe LLMed::Configuration, '#llm with :opencode provider' do
  it 'returns an LLMed::LLM::OpenCode' do
    config = LLMed::Configuration.new(logger: Logger.new(StringIO.new))
    config.set_llm(provider: :opencode, api_key: 'k', model: 'm')

    expect(config.llm).to be_a(LLMed::LLM::OpenCode)
  end
end

describe LLMed::LLM::OpenCode, '#chat' do
  def build_provider
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: {}
    )
  end

  it 'returns the cleaned source code' do
    allow(Open3).to receive(:capture3).and_return(["```ruby\nputs 'hola mundo'\n```", '', double(success?: true, exitstatus: 0)])
    response = build_provider.chat(messages: [{ role: 'system', content: 'system prompt' }, { role: 'user', content: 'user prompt' }])

    expect(response.provider).to eq(:opencode)
    expect(response.model).to eq('m')
    expect(response.source_code).to include("puts 'hola mundo'")
    expect(response.source_code).not_to include('`')
  end

  it 'raises when the opencode run fails' do
    allow(Open3).to receive(:capture3).and_return(['', 'boom', double(success?: false, exitstatus: 1)])

    expect { build_provider.chat(messages: [{ role: 'user', content: 'user prompt' }]) }.to raise_error(RuntimeError)
  end
end
