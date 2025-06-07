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
      def initialize(**args)
        @llm = Langchain::LLM::OpenAI.new(**args)
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
        llm_response = @llm.chat(messages: messages)
        stop = Time.now
        Response.new({ provider: :openai,
                       model: @llm.chat_parameters[:model],
                       duration_seconds: stop.to_i - start.to_i,
                       source_code: source_code(llm_response.chat_completion),
                       total_tokens: llm_response.total_tokens })
      end

      private

      def source_code(content)
        content.gsub('```', '').sub(/^(node(js)?|javascript|ruby|python(\d*)|elixir|perl|bash|c(pp)?)/, '')
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
