require 'open-uri'

class LLMed
  class LiterateProgramming
    def self.execute(llmed, application_name, code, **application_args)
      md = LLMed::LiterateProgramming::Markdown.new()
      contexts = []
      md.parse(code).each do |item|
        context = {}
        case item[:type]
        when :context
          context[:title] = item[:title]
          context[:content] = ''
          item[:content].each do |item_content|
            case item_content[:type]
            when :string
              context[:content] += item_content[:content]
            when :link
              context[:content] += "```#{item_content[:content]}\n#{URI.open(item_content[:reference]).read}\n```"
            end
          end
        end
        contexts << context
      end

      llmed.application(application_name, **application_args) do
        contexts.each do |lcontext|
          context(lcontext[:title]) { lcontext[:content] }
        end
      end
    end
  end
end

require_relative 'literate_programming/markdown'
