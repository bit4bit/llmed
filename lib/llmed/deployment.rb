# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Deployment
    def initialize(name:, output_dir:, logger:, block:)
      @name = name
      @output_dir = output_dir
      @logger = logger
      @block = block
    end

    def execute
      @logger.info("DEPLOYMENT [#{@name}] EXECUTING")
      instance_eval(&@block)
    end
  end
end
