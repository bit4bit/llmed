#<llmed-code context='Library LLMed::LiterateProgramming::Markdown' digest='18aa5391a8a334f24a80542620a277bb9c085762cb88b7dbcafa26a532a48027' after=''>
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
      else
        current_context[:content] << { type: :string, content: line }
      end
    end

    contexts << current_context unless current_context[:content].empty?
    contexts
  end
end
#</llmed-code>