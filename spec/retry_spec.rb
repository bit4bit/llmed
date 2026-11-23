# frozen_string_literal: true

require 'llmed'
require 'support/notify_neutralizer'
require 'open3'
require 'faraday'
require 'logger'
require 'stringio'

describe LLMed::RetryableError do
  it 'is a StandardError' do
    expect(described_class).to be < StandardError
  end
end

describe LLMed::LLM::SyntaxCheck, '#validate!' do
  it 'raises a RetryableError for invalid source' do
    expect {
      LLMed::LLM::SyntaxCheck.validate!('ruby', "def\n", Logger.new(StringIO.new))
    }.to raise_error(LLMed::RetryableError, /syntax check failed for ruby/)
  end
end

describe LLMed::LLM::OpenCode, '#chat transient mapping' do
  def build_provider(log = StringIO.new)
    described_class.new(
      logger: Logger.new(log),
      api_key: nil,
      default_options: { chat_model: 'm' },
      llm_options: {}
    )
  end

  def stub_run(stdout: '', stderr: '', success: true, stdout_read_error: nil)
    stdout_stream = double
    if stdout_read_error
      allow(stdout_stream).to receive(:read).and_raise(stdout_read_error)
    else
      allow(stdout_stream).to receive(:read).and_return(stdout)
    end
    allow(Open3).to receive(:popen3).and_return(
      [double(write: nil, close: nil),
       stdout_stream,
       double(read: stderr),
       double(join: true, value: double(success?: success, exitstatus: success ? 0 : 1))]
    )
  end

  it 'raises RAW-EMPTY when the model printed nothing on a success exit' do
    stub_run(stdout: '')

    expect { build_provider.chat(messages: [{ role: 'user', content: 'p' }]) }
      .to raise_error(LLMed::RetryableError,
                      'opencode run failed (RAW-EMPTY: model printed nothing, raw 0 bytes)')
  end

  it 'raises SCRUBBED-EMPTY with the byte count when fence markers scrub to nothing' do
    log = StringIO.new
    body = "```ruby\n```"
    stub_run(stdout: body)

    expect { build_provider(log).chat(messages: [{ role: 'user', content: 'p' }]) }
      .to raise_error(LLMed::RetryableError,
                      "opencode run failed (SCRUBBED-EMPTY: raw #{body.bytesize} bytes reduced to nothing by source_code extraction)")

    expect(log.string).to include("opencode empty-output raw head: #{body.byteslice(0, 200)}")
  end

  it 'keeps the caller alive when reading stdout raises, logging the read failure' do
    log = StringIO.new
    stub_run(stdout_read_error: StandardError.new('pipe exploded'))

    expect { build_provider(log).chat(messages: [{ role: 'user', content: 'p' }]) }
      .to raise_error(LLMed::RetryableError,
                      'opencode run failed (RAW-EMPTY: model printed nothing, raw 0 bytes)')

    expect(log.string).to include('stdout read failure: pipe exploded')
  end

  it 'keeps a nonzero exit non-retryable' do
    stub_run(stderr: 'auth boom', success: false)

    expect { build_provider.chat(messages: [{ role: 'user', content: 'p' }]) }
      .to raise_error(an_instance_of(RuntimeError)) { |e|
        expect(e.class).not_to be(LLMed::RetryableError)
      }
  end
end

describe LLMed::LLM::OpenAI, '#chat transient mapping' do
  def build_provider
    described_class.new(
      logger: Logger.new(StringIO.new),
      api_key: 'dummy',
      default_options: { chat_model: 'm' }
    )
  end

  def stub_langchain_chat(provider)
    langchain_llm = provider.instance_variable_get(:@llm)
    yield langchain_llm
  end

  it 'raises a RetryableError when the response content is empty' do
    provider = build_provider
    stub_langchain_chat(provider) do |langchain_llm|
      allow(langchain_llm).to receive(:chat).and_return(
        double(chat_completion: nil, completion_tokens: 0, total_tokens: 0)
      )
    end

    expect { provider.chat(messages: [LLMed::LLM::Message::User.new('p')]) }
      .to raise_error(LLMed::RetryableError, /empty response/)
  end

  it 'raises a RetryableError on a clean transport failure' do
    provider = build_provider
    stub_langchain_chat(provider) do |langchain_llm|
      allow(langchain_llm).to receive(:chat).and_raise(Faraday::ConnectionFailed.new('connection refused'))
    end

    expect { provider.chat(messages: [LLMed::LLM::Message::User.new('p')]) }
      .to raise_error(LLMed::RetryableError, /transport failure/)
  end

  it 'keeps auth failures non-retryable' do
    provider = build_provider
    stub_langchain_chat(provider) do |langchain_llm|
      allow(langchain_llm).to receive(:chat).and_raise(Faraday::UnauthorizedError.new('401'))
    end

    expect { provider.chat(messages: [LLMed::LLM::Message::User.new('p')]) }
      .to raise_error(an_instance_of(Faraday::UnauthorizedError)) { |e|
        expect(e.class).not_to be(LLMed::RetryableError)
      }
  end
end

describe LLMed::Configuration, '#llm_retries' do
  def build_configuration
    described_class.new(logger: Logger.new(StringIO.new))
  end

  it 'defaults to 2 retries' do
    config = build_configuration
    config.set_llm(provider: :opencode, api_key: nil, model: 'm')

    expect(config.llm_retries).to eq(2)
  end

  it 'reads retries from the stored set_llm options' do
    config = build_configuration
    config.set_llm(provider: :opencode, api_key: nil, model: 'm', options: { retries: 0 })

    expect(config.provider_options).to include(retries: 0)
    expect(config.llm_retries).to eq(0)
  end

  it 'gives the doc directive precedence over set_llm options' do
    config = build_configuration
    config.set_llm(provider: :opencode, api_key: nil, model: 'm', options: { retries: 0 })
    config.set_llm_provider_retries('1')

    expect(config.llm_retries).to eq(1)
  end

  it 'keeps the directive precedence regardless of set order' do
    config = build_configuration
    config.set_llm_provider_retries(1)
    config.set_llm(provider: :opencode, api_key: nil, model: 'm', options: { retries: 0 })

    expect(config.llm_retries).to eq(1)
  end
end

describe LLMed, 'compile_application retry of invalid model responses' do
  def build_llmed(log = StringIO.new)
    llmed = described_class.new(logger: Logger.new(log), output_dir: '/tmp', release_dir: '/tmp')
    llmed.set_language 'ruby'
    llmed.set_llm(provider: :opencode, api_key: nil, model: 'm')
    [llmed, log]
  end

  def stub_runs(responses)
    invocations = []
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args, &block|
      if args.include?('--dir')
        body = responses[invocations.length] || responses.last
        invocations << body
        [double(write: nil, close: nil),
         double(read: body),
         double(read: ''),
         double(join: true, value: double(success?: true, exitstatus: 0))]
      else
        original.call(*args, &block)
      end
    end
    invocations
  end

  def stub_nonzero_exit
    invocations = []
    allow(Open3).to receive(:popen3).and_wrap_original do |original, *args, &block|
      if args.include?('--dir')
        invocations << args
        [double(write: nil, close: nil),
         double(read: ''),
         double(read: 'auth boom'),
         double(join: true, value: double(success?: false, exitstatus: 1))]
      else
        original.call(*args, &block)
      end
    end
    invocations
  end

  def run_application(llmed, output)
    llmed.application('demo', output_file: output) do
      context('main') { "Show to the user 'hola mundo'" }
    end
    llmed.compile
  end

  it 'retries after an empty response and writes the artifact' do
    llmed, log = build_llmed
    invocations = stub_runs(['', "```ruby\nputs 'hola mundo'\n```"])
    output = StringIO.new

    run_application(llmed, output)

    expect(output.string).to include("puts 'hola mundo'")
    expect(invocations.length).to eq(2)
    expect(log.string.scan(/APPLICATION demo RETRY \d+\/\d+ after: opencode run failed \(RAW-EMPTY: model printed nothing, raw 0 bytes\)/))
      .to eq(['APPLICATION demo RETRY 1/3 after: opencode run failed (RAW-EMPTY: model printed nothing, raw 0 bytes)'])
  end

  it 'retries after an invalid syntax response and writes the artifact' do
    llmed, = build_llmed
    invocations = stub_runs(["def\n", "```ruby\nputs 'hola mundo'\n```"])
    output = StringIO.new

    run_application(llmed, output)

    expect(output.string).to include("puts 'hola mundo'")
    expect(invocations.length).to eq(2)
  end

  it 're-raises the last retryable error after exhausting the default retries' do
    llmed, log = build_llmed
    invocations = stub_runs([''])
    output = StringIO.new

    expect { run_application(llmed, output) }
      .to raise_error(LLMed::RetryableError, /opencode run failed/)

    expect(invocations.length).to eq(3)
    expect(log.string.scan(/APPLICATION demo RETRY \d+\/\d+/))
      .to eq(['APPLICATION demo RETRY 1/3', 'APPLICATION demo RETRY 2/3'])
  end

  it 'raises immediately when set_llm options configure retries: 0' do
    llmed, log = build_llmed
    llmed.set_llm(provider: :opencode, api_key: nil, model: 'm', options: { retries: 0 })
    invocations = stub_runs([''])
    output = StringIO.new

    expect { run_application(llmed, output) }
      .to raise_error(LLMed::RetryableError, /opencode run failed/)

    expect(invocations.length).to eq(1)
    expect(log.string).not_to match(/RETRY/)
  end

  it 'applies the doc directive llm_provider_retries' do
    llmed, log = build_llmed
    invocations = stub_runs([''])
    output = StringIO.new

    LLMed::LiterateProgramming.execute("#!environment llm_provider_retries 1\n\n# Main\n\nShow hi.\n", output_file: output) do |contexts, application_args, environment|
      retries = environment[:llm_provider_retries]
      llmed.set_llm_provider_retries(retries) if retries
      llmed.application('literate_programming', **application_args) do
        contexts.each do |lcontext|
          context(lcontext[:title]) { lcontext[:content] }
        end
      end
    end

    expect { llmed.compile }.to raise_error(LLMed::RetryableError, /opencode run failed/)

    expect(invocations.length).to eq(2)
    expect(log.string.scan(/APPLICATION literate_programming RETRY \d+\/\d+/))
      .to eq(['APPLICATION literate_programming RETRY 1/2'])
  end

  it 'gives the doc directive precedence over set_llm options' do
    llmed, = build_llmed
    llmed.set_llm(provider: :opencode, api_key: nil, model: 'm', options: { retries: 0 })
    invocations = stub_runs([''])
    output = StringIO.new

    LLMed::LiterateProgramming.execute("#!environment llm_provider_retries 1\n\n# Main\n\nShow hi.\n", output_file: output) do |contexts, application_args, environment|
      retries = environment[:llm_provider_retries]
      llmed.set_llm_provider_retries(retries) if retries
      llmed.application('literate_programming', **application_args) do
        contexts.each do |lcontext|
          context(lcontext[:title]) { lcontext[:content] }
        end
      end
    end

    expect { llmed.compile }.to raise_error(LLMed::RetryableError, /opencode run failed/)

    expect(invocations.length).to eq(2)
  end

  it 'does not retry a non-retryable failure' do
    llmed, log = build_llmed
    invocations = stub_nonzero_exit
    output = StringIO.new

    expect { run_application(llmed, output) }.to raise_error(RuntimeError)

    expect(invocations.length).to eq(1)
    expect(log.string).not_to match(/RETRY/)
  end

  it 'does not validate or retry the :test provider' do
    llmed, log = build_llmed
    llmed.set_llm(provider: :test, api_key: '', model: '')
    output = StringIO.new

    llmed.application('demo', output_file: output) do
      context('main') { "def\n" }
    end
    llmed.compile

    expect(output.string).to include('def')
    expect(log.string).not_to match(/RETRY/)
  end
end
