# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Goal
    attr_reader :name, :options

    def initialize(name:, options: {})
      @name = name
      @options = options

    end

    def llm(message)
      @message = message
    end

    def message
      "<goal name=\"#{@name}\">#{@message}</goal>"
    end

    def message?
       !(@message.nil? || @message.empty?)
    end
  end
end
