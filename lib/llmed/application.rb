# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Application
    attr_reader :contexts, :name, :language

    def initialize(name:, language:, output_file:, block:, logger:, release:, release_dir:, output_dir:)
      validate_language(language)

      @name = name
      @output_file = output_file
      @language = language
      @block = block
      @contexts = []
      @logger = logger
      @release = release
      @release_dir = release_dir
      @output_dir = output_dir
    end

    # Example:
    # application { context "demo" { "content" } }
    def context(name, **opts, &block)
      opts[:release_dir] = @release_dir
      ctx = Context.new(name: name, options: opts)
      output = ctx.instance_eval(&block)
      ctx.llm(output) unless ctx.message?

      @contexts << ctx
    end

    def evaluate
      instance_eval(&@block)
    end

    def prepare
      @logger.info("APPLICATION #{@name} COMPILING FOR #{@language}")
      return unless @output_file.is_a?(String)
      return unless @release

      output_file = Pathname.new(@output_dir) + @output_file

      if @release && File.exist?(output_file) && !File.exist?(release_source_code)
        FileUtils.cp(output_file, release_source_code)
        FileUtils.cp(output_file, release_main_source_code)
        @logger.info("APPLICATION #{@name} RELEASE FILE #{release_source_code}")
      elsif @release && !File.exist?(output_file) && File.exist?(release_main_source_code)
        FileUtils.cp(release_main_source_code, output_file)
        return
      end

      @logger.info("APPLICATION #{@name} INPUT RELEASE FILE #{release_main_source_code}")
    end

    def source_code
      return unless File.exist?(release_source_code)

      File.read(release_source_code)
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

    def patch_or_create(output)
      output_content = output

      if @release && File.exist?(release_source_code) && !release_contexts.empty?
        output_release = Release.load(File.read(release_source_code), code_comment(@language))
        input_release = Release.load(output, code_comment(@language))
        output_content = output_release.merge!(input_release, user_contexts).content
        output_release.changes do |change|
          action, ctx = change
          case action
          when :added
            @logger.info("APPLICATION #{@name} PATCH ADDING NEW CONTEXT #{ctx.name}")
          when :updated
            @logger.info("APPLICATION #{@name} PATCH UPDATING CONTEXT #{ctx.name} TO DIGEST #{ctx.digest}")
          end
        end
      end

      output_file(@output_dir) do |file|
        file.write(output_content)
      end
    end

    def system_prompt(configuration)
      configuration.prompt(language: language,
                           source_code: source_code,
                           update_context_digests: digests_of_context_to_update)
    end

    def rebuild?
      return true unless @release
      return true if release_contexts.empty?

      !digests_of_context_to_update.tap do |digests|
        digests.each do |digest|
          context_by_digest = release_contexts.invert

          if context_by_digest[digest].nil?

            @logger.info("APPLICATION #{@name} ADDING CONTEXT #{user_contexts.invert[digest]}")
          else
            @logger.info("APPLICATION #{@name} REBUILDING CONTEXT #{context_by_digest[digest]}")
          end
        end
      end.empty?
    end

    def write_statistics(response)
      return unless @output_file.is_a?(String)

      statistics_file = Pathname.new(@release_dir) + "#{@output_file}.statistics"

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

    private

    def digests_of_context_to_update
      update_context_digest = []

      unless release_instance.empty?
        # rebuild context from top to down
        # we are expecting:
        # - top the most stable concepts
        # - buttom the most inestable concepts
        update_rest = false
        @contexts.each do |ctx|
          release_context = release_instance.context_by(ctx.name)

          if update_rest && release_context.digest?
            update_context_digest << release_context.digest
            next
          end

          # added new context
          if !release_context.digest? && !user_contexts[ctx.name].nil?
            update_context_digest << user_contexts[ctx.name]
            next
          elsif release_context.digest? && !ctx.same_digest?(release_context.digest)
            update_rest = true
            update_context_digest << release_context.digest
            next
          elsif release_context.digest?
            # maybe the context is not connected to the source code
            next
          end
        end
      end

      update_context_digest
    end

    def release_source_code
      Pathname.new(@release_dir) + "#{@output_file}.r#{@release}#{@language}.cache"
    end

    def release_main_source_code
      Pathname.new(@release_dir) + "#{@output_file}.release"
    end

    def user_contexts
      @contexts.map do |ctx|
        [ctx.name, ctx.digest]
      end.to_h
    end

    def release_contexts
      return {} unless @release

      return {} unless File.exist?(release_source_code)

      File.read(release_source_code).scan(/context='(.+?)' digest='(.+?)'/).to_h
    end

    def release_instance
      if File.exist?(release_source_code)
        Release.load(File.read(release_source_code), code_comment(@language))
      else
        Release.empty
      end
    end

    def code_comment(language)
      { ruby: '#', node: '//', elixir: '#', bash: '#', python: '#', go: '//', javascript: '//', c: '//',
        cpp: '//' }.fetch(language)
    end

    def validate_language(language)
      return unless code_comment(language.to_sym).nil?

      raise "language #{language} not supported"
    end
  end
end
