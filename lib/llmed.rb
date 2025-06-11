# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'pp'
require 'csv'
require 'digest'
require 'json'
require 'pathname'
require 'fileutils'
require 'forwardable'
require 'notify'

class LLMed
  extend Forwardable

  def initialize(logger:, output_dir:, release_dir:)
    @logger = logger
    @applications = []
    @configuration = Configuration.new
    @release_dir = release_dir || output_dir
    @output_dir = output_dir
  end

  def eval_source(code)
    instance_eval(code)
  end

  # changes default language
  def_delegator :@configuration, :set_language, :set_language
  # changes default llm
  def_delegator :@configuration, :set_llm, :set_llm
  # changes default prompt
  def_delegator :@configuration, :set_prompt, :set_prompt

  def application(name, output_file:, language: nil, release: nil, &block)
    @app = Application.new(
      name: name,
      language: @configuration.language(language),
      output_file: output_file,
      block: block,
      logger: @logger,
      release: release,
      release_dir: @release_dir,
      output_dir: @output_dir
    )
    @applications << @app
  end

  def compile
    @applications.each do |app|
      compile_application(app)
    end
  end

  private

  def compile_application(app)
    app.notify('COMPILE START')

    app.prepare
    app.evaluate
    if app.rebuild?
      llm = @configuration.llm
      messages = [LLMed::LLM::Message::System.new(app.system_prompt(@configuration))]
      app.contexts.each do |ctx|
        next if ctx.skip?

        messages << LLMed::LLM::Message::User.new(ctx.message)
      end

      llm_response = llm.chat(messages: messages)
      @logger.info("APPLICATION #{app.name} TOTAL TOKENS #{llm_response.total_tokens}")

      app.patch_or_create(llm_response.source_code)
      app.write_statistics(llm_response)
      app.notify("COMPILE DONE #{llm_response.duration_seconds}")
    else
      @logger.info("APPLICATION #{app.name} NOT CHANGES DETECTED")
    end
  end
end

require_relative 'llm'
require_relative 'llmed/configuration'
require_relative 'llmed/context'
require_relative 'llmed/release'
require_relative 'llmed/application'
