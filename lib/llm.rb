require 'openai'
require 'langchain'
require 'open3'

Langchain.logger.level = Logger::ERROR

class LLMed
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

    module SourceCodeScrubbing
      def source_code(content)
        content.gsub('```', '').sub(/^(node(js)?|javascript|ruby|python(\d*)|elixir|bash|html|go|c(pp)?)([ \n])/, '')
      end
    end

    class OpenAI

      DEFAULT_URI_BASE = "https://api.openai.com/".freeze
      MAX_TOKENS = 8192

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
        llm_response = @llm.chat(messages: messages, max_tokens: MAX_TOKENS)
        warn_token_limits(llm_response)

        stop = Time.now
        Response.new({ provider: provider,
                       model: @llm.chat_parameters[:model],
                       duration_seconds: stop.to_i - start.to_i,
                       source_code: source_code(llm_response.chat_completion),
                       total_tokens: llm_response.total_tokens })
      end

      private
      def warn_token_limits(llm_response)
        if llm_response.completion_tokens >= MAX_TOKENS
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

    class OpenCode
      include SourceCodeScrubbing
      private :source_code

      DEFAULT_BIN = 'opencode'.freeze
      DEFAULT_TIMEOUT = 900
      PROMPT_SEPARATOR = "\n\n---\n\n".freeze

      def initialize(**args)
        @logger = args.delete(:logger)
        args.delete(:api_key)
        @model = args.dig(:default_options, :chat_model)
        @llm_options = args.fetch(:llm_options, {}) || {}
        @bin = @llm_options.fetch(:bin, DEFAULT_BIN)
        @dir = @llm_options[:dir]
        @timeout = @llm_options.fetch(:timeout, DEFAULT_TIMEOUT)
        @flags = @llm_options[:flags]
      end

      def chat(messages: [])
        prompt = messages.map { |m| m[:content] }.join(PROMPT_SEPARATOR)

        command = [@bin, 'run', '-m', @model]
        command.concat(['--dir', @dir]) if @dir
        command.concat(@flags) if @flags

        start = Time.now
        stdout, stderr, status = run(command, prompt)
        stop = Time.now

        cleaned = status.success? ? source_code(stdout) : ''
        if !status.success? || cleaned.strip.empty?
          @logger.error("opencode run failed (exit: #{status.success? ? 'success but empty output' : status.exitstatus}): #{stderr.to_s.lines.last(10).join}")
          raise "opencode run failed for model #{@model}"
        end

        Response.new({ provider: :opencode,
                       model: @model,
                       duration_seconds: stop.to_i - start.to_i,
                       source_code: cleaned,
                       total_tokens: nil })
      end

      private

      def run(command, prompt)
        stdin, stdout, stderr, wait_thr = Open3.popen3(*command, spawn_options)

        stdin_thread = prompt_writer(stdin, prompt)
        stdout_thread = stream_reader(stdout)
        stderr_thread = stream_reader(stderr)

        unless wait_thr.join(@timeout)
          kill_child_tree(wait_thr)
          stdin_thread.join
          stdout_thread.join
          stderr_thread.join

          @logger.error("opencode run timed out after #{@timeout} seconds")
          raise "opencode run timed out after #{@timeout} seconds"
        end

        stdin_thread.join
        [stdout_thread.value, stderr_thread.value, wait_thr.value]
      end

      def spawn_options
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

        @logger.warn("opencode timeout kill left pid #{wait_thr.pid} alive") if wait_thr.alive?
      end

      def send_signal(signal, target)
        Process.kill(signal, target)
      rescue Errno::ESRCH, Errno::EPERM => e
        @logger.warn("opencode timeout kill #{signal} to #{target} failed: #{e.message}")
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
