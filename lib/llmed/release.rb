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
        user_context = user_contexts.by_name(ctx.name)
        ctx.digest = user_context.digest unless user_context.nil?
      end

      # insertions missed user contexts
      user_contexts.each do |user_context|
        next if contexts.any? { |ctx| ctx.name == user_context.name }

        code = release.context_by(user_context.name).code
        new_ctx = ContextCode.new(user_context.name, user_context.digest, code, '')
        contexts.prepend(new_ctx)
        @changes << [:added, new_ctx]
      end

      # code context must have the same order as user contexts
      if user_contexts.empty?
        contexts_sorted = contexts
      else
        user_contexts_iter = user_contexts.dup
        contexts_iter = contexts.dup
        order_digests = rewire_code_contexts(contexts_iter, user_contexts_iter)

        contexts_on_digests = order_digests.map { |digest| contexts_iter.find { |ctx| ctx.digest == digest } }
        contexts_missing_digests = contexts_iter.select { |ctx| !order_digests.include?(ctx.digest) }
        contexts_sorted = contexts_on_digests + contexts_missing_digests
      end

      # Sort contexts so that the latest digest (the one whose 'after' is empty) comes last
      @contexts = contexts_sorted.sort do |a, b|
        if a.after.empty? && !b.after.empty?
          1
        elsif !a.after.empty? && b.after.empty?
          -1
        else
          0
        end
      end

      self
    end

    private

    def rewire_code_contexts(code_contexts, user_contexts)
      order_digests = []
      user_contexts.each_with_next do |user_context, next_user_context|
        ctx = code_contexts.find { |ctx| ctx.name == user_context.name }
        if ctx
          ctx.digest = user_context.digest
          order_digests << user_context.digest
          ctx.after = '' if user_contexts.count > 1
          ctx.after = next_user_context.digest if next_user_context
        end
      end

      order_digests
    end

    def initialize(origin, code_comment)
      @origin = origin
      @content = ''
      @changes = []
      @code_comment = code_comment
      @contexts = []

      @origin.scan(%r{<llmed-code context='(.+?)' digest='(.+?)'(?:\s+[^>]*?)?(after='.*?')?>#{@code_comment.end}(.+?)#{@code_comment.begin}+\s*<?/?llmed-code}im).each do |match|
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
