# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'set'

class LLMed
  class Application
    attr_reader :contexts, :name, :language

    class CodeComment
      def initialize(language)
        raise "language #{language} not supported" if code_comment(language.to_sym).nil?

        @language = language.to_sym
      end

      def begin
        code_comment(@language).first
      end

      def end
        code_comment(@language).last
      end

      private

      def code_comment(language)
        { ruby: ['#', ''], node: ['//', ''], elixir: ['#', ''], bash: ['#', ''], python: ['#', ''], go: ['//', ''], javascript: ['//', ''], c: ['//', ''],
          cpp: ['//', ''], html: ['<!--', '-->'] }.fetch(language)
      end
    end

    def initialize(name:, language:, output_file:, block:, logger:, release:, release_dir:, output_dir:)
      snapshot_file = Pathname.new(release_dir) + "#{output_file}.snapshot"

      @name = name
      @output_file = output_file
      @language = language.to_sym
      @code_comment = CodeComment.new(language)
      @block = block
      @contexts = []
      @goals = []
      @logger = logger
      @release = release
      @release_dir = release_dir
      @output_dir = output_dir
      @snapshot = Snapshot.new(snapshot_file)
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

    def achieve(name, **opts, &block)
      opts[:release_dir] = @release_dir
      goal = Goal.new(name: name, options: opts)
      output = goal.instance_eval(&block)
      goal.llm(output) unless goal.message?

      @goals << goal
    end

    def evaluate
      instance_eval(&@block)
    end

    class Snapshot
      attr_reader :snapshot_file

      def initialize(snapshot_file)
        @snapshot_file = snapshot_file
        @contexts = []
      end

      def sync(default)
        load(default)
        dump
      end

      def refresh(contexts)
        @contexts = contexts.map{ |ctx| [ctx.name, {'name' => ctx.name, 'message' => ctx.raw}]}.to_h
        dump
      end

      def diff(other_contexts)
        diffs = {}
        other_contexts.each do |other_ctx|
          current_ctx = @contexts[other_ctx.name]
          result = line_diff(current_ctx['message'], other_ctx.raw)
          # omit not changes
          if !result.all?{|op, line| op == '=:'}
            diffs[other_ctx.name] = result
          end
        end

        diffs
      end

      private

      def line_diff(text1, text2)
        lines1 = text1.split("\n")
        lines2 = text2.split("\n")

        result = []

        i1 = 0
        i2 = 0

        while i1 < lines1.size || i2 < lines2.size
          line1 = lines1[i1]
          line2 = lines2[i2]

          if i1 < lines1.size && i2 < lines2.size && line1 == line2
            result << ["=:", line1]
            i1 += 1
            i2 += 1
          elsif i1 < lines1.size && (i2 >= lines2.size || !lines2[i2..-1].include?(line1))
            result << ["-:", line1]
            i1 += 1
          elsif i2 < lines2.size && (i1 >= lines1.size || !lines1[i1..-1].include?(line2))
            result << ["+:", line2]
            i2 += 1
          else
            # Try to find if one of the lines matches later
            idx1 = lines1[i1+1..-1]&.index(line2)
            idx2 = lines2[i2+1..-1]&.index(line1)

            if !idx1.nil? && (idx2.nil? || idx1 <= idx2)
              result << ["-:", line1]
              i1 += 1
            elsif !idx2.nil?
              result << ["+:", line2]
              i2 += 1
            else
              # Lines differ, treat both as deleted and added
              result << ["-:", line1]
              result << ["+:", line2]
              i1 += 1
              i2 += 1
            end
          end
        end

        result
      end

      def load(default)
        if File.exist?(@snapshot_file)
          File.open(@snapshot_file, 'r') do |f|
            @contexts = JSON.load(f.read)['contexts']
          end
        else
          @contexts = default.map{ |ctx| [ctx.name, {'name' => ctx.name, 'message' => ctx.raw}]}.to_h
        end
      end

      def dump
        File.open(@snapshot_file, 'w') do |file|
          file.write(JSON.dump({'contexts' => @contexts}))
        end
      end
    end

    def prepare_snapshot
      raise "snapshot preparation require contexts" if @contexts.empty?

      @logger.info("APPLICATION #{@name} PREPARING SNAPSHOT #{@snapshot.snapshot_file}")

      @snapshot.sync(@contexts)
    end

    def prepare_release
      @logger.info("APPLICATION #{@name} COMPILING FOR #{@language} RELEASE #{@release}")
      return unless @output_file.is_a?(String)
      return unless @release

      output_file = Pathname.new(@output_dir) + @output_file

      if @release && File.exist?(output_file) && !File.exist?(release_source_code)

      elsif @release && !File.exist?(output_file) && File.exist?(release_main_source_code)
        FileUtils.mkdir_p(File.dirname(output_file))
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
        output_release = Release.load(File.read(release_source_code), @code_comment)
        input_release = Release.load(output, @code_comment)
        output_content = output_release.merge!(input_release, user_contexts).content

        output_release.changes.each do |change|
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

      # only update snapshot if changes are made
      if !File.exist?(release_source_code)
        @snapshot.refresh(@contexts)
        @logger.info("APPLICATION #{@name} SNAPSHOT REFRESHED")
      end

      return unless @output_file.is_a?(String)
      output_file = Pathname.new(@output_dir) + @output_file
      FileUtils.cp(output_file, release_source_code)
      FileUtils.cp(output_file, release_main_source_code)
      @logger.info("APPLICATION #{@name} RELEASE FILE #{release_source_code}")
    end

    def system_prompt(configuration)
      contexts_diffs = @snapshot.diff(contexts)
      changes_of_contexts = ''
      if contexts_diffs.any?
        contexts_diffs.each do |context_name, diffs|
          changes_of_contexts += "# Context: #{context_name}\n"
          changes_of_contexts += diffs.map { |op, line| "#{op} #{line}" }.join("\n")
        end
      end

      configuration.prompt(language: language,
                           source_code: source_code,
                           code_comment_begin: @code_comment.begin,
                           code_comment_end: @code_comment.end,
                           update_context_digests: digests_of_context_to_update,
                           changes_of_contexts: changes_of_contexts,
                           goals: goals)
    end

    def rebuild?
      return true unless @release
      return true if release_contexts.empty?

      !digests_of_context_to_update.tap do |digests|
        digests.each do |digest|
          context_by_digest = release_contexts.invert
          if context_by_digest[digest].nil?
            @logger.info("APPLICATION #{@name} ADDING CONTEXT #{user_contexts.by_digest(digest).name}")
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

    def goals
      @goals.map(&:message).join("\n")
    end

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
          if !release_context.digest? && !user_contexts.by_name(ctx.name).nil?
            update_context_digest << user_contexts.by_name(ctx.name).digest
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
      UserContexts.new(@contexts)
    end

    def release_contexts
      return {} unless @release

      return {} unless File.exist?(release_source_code)

      File.read(release_source_code).scan(/context='(.+?)' digest='(.+?)'/).to_h
    end

    def release_instance
      if File.exist?(release_source_code)
        Release.load(File.read(release_source_code), @code_comment)
      else
        Release.empty(@code_comment)
      end
    end
  end
end
