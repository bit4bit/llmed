# frozen_string_literal: true

require 'llmed'
require 'logger'
require 'stringio'

describe LLMed::LLM::OpenAI, '#chat max_tokens cap' do
  def build_provider(llm_options: {})
    LLMed::LLM::OpenAI.new(
      logger: logger,
      api_key: 'k',
      default_options: { max_tokens: nil, temperature: 0.7, chat_model: 'm' },
      llm_options: llm_options
    )
  end

  def logger
    @log_stream ||= StringIO.new
    @logger ||= Logger.new(@log_stream)
  end

  def logged_output
    @log_stream.string
  end

  def stub_chat(provider)
    llm = provider.instance_variable_get(:@llm)
    calls = []
    allow(llm).to receive(:chat) do |**kwargs|
      calls << kwargs
      double(chat_completion: "```ruby\nputs 'hola mundo'\n```",
             completion_tokens: 10,
             total_tokens: 20)
    end
    calls
  end

  it 'defaults to 8192' do
    provider = build_provider
    calls = stub_chat(provider)
    provider.chat(messages: [LLMed::LLM::Message::User.new('user prompt')])

    expect(calls.first[:max_tokens]).to eq(8192)
  end

  it 'honors llm_options: { max_tokens: N }' do
    provider = build_provider(llm_options: { max_tokens: 32768 })
    calls = stub_chat(provider)
    provider.chat(messages: [LLMed::LLM::Message::User.new('user prompt')])

    expect(calls.first[:max_tokens]).to eq(32768)
  end

  it 'falls back to the default with a warning on an invalid max_tokens' do
    provider = build_provider(llm_options: { max_tokens: 'bogus' })
    calls = stub_chat(provider)
    provider.chat(messages: [LLMed::LLM::Message::User.new('user prompt')])

    expect(calls.first[:max_tokens]).to eq(8192)
    expect(logged_output).to include('invalid max_tokens option ignored: bogus')
  end

  it 'compares completion tokens against the effective cap' do
    provider = build_provider(llm_options: { max_tokens: 100 })
    llm = provider.instance_variable_get(:@llm)
    calls = []
    allow(llm).to receive(:chat) do |**kwargs|
      calls << kwargs
      double(chat_completion: "```ruby\nputs 'hola mundo'\n```",
             completion_tokens: 100,
             total_tokens: 120)
    end
    provider.chat(messages: [LLMed::LLM::Message::User.new('user prompt')])

    expect(calls.first[:max_tokens]).to eq(100)
    expect(logged_output).to include('COMPLETED TOKENS REACHED MAX TOKENS 100')
  end
end
