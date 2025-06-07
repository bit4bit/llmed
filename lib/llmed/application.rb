# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Application
    attr_reader :contexts, :name, :language

    def initialize(name:, language:, output_file:, block:, logger:, release:, release_dir:, output_dir:)
      raise 'required language' if language.nil?

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
      return unless @output_file.is_a?(String)
      return unless @release

      output_file = Pathname.new(@output_dir) + @output_file
      if @release && !File.exist?(release_source_code)
        FileUtils.cp(output_file, release_source_code)
        FileUtils.cp(output_file, release_main_source_code)
        @logger.info("APPLICATION #{@name} RELEASE FILE #{release_source_code}")
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

      if @release && File.exist?(release_source_code)
        release_source_code_content = File.read(release_source_code)
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
          release_source_code_content = release_source_code_content.sub(%r{(.*?)(<llmed-code context='#{name}' digest='.*?'>)(.+?)(</llmed-code>)(.*?)}m) do
            "#{::Regexp.last_match(1)}<llmed-code context='#{name}' digest='#{new_digest}'>#{new_code}#{::Regexp.last_match(4)}#{::Regexp.last_match(5)}"
          end
        end

        output_content = release_source_code_content
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
          @logger.info("APPLICATION #{@name} REBUILDING CONTEXT #{context_by_digest[digest]}")
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

    def release_source_code
      Pathname.new(@release_dir) + "#{@output_file}.r#{@release}#{@language}.cache"
    end

    def release_main_source_code
      Pathname.new(@release_dir) + "#{@output_file}.release"
    end

    def release_contexts
      return {} unless @release

      return {} unless File.exist?(release_source_code)

      File.read(release_source_code).scan(/context='(.+)' digest='(.+)'/).to_h
    end
  end
end
