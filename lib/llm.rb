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

    class Response
      def initialize(response, tokens)
        @response = response
        @tokens = tokens
      end

      def source_code
        @response
      end

      def total_tokens
        @tokens
      end
    end

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

        llm_response = @llm.chat(messages: messages)
        Response.new(llm_response.chat_completion, llm_response.total_tokens)
      end
    end

    class Test
      def initialize
        @output = ''
      end

      def chat(messages: [])
        @output = messages.map { |m| m[:content] }.join("\n")

        Response.new(@output, 0)
      end
    end
  end
end
