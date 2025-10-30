require 'openai'
require 'langchain'

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

    class OpenAI

      DEFAULT_URI_BASE = "https://api.openai.com/".freeze
      MAX_TOKENS = 8192

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

      def source_code(content)
        content.gsub('```', '').sub(/^(node(js)?|javascript|ruby|python(\d*)|elixir|bash|html|go|c(pp)?)([ \n])/, '')
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
