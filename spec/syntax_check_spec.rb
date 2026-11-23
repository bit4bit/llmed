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

  describe 'java sibling sources' do
    def stuck_core_source
      <<~JAVA
        package app.stuck;

        public class StuckCore {
          public StuckData data;
        }
      JAVA
    end

    def stuck_data_source
      <<~JAVA
        package app.stuck;

        public class StuckData {
          public int value;
        }
      JAVA
    end

    it 'accepts a java source referencing a sibling class present in source_dir' do
      Dir.mktmpdir('llmed-java-siblings') do |dir|
        File.write(File.join(dir, 'StuckData.java'), stuck_data_source)

        expect(described_class.validate!('java', stuck_core_source, logger, source_dir: dir)).to be(true)
      end
    end

    it 'rejects the same source with source_dir nil' do
      expect {
        described_class.validate!('java', stuck_core_source, logger)
      }.to raise_error(LLMed::RetryableError, /cannot find symbol/)
    end

    it 'accepts a sibling present alongside an unrelated pre-existing java file' do
      Dir.mktmpdir('llmed-java-siblings') do |dir|
        File.write(File.join(dir, 'StuckData.java'), stuck_data_source)
        File.write(File.join(dir, 'Unrelated.java'), <<~JAVA)
          package unrelated;

          public class Unrelated {
          }
        JAVA

        expect(described_class.validate!('java', stuck_core_source, logger, source_dir: dir)).to be(true)
      end
    end
  end

  describe 'CodeComment rust support' do
    it 'uses // line comments for rust' do
      comment = LLMed::Application::CodeComment.new('rust')
      expect(comment.begin).to eq('//')
      expect(comment.end).to eq('')
    end
  end

  describe 'html' do
    def valid_html
      <<~HTML
        <!DOCTYPE html>
        <html>
          <head>
            <title>ok</title>
            <script>var x = 1;</script>
            <style>body { margin: 0; }</style>
          </head>
          <body>hi</body>
        </html>
      HTML
    end

    it 'accepts a complete minimal html page' do
      expect(described_class.validate!('html', valid_html, logger)).to be(true)
    end

    it 'rejects a page with two script opens and one script close' do
      source = valid_html.sub(%r{</script>}, '')
      expect {
        described_class.validate!('html', source, logger)
      }.to raise_error(/syntax check failed for html: /)
    end

    it 'rejects a page truncated mid-file with no closing html' do
      source = valid_html[0, valid_html.length / 2]
      expect {
        described_class.validate!('html', source, logger)
      }.to raise_error(/syntax check failed for html: /)
    end

    it 'rejects an empty string' do
      expect {
        described_class.validate!('html', '', logger)
      }.to raise_error(/syntax check failed for html: /)
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
