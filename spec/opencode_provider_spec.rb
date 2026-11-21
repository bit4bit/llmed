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
    allow(Open3).to receive(:popen3).and_return(
      [double(write: nil, close: nil),
       double(read: "```ruby\nputs 'hola mundo'\n```"),
       double(read: ''),
       double(join: true, value: double(success?: true, exitstatus: 0))]
    )
    response = build_provider.chat(messages: [{ role: 'system', content: 'system prompt' }, { role: 'user', content: 'user prompt' }])

    expect(response.provider).to eq(:opencode)
    expect(response.model).to eq('m')
    expect(response.source_code).to include("puts 'hola mundo'")
    expect(response.source_code).not_to include('`')
  end

  it 'raises when the opencode run fails' do
    allow(Open3).to receive(:popen3).and_return(
      [double(write: nil, close: nil),
       double(read: ''),
       double(read: 'boom'),
       double(join: true, value: double(success?: false, exitstatus: 1))]
    )

    expect { build_provider.chat(messages: [{ role: 'user', content: 'user prompt' }]) }.to raise_error(RuntimeError)
  end
end

describe LLMed::LLM::OpenCode, '#run' do
  def build_provider(llm_options: {})
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: llm_options
    )
  end

  it 'returns stdout, stderr and status on success' do
    stdout, stderr, status = build_provider.send(:run, ['ruby', '-e', 'print "ping"'], 'ignored')

    expect(stdout).to include('ping')
    expect(stderr).to eq('')
    expect(status.success?).to eq(true)
  end

  it 'delivers the prompt via stdin' do
    stdout, _stderr, status = build_provider.send(:run, ['ruby', '-e', 'print $stdin.read.upcase'], 'ping')

    expect(stdout).to eq('PING')
    expect(status.success?).to eq(true)
  end

  it 'raises and kills the child when the run times out' do
    provider = build_provider(llm_options: { timeout: 1 })

    expect { provider.send(:run, ['ruby', '-e', 'sleep 30'], 'ignored') }
      .to raise_error(RuntimeError, /timed out after 1 seconds/)
  end
end

describe LLMed::LLM::OpenCode, '#chat end-to-end' do
  def build_provider(llm_options: {})
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: llm_options
    )
  end

  it 'builds the command and returns a response from the real subprocess' do
    response = build_provider(llm_options: { bin: '/bin/echo', flags: ['run'] })
                 .chat(messages: [{ role: 'user', content: 'ignored' }])

    expect(response.provider).to eq(:opencode)
    expect(response.model).to eq('m')
    expect(response.source_code).to include('run -m m')
  end
end
