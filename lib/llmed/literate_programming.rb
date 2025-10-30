require 'open-uri'

class LLMed
  class LiterateProgramming
    def self.execute(code, **application_args)
      md = LLMed::LiterateProgramming::Markdown.new()
      contexts = []
      environment = {}

      md.parse(code).each do |item|
        context = {}

        if item[:title] == "_default"
          item[:content].each do |item_content|
            case item_content[:type]
            when :environment
              name = item_content[:name].strip.to_sym
              value = item_content[:value].strip
              if [:language, :release, :output_file, :output_dir, :release_dir].include?(name) && !value.empty?
                application_args[name] = value
              else
                environment[name] = value
              end
            end
          end
          next
        end

        case item[:type]
        when :context
          context[:title] = item[:title]
          context[:content] = ''

          item[:content].each do |item_content|
            case item_content[:type]
            when :comment
              next
            when :string
              context[:content] += item_content[:content]
            when :link
              context[:content] += "#{URI.open(item_content[:reference]).read}\n"
            end
          end
        contexts << context
        end
      end

      yield contexts, application_args, environment
    end
  end
end

require_relative 'literate_programming/markdown'
