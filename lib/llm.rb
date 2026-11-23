require 'openai'
require 'langchain'
require 'open3'
require 'tempfile'
require 'tmpdir'

Langchain.logger.level = Logger::ERROR

class LLMed
  # Transient, re-sample-fixable failure of a provider response
  # (empty output, invalid syntax, clean transport failure).
  class RetryableError < StandardError; end

  module LLM
    module Message
      System = Struct.new(:content)
      User = Struct.new(:content)
    end

    module Template
      def self.build(template:, input_variables:)
        Langchain::Prompt::PromptTemplate.new(template: template, input_variables: input_variables)
      end
    end

    Response = Struct.new(:provider, :model, :source_code, :duration_seconds, :total_tokens, keyword_init: true)

    module SyntaxCheck
      PYTHON_CHECK_CODE = "import sys; compile(open(sys.argv[1]).read(), 'check', 'exec')".freeze
      CHECKERS = {
        'ruby' => ->(path, _tmpdir) { ['ruby', '-c', path] },
        'node' => ->(path, _tmpdir) { ['node', '--check', path] },
        'javascript' => ->(path, _tmpdir) { ['node', '--check', path] },
        'python' => ->(path, _tmpdir) { ['python3', '-c', PYTHON_CHECK_CODE, path] },
        'python3' => ->(path, _tmpdir) { ['python3', '-c', PYTHON_CHECK_CODE, path] },
        'rust' => ->(path, tmpdir) { ['rustc', '--emit=metadata', '--out-dir', tmpdir, path] },
        'c' => ->(path, _tmpdir) { ['gcc', '-fsyntax-only', path] }
      }.freeze

      module_function

      def validate!(language, source, logger, source_dir: nil)
        lang = language.to_s.downcase
        return validate_java!(source, logger, source_dir: source_dir) if lang == 'java'
        return validate_html!(source, logger) if lang == 'html'

        checker = CHECKERS[language.to_s.downcase]
        unless checker
          logger.warn("syntax checker unavailable for #{language}")
          return true
        end

        Dir.mktmpdir('llmed-syntax-check') do |tmpdir|
          # gcc -fsyntax-only only recognizes *.c inputs; other checkers are extension-agnostic.
          suffix = language.to_s.downcase == 'c' ? '.c' : ''
          Tempfile.create(['llmed-syntax-check', suffix]) do |tmpfile|
            tmpfile.write(source.to_s)
            tmpfile.flush
            stdout, stderr, status = Open3.capture3(*checker.call(tmpfile.path, tmpdir))
            unless status.success?
              output = [stderr, stdout].compact.join.strip
              logger.error("syntax check failed for #{language}: #{output.lines.last(5).join}")
              raise RetryableError, "syntax check failed for #{language}: #{output.lines.first.to_s.strip}"
            end
          end
        end
        true
      rescue Errno::ENOENT, Errno::EACCES => e
        logger.warn("syntax checker unavailable for #{language}: #{e.message}")
        true
      end

      # A top-level PUBLIC java class must live in a file named exactly
      # <ClassName>.java, so a generic temp name makes javac fail for
      # reasons unrelated to the source.
      #
      # Sibling artifacts of one project can reference each other
      # (e.g. app.stuck.StuckCore uses app.stuck.StuckData), so every other
      # *.java of source_dir is copied flat into the tmpdir and passed to
      # javac in the same input set — javac resolves public classes found
      # anywhere in the explicit input files. A file sharing the candidate's
      # class name is excluded so a stale artifact can never shadow the
      # fresh source.
      def validate_java!(source, logger, source_dir: nil)
        class_name = source.to_s[/public\s+class\s+(\w+)/, 1] || 'LlmedSyntaxCheck'
        Dir.mktmpdir('llmed-syntax-check') do |tmpdir|
          tmpfile = File.join(tmpdir, "#{class_name}.java")
          File.write(tmpfile, source.to_s)
          copy_java_siblings!(tmpdir, source_dir, "#{class_name}.java")
          classes_dir = File.join(tmpdir, 'classes')
          FileUtils.mkdir_p(classes_dir)
          stdout, stderr, status = Open3.capture3('javac', '-d', classes_dir, *Dir.glob(File.join(tmpdir, '*.java')).sort)
          unless status.success?
            output = [stderr, stdout].compact.join.strip
            logger.error("syntax check failed for java: #{output.lines.last(5).join}")
            raise RetryableError, "syntax check failed for java: #{output.lines.first.to_s.strip}"
          end
        end
        true
      rescue Errno::ENOENT, Errno::EACCES => e
        logger.warn("syntax checker unavailable for java: #{e.message}")
        true
      end

      # Flat-copy every other *.java of source_dir into tmpdir. Files sharing
      # the candidate's temp-file basename (its class name) are skipped so a
      # stale artifact of the same name can never shadow the candidate.
      # nil, missing dirs or empty dirs copy nothing: standalone behavior.
      def copy_java_siblings!(tmpdir, source_dir, candidate_basename)
        return true if source_dir.nil?
        return true unless File.directory?(source_dir)

        Dir.glob(File.join(source_dir, '*.java')).sort.each do |path|
          basename = File.basename(path)
          next if basename == candidate_basename

          FileUtils.cp(path, File.join(tmpdir, basename))
        end
        true
      end

      # An HTML response is checked without any external binary: a truncated
      # LLM response (missing closing tags, unbalanced script/style blocks)
      # is the common upstream failure mode and must not be cached as a
      # broken artifact.
      def validate_html!(source, logger)
        s = source.to_s
        unless s =~ /<html\b/i
          return html_check_failed!(logger, 'missing <html element')
        end
        unless s.strip =~ %r{</html>\z}i
          return html_check_failed!(logger, 'source does not end with </html>')
        end
        if s.scan(/<script\b/i).length != s.scan(%r{</script\b}i).length
          return html_check_failed!(logger, 'unbalanced <script> tags')
        end
        if s.scan(/<style\b/i).length != s.scan(%r{</style\b}i).length
          return html_check_failed!(logger, 'unbalanced <style> tags')
        end
        true
      end

      def html_check_failed!(logger, reason)
        logger.error("syntax check failed for html: #{reason}")
        raise RetryableError, "syntax check failed for html: #{reason}"
      end
    end

    module SourceCodeScrubbing
      BARE_LANGUAGE_LINE = %w[
        ruby rb python3 python2 python py javascript js jsx typescript ts node nodejs
        bash sh shell zsh html elixir exs golang go cpp c++ c java kotlin rust sql lua perl
      ].join('|').freeze

      def source_code(content)
        content = content.gsub('```', '').sub(/^(node(js)?|javascript|java|ruby|python(\d*)|elixir|bash|html|go|c(pp)?|rust)([ \t]*\n)/, '')
        content.gsub(/^[ \t]*(?:#{BARE_LANGUAGE_LINE})[ \t]*\n/i, '')
               .sub(/(?:\A|(?<=\n))[ \t]*(?:#{BARE_LANGUAGE_LINE})[ \t]*\z/i, '')
      end
    end

    class OpenAI

      DEFAULT_URI_BASE = "https://api.openai.com/".freeze
      MAX_TOKENS = 8192
      # Clean transport failures (connection refused/reset, timeouts, 5xx)
      # are transient and re-samplable; HTTP 4xx (auth, bad request) are not.
      RETRYABLE_TRANSPORT_ERRORS = [
        Faraday::ConnectionFailed,
        Faraday::ServerError
      ].freeze

      include SourceCodeScrubbing
      private :source_code

      def initialize(**args)
        @logger = args.delete(:logger)
        @llm = Langchain::LLM::OpenAI.new(**llm_arguments(args))
      end

      def chat(messages: [])
        messages = messages.map do |m|
          case m
          when Message::System
            { role: 'system', content: m.content }
          when Message::User
            { role: 'user', content: m.content }
          end
        end

        start = Time.now
        begin
          llm_response = @llm.chat(messages: messages, max_tokens: MAX_TOKENS)
        rescue *RETRYABLE_TRANSPORT_ERRORS => e
          @logger.error("provider transport failure: #{e.message}")
          raise RetryableError, "transport failure calling #{provider}: #{e.message}"
        end
        warn_token_limits(llm_response)

        content = llm_response.chat_completion
        if content.nil? || content.to_s.strip.empty?
          @logger.error("provider returned empty response content")
          raise RetryableError, "empty response from #{provider}"
        end

        stop = Time.now
        Response.new({ provider: provider,
                       model: @llm.chat_parameters[:model],
                       duration_seconds: stop.to_i - start.to_i,
                       source_code: source_code(content),
                       total_tokens: llm_response.total_tokens })
      end

      private
      def warn_token_limits(llm_response)
        if llm_response.completion_tokens.to_i >= MAX_TOKENS
          @logger.warn("POSSIBLE INCONSISTENCY COMPLETED TOKENS REACHED MAX TOKENS #{MAX_TOKENS}")
        end
      end

      def llm_arguments(args)
        args
      end

      def provider
        :openai
      end
    end

    class Anthropic < OpenAI
      private

      def llm_arguments(args)
        @logger = args.delete(:logger)
        args.merge({ llm_options: { uri_base: 'https://api.anthropic.com/v1/' } })
      end

      def provider
        :anthropic
      end
    end

    class LikeOpenAI < OpenAI
      private

      def llm_arguments(args)
        args
      end

      def provider
        :like_openai
      end
    end

    # Shared behavior for providers that shell out to a local coding CLI.
    # Subclasses define DEFAULT_BIN, cli_name, provider_name, tmpdir_prefix
    # and build_command(dir), and may override spawn_options(dir).
    class CLIProvider
      include SourceCodeScrubbing
      private :source_code

      DEFAULT_TIMEOUT = 900
      PROMPT_SEPARATOR = "\n\n---\n\n".freeze

      def initialize(**args)
        @logger = args.delete(:logger)
        args.delete(:api_key)
        @model = args.dig(:default_options, :chat_model)
        @llm_options = args.fetch(:llm_options, {}) || {}
        @bin = @llm_options.fetch(:bin, self.class::DEFAULT_BIN)
        @dir = @llm_options[:dir]
        @timeout = @llm_options.fetch(:timeout, DEFAULT_TIMEOUT)
        @flags = @llm_options[:flags]
      end

      def chat(messages: [])
        prompt = messages.map { |m| m[:content] }.join(PROMPT_SEPARATOR)

        if @dir
          chat_response(prompt, @dir)
        else
          Dir.mktmpdir(tmpdir_prefix) { |dir| chat_response(prompt, dir) }
        end
      end

      private

      def chat_response(prompt, dir)
        command = build_command(dir)
        command.concat(@flags) if @flags

        start = Time.now
        stdout, stderr, status = run(command, prompt, dir)
        stop = Time.now

        cleaned = status.success? ? source_code(stdout) : ''
        if !status.success?
          @logger.error("#{cli_name} run failed (exit: #{status.exitstatus}): #{stderr.to_s.lines.last(10).join}")
          raise "#{cli_name} run failed for model #{@model}"
        end
        if cleaned.strip.empty?
          @logger.error("#{cli_name} run failed (exit: success but empty output): #{stderr.to_s.lines.last(10).join}")
          raise RetryableError, "#{cli_name} run failed for model #{@model}"
        end

        Response.new({ provider: provider_name,
                       model: @model,
                       duration_seconds: stop.to_i - start.to_i,
                       source_code: cleaned,
                       total_tokens: nil })
      end

      def run(command, prompt, dir = nil)
        stdin, stdout, stderr, wait_thr = Open3.popen3(*command, spawn_options(dir))

        stdin_thread = prompt_writer(stdin, prompt)
        stdout_thread = stream_reader(stdout)
        stderr_thread = stream_reader(stderr)

        unless wait_thr.join(@timeout)
          kill_child_tree(wait_thr)
          stdin_thread.join
          stdout_thread.join
          stderr_thread.join

          @logger.error("#{cli_name} run timed out after #{@timeout} seconds")
          raise "#{cli_name} run timed out after #{@timeout} seconds"
        end

        stdin_thread.join
        [stdout_thread.value, stderr_thread.value, wait_thr.value]
      end

      def spawn_options(_dir = nil)
        windows? ? { new_pgroup: true } : { pgroup: true }
      end

      def windows?
        RUBY_PLATFORM.match?(/mswin|mingw/)
      end

      def prompt_writer(stdin, prompt)
        Thread.new do
          begin
            stdin.write(prompt)
          rescue StandardError
            nil
          end
          begin
            stdin.close
          rescue StandardError
            nil
          end
        end
      end

      def stream_reader(stream)
        Thread.new do
          begin
            stream.read
          rescue StandardError
            ''
          end
        end
      end

      def kill_child_tree(wait_thr)
        target = windows? ? wait_thr.pid : -wait_thr.pid

        send_signal('TERM', target)
        wait_thr.join(5)
        send_signal('KILL', target) if wait_thr.alive?
        wait_thr.join(5)

        @logger.warn("#{cli_name} timeout kill left pid #{wait_thr.pid} alive") if wait_thr.alive?
      end

      def send_signal(signal, target)
        Process.kill(signal, target)
      rescue Errno::ESRCH, Errno::EPERM => e
        @logger.warn("#{cli_name} timeout kill #{signal} to #{target} failed: #{e.message}")
      end
    end

    class OpenCode < CLIProvider
      DEFAULT_BIN = 'opencode'.freeze

      private

      def cli_name
        'opencode'
      end

      def provider_name
        :opencode
      end

      def tmpdir_prefix
        'llmed-opencode'
      end

      def build_command(dir)
        [@bin, 'run', '-m', @model, '--dir', dir]
      end
    end

    # Claude Code has no --dir flag, so the sandbox is the child's working directory.
    class ClaudeCode < CLIProvider
      DEFAULT_BIN = 'claude'.freeze

      private

      def cli_name
        'claude'
      end

      def provider_name
        :claude
      end

      def tmpdir_prefix
        'llmed-claude'
      end

      def build_command(_dir)
        [@bin, '-p', '--output-format', 'text', '--model', @model]
      end

      def spawn_options(dir = nil)
        dir ? super.merge(chdir: dir) : super
      end
    end

    class Test
      def initialize
        @output = ''
      end

      def chat(messages: [])
        @output = messages.map { |m| m[:content] }.join("\n")

        Response.new({ provider: :test,
                       model: 'test',
                       duration_seconds: 0,
                       source_code: @output,
                       total_tokens: 0 })
      end
    end
  end
end
