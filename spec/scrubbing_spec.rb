# frozen_string_literal: true

require 'llmed'
require 'logger'
require 'stringio'

describe LLMed::LLM::SourceCodeScrubbing, '#source_code' do
  def scrub(content)
    LLMed::LLM::OpenCode.new(logger: Logger.new(StringIO.new), llm_options: {})
                       .send(:source_code, content)
  end

  it 'removes the bare language tag line of a single fenced block' do
    result = scrub("```python\nx = 1\n```")

    expect(result).to eq("x = 1\n")
    lines = result.lines.map(&:strip)
    expect(lines).not_to include('python')
  end

  it 'removes the language tag line of every fence in a multi-block response' do
    result = scrub("```python\na = 1\n```\n```python\nb = 2\n```")

    lines = result.lines.map(&:strip)
    expect(lines).not_to include('python')
    expect(result).to include('a = 1')
    expect(result).to include('b = 2')
  end

  it 'leaves plain source code untouched' do
    expect(scrub("puts 1\n")).to eq("puts 1\n")
    expect(scrub("// ok\n")).to eq("// ok\n")
    expect(scrub('x = 5')).to eq('x = 5')
  end

  it 'keeps real code lines that merely start with a language identifier' do
    expect(scrub("python = 3\n")).to eq("python = 3\n")
    expect(scrub("ruby -e 'puts 1'\n")).to eq("ruby -e 'puts 1'\n")
  end

  it 'deletes the bare python line between marker lines (regression)' do
    result = scrub("#</llmed-code>\n\n\npython\n#<llmed-code")

    lines = result.lines.map(&:strip)
    expect(lines).not_to include('python')
    expect(result).to include('#</llmed-code>')
    expect(result).to include('#<llmed-code')
  end

  it 'keeps the OpenAI leading-tag example behavior' do
    result = scrub("```ruby\nputs 'hola mundo'\n```")

    expect(result).to include("puts 'hola mundo'")
    expect(result).not_to include('`')
    lines = result.lines.map(&:strip)
    expect(lines).not_to include('ruby')
  end
end
