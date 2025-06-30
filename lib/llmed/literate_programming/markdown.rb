#<llmed-code context='Library LLMed::LiterateProgramming::Markdown' digest='9c0e3f61ab4cdc3c56c29230a800487dd1a7ef0d929c843fd2461907d0831ab2' after=''>
class LLMed::LiterateProgramming::Markdown
  def parse(input)
    contexts = []
    current_context = { type: :context, title: "_default", content: [] }
    
    input.each_line do |line|
      if line.strip =~ /^# (.+)$/
        contexts << current_context unless current_context[:content].empty?
        current_context = { type: :context, title: Regexp.last_match(1), content: [] }
      elsif line.strip =~ /^\[(.+)\]\((.+)\)$/
        current_context[:content] << { type: :link, content: Regexp.last_match(1), reference: Regexp.last_match(2) }
      elsif line.strip =~ /^#% (.+)$/
        current_context[:content] << { type: :comment, content: Regexp.last_match(1) + "\n" }
      elsif line.strip =~ /^#!environment\s+(\w+)\s+(.+)$/
        current_context[:content] << { type: :environment, name: Regexp.last_match(1), value: Regexp.last_match(2) }
      else
        current_context[:content] << { type: :string, content: line }
      end
    end

    contexts << current_context unless current_context[:content].empty?
    contexts
  end
end
#</llmed-code>