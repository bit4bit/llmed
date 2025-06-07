# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Context
    attr_reader :name

    def initialize(name:, options: {})
      @name = name
      @skip = options[:skip] || false
      @release_dir = options[:release_dir]
    end

    def skip?
      @skip
    end

    def same_digest?(val)
      digest == val
    end

    def digest
      Digest::SHA256.hexdigest "#{@name}.#{@message}"
    end

    def message
      "# Context: #{@name} Digest: #{digest}\n\n#{@message}"
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
