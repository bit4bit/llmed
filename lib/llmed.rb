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

  class Context
    attr_reader :name

    def initialize(name:, options: {})
      @name = name
      @skip = options[:skip] || false
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
  end

  class Configuration
    def initialize
      @prompt = LLMed::LLM::Template.build(template: "
You are a software developer and only have knowledge of the programming language {language}.
Your response must contain only the generated source code, with no additional text.
All source code must be written in a single file, and you must ensure it runs correctly on the first attempt.
Always include the properly escaped comment: LLMED-COMPILED.

You must only modify the following source code:
{source_code}

Only generate source code of the context who digest belongs to {update_context_digests}.

Wrap with comment every code that belongs to the indicated context, example in ruby:
#<llmed-code context='context name' digest='....'>
...
#</llmed-code>

", input_variables: %w[language source_code update_context_digests])
    end

    def prompt(language:, source_code:, update_context_digests: [])
      @prompt.format(language: language, source_code: source_code,
                     update_context_digests: update_context_digests.join(','))
    end

    # Change the default prompt, input variables: language, source_code
    # Example:
    #  set_prompt "my new prompt"
    def set_prompt(*arg, input_variables: %w[language source_code], **args)
      input_variables = {} if args[:file]
      prompt = File.read(args[:file]) if args[:file]
      prompt ||= arg.first
      @prompt = LLMed::LLM::Template.build(template: prompt, input_variables: input_variables)
    end

    # Set default language used for all applications.
    # Example:
    #  set_langugage :ruby
    def set_language(language)
      @language = language
    end

    def set_llm(provider:, api_key:, model:)
      @provider = provider
      @provider_api_key = api_key
      @provider_model = model
    end

    def language(main)
      lang = main || @language
      raise 'Please assign a language to the application or general with the function set_languag' if lang.nil?

      lang
    end

    def llm
      case @provider
      when :openai
        LLMed::LLM::OpenAI.new(
          api_key: @provider_api_key,
          default_options: { temperature: 0.7, chat_model: @provider_model }
        )
      when :test
        LLMed::LLM::Test.new
      when nil
        raise 'Please set the provider with `set_llm(provider, api_key, model)`'
      else
        raise "not implemented provider #{@provider}"
      end
    end
  end

  class Application
    attr_reader :contexts, :name, :language

    def initialize(name:, language:, output_file:, block:, logger:, release:)
      raise 'required language' if language.nil?

      @name = name
      @output_file = output_file
      @language = language
      @block = block
      @contexts = []
      @logger = logger
      @release = release
    end

    def context(name, **opts, &block)
      ctx = Context.new(name: name, options: opts)
      output = ctx.instance_eval(&block)
      ctx.llm(output) unless ctx.message?

      @contexts << ctx
    end

    def evaluate
      instance_eval(&@block)
    end

    def source_code(output_dir, release_dir)
      return unless @output_file.is_a?(String)
      return unless @release

      release_source_code = Pathname.new(release_dir) + "#{@output_file}.r#{@release}#{@language}.cache"
      release_main_source_code = Pathname.new(release_dir) + "#{@output_file}.release"
      output_file = Pathname.new(output_dir) + @output_file
      if @release && !File.exist?(release_source_code)
        FileUtils.cp(output_file, release_source_code)
        FileUtils.cp(output_file, release_main_source_code)
        @logger.info("APPLICATION #{@name} RELEASE FILE #{release_source_code}")
      end
      @logger.info("APPLICATION #{@name} INPUT RELEASE FILE #{release_main_source_code}")
      File.read(release_source_code)
    end

    def release_contexts(_output_dir, release_dir)
      return {} unless @release

      release_source_code = Pathname.new(release_dir) + "#{@output_file}.r#{@release}#{@language}.cache"
      return {} unless File.exist?(release_source_code)

      File.read(release_source_code).scan(/context='(.+)' digest='(.+)'/).to_h
    end

    def output_file(output_dir, mode = 'w', &block)
      if @output_file.respond_to? :write
        yield @output_file
      else
        path = Pathname.new(output_dir) + @output_file
        FileUtils.mkdir_p(File.dirname(path))

        @logger.info("APPLICATION #{@name} OUTPUT FILE #{path}")

        File.open(path, mode, &block)
      end
    end

    def patch_or_create(output_dir, release_dir, output)
      release_source_code_path = Pathname.new(release_dir) + "#{@output_file}.r#{@release}#{@language}.cache"

      if @release && File.exist?(release_source_code_path)
        release_source_code = File.read(release_source_code_path)
        output_contexts = output.scan(%r{<llmed-code context='(.+?)' digest='(.+?)'>(.+?)</llmed-code>}im)

        output_contexts.each do |match|
          name, digest, new_code = match
          new_digest = digest
          @contexts.each do |ctx|
            if ctx.name == name
              new_digest = ctx.digest
              break
            end
          end

          @logger.info("APPLICATION #{@name} PATCHING CONTEXT #{name} \n\tFROM #{digest}\n\tTO DIGEST #{new_digest}")
          release_source_code = release_source_code.sub(%r{(.*?)(<llmed-code context='#{name}' digest='.*?'>)(.+?)(</llmed-code>)(.*?)}m) do
            "#{::Regexp.last_match(1)}<llmed-code context='#{name}' digest='#{new_digest}'>#{new_code}#{::Regexp.last_match(4)}#{::Regexp.last_match(5)}"
          end
        end

        output_file(output_dir) do |file|
          file.write(release_source_code)
        end
      else
        output_file(output_dir) do |file|
          file.write(output)
        end
      end
    end

    def digests_of_context_to_update(output_dir, release_dir)
      update_context_digest = []
      release_contexts = release_contexts(output_dir, release_dir)

      unless release_contexts.empty?
        # rebuild context from top to down
        # we are expecting:
        # - top the most stable concepts
        # - buttom the most inestable concepts
        update_rest = false
        @contexts.each do |ctx|
          release_context_digest = release_contexts[ctx.name]
          # maybe the context is not connected to the source code
          next if release_context_digest.nil?

          if update_rest
            update_context_digest << release_context_digest
            next
          end
          next if ctx.same_digest?(release_context_digest)

          update_rest = true
          update_context_digest << release_context_digest
        end
      end

      update_context_digest
    end

    def rebuild?(output_dir, release_dir)
      return true unless @release

      update_context_digest = digests_of_context_to_update(output_dir, release_dir)
      release_contexts = release_contexts(output_dir, release_dir)
      update_context_digest.each do |digest|
        context_by_digest = release_contexts.invert
        @logger.info("APPLICATION #{@name} REBUILDING CONTEXT #{context_by_digest[digest]}")
      end

      !update_context_digest.empty?
    end

    def write_statistics(release_dir, response)
      return unless @output_file.is_a?(String)

      statistics_file = Pathname.new(release_dir) + "#{@output_file}.statistics"

      File.open(statistics_file, 'a') do |file|
        stat = {
          inserted_at: Time.now.to_i,
          name: @name,
          provider: response.provider,
          model: response.model,
          release: @release,
          total_tokens: response.total_tokens,
          duration_seconds: response.duration_seconds
        }
        file.puts stat.to_json
      end
      @logger.info("APPLICATION #{@name} WROTE STATISTICS FILE #{statistics_file}")
    end

    def notify(message)
      Notify.notify("APPLICATION #{@name}", message)
    end
  end

  def initialize(logger:)
    @logger = logger
    @applications = []
    @configuration = Configuration.new
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
    @app = Application.new(name: name, language: @configuration.language(language), output_file: output_file,
                           block: block, logger: @logger, release: release)
    @applications << @app
  end

  def compile(output_dir:, release_dir: nil)
    @applications.each do |app|
      compile_application(app, output_dir, release_dir)
    end
  end

  private

  def compile_application(app, output_dir, release_dir)
    release_dir ||= output_dir

    app.notify('COMPILE START')
    @logger.info("APPLICATION #{app.name} COMPILING")

    llm = @configuration.llm

    app.evaluate

    system_content = @configuration.prompt(language: app.language,
                                           source_code: app.source_code(
                                             output_dir, release_dir
                                           ),
                                           update_context_digests: app.digests_of_context_to_update(output_dir,
                                                                                                    release_dir))
    messages = [LLMed::LLM::Message::System.new(system_content)]
    app.contexts.each do |ctx|
      next if ctx.skip?

      messages << LLMed::LLM::Message::User.new(ctx.message)
    end
    if app.rebuild?(output_dir, release_dir)
      llm_response = llm.chat(messages: messages)
      @logger.info("APPLICATION #{app.name} TOTAL TOKENS #{llm_response.total_tokens}")
      write_output(app, output_dir, release_dir, llm_response.source_code)
      write_statistics(app, release_dir, llm_response)
      app.notify("COMPILE DONE #{llm_response.duration_seconds}")
    else
      @logger.info("APPLICATION #{app.name} NOT CHANGES DETECTED")
    end
  end

  def write_statistics(app, release_dir, response)
    app.write_statistics(release_dir, response)
  end

  def write_output(app, output_dir, release_dir, output)
    app.patch_or_create(output_dir, release_dir, output)
  end
end

require_relative 'llm'
