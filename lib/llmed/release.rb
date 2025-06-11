# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Release
    ContextCode = Struct.new(:name, :digest, :code, :after) do
      def to_llmed_code(code_comment)
        "#{code_comment}<llmed-code context='#{name}' digest='#{digest}' after='#{after}'>#{code}#{code_comment}</llmed-code>"
      end

      def digest?
        return false if digest.nil?
        return false if digest.empty?

        true
      end
    end

    def self.load(origin, code_comment)
      new(origin, code_comment)
    end

    def self.empty
      new('', '')
    end

    def content
      out = ''

      @contexts.each do |ctx|
        out += ctx.to_llmed_code(@code_comment)
        out += "\n"
      end

      out.strip!

      out
    end

    def empty?
      @origin.empty?
    end

    attr_reader :contexts

    def changes
      changes = @changes.dup
      @changes.clear
      changes
    end

    def context_by(name)
      @contexts.each do |ctx|
        return ctx if ctx.name == name
      end

      ContextCode.new('', '', '', '')
    end

    def has_context?(name)
      context_by(name).digest?
    end

    def merge!(release)
      contexts = []

      # updates
      @contexts.each do |ctx|
        new_ctx = release.context_by(ctx.name)
        if release.has_context?(ctx.name)
          contexts << new_ctx
          @changes << [:updated, new_ctx]
        else
          contexts << ctx
        end
      end

      # insertions
      insertions = []
      release.contexts.each do |new_ctx|
        next if has_context?(new_ctx.name)

        contexts.each_with_index do |current_ctx, idx|
          if current_ctx.digest == new_ctx.after
            insertions << [idx, current_ctx.digest, new_ctx]
            break
          end
        end
      end

      insertions.each do |action|
        idx, old_digest, new_ctx = action
        contexts.each do |ctx|
          ctx.after = new_ctx.digest if ctx.after == old_digest
        end
        contexts.insert(idx, new_ctx)
        @changes << [:added, new_ctx]
      end

      @contexts = contexts
      self
    end

    private

    def initialize(origin, code_comment)
      @origin = origin
      @content = ''
      @changes = []
      @code_comment = code_comment
      @contexts = []

      @origin.scan(%r{<llmed-code context='(.+?)' digest='(.+?)' after='(.*?)'>(.+?)#{@code_comment}+\s*</llmed-code>}im).each do |match|
        name, digest, after, code = match
        @contexts << ContextCode.new(name, digest, code, after)
      end
    end
  end
end
