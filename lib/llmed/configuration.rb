# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Configuration
    def initialize(logger:)
      @logger = logger
      # Manual tested, pass 5 times execution
      @prompt = LLMed::LLM::Template.build(template: "
You are a software developer with knowledge only of the programming language {language}, following the SOLID principles strictly, you always use only imperative and functional programming, design highly isolated components.
The contexts are declarations of how the source code will be (not a file) ensure to follow this always.
The contexts are connected as a flat linked list.
All the contexts represent one source code.
There is always a one-to-one correspondence between context and source code.
Always include the properly escaped comment: LLMED-COMPILED.

You must only modify the following source code:
{source_code}

Only generate source code of the context who digest belongs to {update_context_digests} or a is a new context.

Wrap with comment every code that belongs to the indicated context, example in {language}:
{code_comment_begin}<llmed-code context='context name' digest='....' after='digest next context'>{code_comment_end}
...
{code_comment_begin}</llmed-code>{code_comment_end}

!!Your response must contain only the generated source code, with no additional text or comments, and you must ensure that runs correctly on the first attempt.
", input_variables: %w[language source_code code_comment_begin code_comment_end update_context_digests])
    end

    def prompt(language:, source_code:, code_comment_begin:, code_comment_end:, update_context_digests: [])
      @prompt.format(language: language,
                     source_code: source_code,
                     code_comment_begin: code_comment_begin,
                     code_comment_end: code_comment_end,
                     update_context_digests: update_context_digests.join(','))
    end

    # Change the default prompt, input variables: language, source_code
    # Example:
    #  set_prompt "my new prompt"
    def set_prompt(*arg, input_variables: %w[language code_comment_begin code_comment_end source_code], **args)
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

    def set_llm(provider:, api_key:, model:, options: {})
      @provider = provider
      @provider_api_key = api_key
      @provider_model = model
      @provider_options = options
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
          logger: @logger,
          api_key: @provider_api_key,
          default_options: { max_tokens: nil, temperature: 0.7, chat_model: @provider_model }
        )
      when :anthropic
        LLMed::LLM::Anthropic.new(
          logger: @logger,
          api_key: @provider_api_key,
          default_options: { max_tokens: nil, temperature: 0.7, chat_model: @provider_model }
        )
      when :like_openai
        LLMed::LLM::LikeOpenAI.new(
          logger: @logger,
          api_key: @provider_api_key,
          default_options: { temperature: 0.7, chat_model: @provider_model },
          llm_options: @provider_options
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
end
