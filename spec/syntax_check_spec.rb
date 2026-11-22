# frozen_string_literal: true

require 'llmed'
require 'logger'
require 'stringio'

describe LLMed::LLM::SyntaxCheck, '#validate!' do
  def logger
    @io ||= StringIO.new
    @logger ||= Logger.new(@io)
  end

  def messages
    @io.string
  end

  it 'accepts valid ruby source' do
    expect(described_class.validate!('ruby', "puts 1\n", logger)).to be(true)
  end

  it 'rejects invalid ruby source' do
    expect {
      described_class.validate!('ruby', "def\n", logger)
    }.to raise_error(/syntax check failed for ruby/)
  end

  it 'accepts valid node source' do
    expect(described_class.validate!('node', "console.log(1)\n", logger)).to be(true)
  end

  it 'rejects invalid node source' do
    expect {
      described_class.validate!('node', "function {\n", logger)
    }.to raise_error(/syntax check failed for node/)
  end

  it 'accepts javascript as node source' do
    expect(described_class.validate!('javascript', "console.log(1)\n", logger)).to be(true)
  end

  it 'rejects invalid javascript source' do
    expect {
      described_class.validate!('javascript', "function {\n", logger)
    }.to raise_error(/syntax check failed for javascript/)
  end

  it 'accepts valid python source' do
    expect(described_class.validate!('python', "x = 1\n", logger)).to be(true)
  end

  it 'rejects invalid python source' do
    expect {
      described_class.validate!('python', "def(:\n", logger)
    }.to raise_error(/syntax check failed for python/)
  end

  it 'accepts python3 as python source' do
    expect(described_class.validate!('python3', "x = 1\n", logger)).to be(true)
  end

  it 'accepts valid rust source' do
    expect(described_class.validate!('rust', "fn main() {}\n", logger)).to be(true)
  end

  it 'rejects invalid rust source' do
    expect {
      described_class.validate!('rust', "fn main() {\n", logger)
    }.to raise_error(/syntax check failed for rust/)
  end

  it 'accepts valid c source' do
    expect(described_class.validate!('c', "int main(void) { return 0; }\n", logger)).to be(true)
  end

  it 'rejects invalid c source' do
    expect {
      described_class.validate!('c', "int main( {\n", logger)
    }.to raise_error(/syntax check failed for c/)
  end

  describe 'CodeComment java support' do
    it 'uses // line comments for java' do
      comment = LLMed::Application::CodeComment.new('java')
      expect(comment.begin).to eq('//')
      expect(comment.end).to eq('')
    end
  end

  it 'accepts valid java source with a public class name' do
    source = <<~JAVA
      public class MiniRogue {
        public static void main(String[] args) {
          System.out.println("ok");
        }
      }
    JAVA
    expect(described_class.validate!('java', source, logger)).to be(true)
  end

  it 'rejects invalid java source' do
    expect {
      described_class.validate!('java', "public class MiniRogue {\n", logger)
    }.to raise_error(/syntax check failed for java/)
  end

  describe 'CodeComment rust support' do
    it 'uses // line comments for rust' do
      comment = LLMed::Application::CodeComment.new('rust')
      expect(comment.begin).to eq('//')
      expect(comment.end).to eq('')
    end
  end

  it 'skips unknown languages returning true' do
    expect(described_class.validate!('cobol', "DISPLAY 'HI'.\n", logger)).to be(true)
    expect(messages).to include('syntax checker unavailable for cobol')
  end

  it 'skips when the checker binary is missing' do
    allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

    expect(described_class.validate!('ruby', "puts 1\n", logger)).to be(true)
    expect(messages).to match(/syntax checker unavailable for ruby/)
  end
end
