# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Release
    ContextCode = Struct.new(:name, :digest, :code) do
      def digest?
        return false if @digest.nil?

        false if @digest.empty?
      end
    end

    def self.load(origin)
      new(origin)
    end

    def self.empty
      new('')
    end

    attr_reader :content

    def empty?
      @origin.empty?
    end

    def contexts
      # list, order is important
      contexts = []
      @origin.scan(%r{<llmed-code context='(.+?)' digest='(.+?)'>(.+?)</llmed-code>}im).each do |match|
        name, digest, code = match
        contexts << ContextCode.new(name, digest, code)
      end

      contexts
    end

    def changes
      changes = @changes.dup
      @changes.clear
      changes
    end

    def context_by(name)
      contexts.each do |ctx|
        return ctx if ctx.name == name
      end

      ContextCode.new('', '', '')
    end

    def has_context?(name)
      contexts.each do |ctx|
        return true if ctx.name == name
      end
      false
    end

    def merge!(release, code_comment)
      content = @origin.dup

      release.contexts.each do |ctx|
        if has_context?(ctx.name)
          content = content.sub(%r{(.*?)(<llmed-code context='#{ctx.name}' digest='.*?'>)(.+?)(</llmed-code>)(.*?)}m) do
            "#{::Regexp.last_match(1)}<llmed-code context='#{ctx.name}' digest='#{ctx.digest}'>#{ctx.code}#{::Regexp.last_match(4)}#{::Regexp.last_match(5)}"
          end
          @changes << [:updated, ctx]
        else
          content += "#{code_comment}<llmed-code context='#{ctx.name}' digest='#{ctx.digest}'>
#{ctx.code}
        #{code_comment}</llmed-code>"
          @changes << [:added, ctx]
        end
      end

      @content = content
      self
    end

    private

    def initialize(origin)
      @origin = origin
      @content = ''
      @changes = []
    end
  end
end
