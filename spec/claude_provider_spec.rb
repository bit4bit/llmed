# frozen_string_literal: true

require 'llmed'
require 'open3'
require 'logger'
require 'stringio'

describe LLMed::Configuration, '#llm with :claude provider' do
  it 'returns an LLMed::LLM::ClaudeCode' do
    config = LLMed::Configuration.new(logger: Logger.new(StringIO.new))
    config.set_llm(provider: :claude, api_key: 'k', model: 'm')

    expect(config.llm).to be_a(LLMed::LLM::ClaudeCode)
  end
end

describe LLMed::LLM::ClaudeCode, '#chat' do
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

    expect(response.provider).to eq(:claude)
    expect(response.model).to eq('m')
    expect(response.source_code).to include("puts 'hola mundo'")
    expect(response.source_code).not_to include('`')
  end

  it 'raises when the claude run fails' do
    allow(Open3).to receive(:popen3).and_return(
      [double(write: nil, close: nil),
       double(read: ''),
       double(read: 'boom'),
       double(join: true, value: double(success?: false, exitstatus: 1))]
    )

    expect { build_provider.chat(messages: [{ role: 'user', content: 'user prompt' }]) }.to raise_error(RuntimeError)
  end

  it 'raises a RetryableError when the claude run succeeds with empty output' do
    allow(Open3).to receive(:popen3).and_return(
      [double(write: nil, close: nil),
       double(read: ''),
       double(read: ''),
       double(join: true, value: double(success?: true, exitstatus: 0))]
    )

    expect { build_provider.chat(messages: [{ role: 'user', content: 'user prompt' }]) }
      .to raise_error(LLMed::RetryableError)
  end
end

describe LLMed::LLM::ClaudeCode, '#run' do
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

describe LLMed::LLM::ClaudeCode, '#chat end-to-end' do
  def build_provider(llm_options: {})
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: llm_options
    )
  end

  it 'builds the command and returns a response from the real subprocess' do
    response = build_provider(llm_options: { bin: '/bin/echo', flags: ['--verbose'] })
                 .chat(messages: [{ role: 'user', content: 'ignored' }])

    expect(response.provider).to eq(:claude)
    expect(response.model).to eq('m')
    expect(response.source_code).to include('-p --output-format text --model m --verbose')
  end
end

describe LLMed::LLM::ClaudeCode, '#chat sandbox dir' do
  def build_provider(llm_options: {})
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: llm_options
    )
  end

  # Records each popen3 call as [command_args, spawn_options] and a snapshot of
  # the working directory's children at call time.
  def stub_claude_run
    calls = []
    dir_snapshots = []
    allow(Open3).to receive(:popen3) do |*args|
      opts = args.last.is_a?(Hash) ? args.pop : {}
      dir = opts[:chdir]
      dir_snapshots << (dir && File.directory?(dir) ? Dir.children(dir).sort : nil)
      calls << [args, opts]
      [double(write: nil, close: nil),
       double(read: "```ruby\nputs 'hi'\n```"),
       double(read: ''),
       double(join: true, value: double(success?: true, exitstatus: 0))]
    end
    [calls, dir_snapshots]
  end

  it 'runs claude non-interactively with the model and no --dir flag' do
    calls, = stub_claude_run
    build_provider.chat(messages: [{ role: 'user', content: 'p' }])

    expect(calls.first.first).to eq(['claude', '-p', '--output-format', 'text', '--model', 'm'])
  end

  it 'runs inside a fresh empty temp dir when no :dir is provided' do
    calls, dir_snapshots = stub_claude_run
    build_provider.chat(messages: [{ role: 'user', content: 'p' }])

    dir = calls.first.last[:chdir]
    expect(dir).to start_with(Dir.tmpdir)
    expect(File.basename(dir)).to start_with('llmed-claude')
    expect(dir_snapshots.first).to eq([])
  end

  it 'uses a different fresh dir for every chat call' do
    calls, = stub_claude_run
    provider = build_provider
    provider.chat(messages: [{ role: 'user', content: 'p' }])
    provider.chat(messages: [{ role: 'user', content: 'p' }])

    expect(calls[0].last[:chdir]).to start_with(Dir.tmpdir)
    expect(calls[1].last[:chdir]).to start_with(Dir.tmpdir)
    expect(calls[0].last[:chdir]).not_to eq(calls[1].last[:chdir])
  end

  it 'keeps an explicit :dir sandbox and creates no temp dir' do
    expect(Dir).not_to receive(:mktmpdir)
    calls, = stub_claude_run
    build_provider(llm_options: { dir: '/my/sandbox' })
      .chat(messages: [{ role: 'user', content: 'p' }])

    expect(calls.first.last[:chdir]).to eq('/my/sandbox')
  end

  it 'removes the fresh temp dir after chat returns' do
    calls, = stub_claude_run
    build_provider.chat(messages: [{ role: 'user', content: 'p' }])

    expect(File.exist?(calls.first.last[:chdir])).to be(false)
  end
end
