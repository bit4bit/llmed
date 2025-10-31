# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'erb'

class LLMed
  class UserContexts
    def initialize(contexts)
      @contexts = contexts.dup
    end

    def each(&block)
      @contexts.each(&block)
    end

    def empty?
      @contexts.empty?
    end

    def [](idx)
      @contexts[idx]
    end

    def each_with_next(&block)
      @contexts.each_with_index do |ctx, idx|
        next_ctx = @contexts[idx + 1]
        block.call(ctx, next_ctx)
      end
    end

    def count
      @contexts.count
    end

    def by_name(name)
      @contexts.find { |ctx| ctx.name == name }
    end

    def by_digest(digest)
      @contexts.find { |ctx| ctx.same_digest?(digest) }
    end
  end

  class Context
    attr_reader :name

    def initialize(name:, digest: nil, options: {})
      @name = name
      @skip = options[:skip] || false
      @fixed_digest = digest || nil
      @release_dir = options[:release_dir]
    end

    def skip?
      @skip
    end

    def same_digest?(val)
      digest == val
    end

    def digest
      @fixed_digest || Digest::SHA256.hexdigest("#{@name}.#{@message}")
    end

    def message
      "# Context: \"#{@name}\" Digest: #{digest}\n\n#{@message}"
    end

    def llm(message)
      @message = message
    end

    def message?
      !(@message.nil? || @message.empty?)
    end

    # Example:
    #  context("files") { sh "ls /etc" }
    def sh(cmd)
      `#{cmd}`
    end

    # Example:
    #  context("application") { from_file("application.cllmed") }
    def from_file(path)
      File.read(path)
    end

    # Example:
    #  context("application") { from_erb("application.cllmed.erb") }
    def from_erb(path)
      ERB.new(File.read(path)).result(binding)
    end

    # Example:
    #  context("source") { from_source_code("sourcepathtoinclude") }
    def from_source_code(path)
      code = File.read(path)
      " Given the following source code: #{code}\n\n\n"
    end

    # Example:
    #  context("source") { from_release("file in release dir") }
    def from_release(path)
      code = File.read(Pathname.new(@release_dir) + path)
      " Given the following source code: #{code}\n\n\n"
    end
  end
end
