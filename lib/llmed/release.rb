# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Release
    ContextCode = Struct.new(:name, :digest, :code, :after) do
      def to_llmed_code(code_comment)
        close_newline = "\n" if code.strip.empty?
        "#{code_comment.begin}<llmed-code context='#{name}' digest='#{digest}' after='#{after}'>#{code_comment.end}#{code}#{close_newline}#{code_comment.begin}</llmed-code>#{code_comment.end}"
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

    def self.empty(code_comment)
      new('', code_comment)
    end

    def content
      out = String.new

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

    def merge!(release, user_contexts)
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

      # insertions from release
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

      # fix user contexts digest
      contexts.each do |ctx|
        user_context_digest = user_contexts[ctx.name]
        ctx.digest = user_context_digest unless user_context_digest.nil?
      end

      # insertions missed user contexts
      user_contexts.each do |name, digest|
        next if contexts.any? { |ctx| ctx.name == name }
        code = release.context_by(name).code
        new_ctx = ContextCode.new(name, digest, code, '')
        contexts.prepend(new_ctx)
        @changes << [:added, new_ctx]
      end

      # prioritize user order
      contexts_that_belongs_to_user = []
      contexts_that_not_belongs_to_user = []
      if user_contexts.empty?
        contexts_sorted = contexts
      else
        user_contexts_iter = user_contexts.dup
        contexts_iter = contexts.dup

        user_contexts.each do |name, _digest|
          contexts_iter = contexts_iter.delete_if {|ctx|
            if ctx.name == name
              contexts_that_belongs_to_user << ctx
              true
            else
              false
            end
          }
        end

        contexts_that_not_belongs_to_user = contexts_iter
        contexts_sorted = contexts_that_not_belongs_to_user + contexts_that_belongs_to_user
        contexts_sorted.flatten!
      end

      @contexts = contexts_sorted.sort {|a,b|
        if a.digest == b.after
          1
        else
          0
        end
      }

      self
    end

    private

    def initialize(origin, code_comment)
      @origin = origin
      @content = ''
      @changes = []
      @code_comment = code_comment
      @contexts = []

      @origin.scan(%r{<llmed-code context='(.+?)' digest='(.+?)'\s*(after='.*?')?>#{@code_comment.end}(.+?)#{@code_comment.begin}+\s*<?/?llmed-code}im).each do |match|
        name, digest, after_block, code = match
        after = if after_block.nil?
                  ''
                else
                  after_block[/after='(.*?)'/, 1]
                end

        @contexts << ContextCode.new(name, digest, code, after)
      end
    end
  end
end
