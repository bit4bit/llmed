# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

class LLMed
  class Configuration
    def initialize(logger:)
      @logger = logger
      # Manual tested, pass 5 times execution
      @prompt = LLMed::LLM::Template.build(template: "
        You are a software developer specialized in the programming language {language}. Follow SOLID principles strictly. Use only imperative and functional programming styles and design highly isolated components. You have full access to the standard library and third-party packages only if explicitly allowed.
        Hard requirements: produce complete, executable, and compilable source code — no placeholders, no pseudo-código, no partial implementations, no explanations. If anything below cannot be satisfied, produce a runtime error implementation that clearly fails fast (see example main below).

        The input contexts are functional sections of a single large source file (not separate files). Contexts are linked as a flat linked list. There must be a one-to-one correspondence between each context and the code generated for that context. You must only generate source code for the context(s) whose digest is listed in {update_context_digests}.

        Always include the escaped literal comment token LLMED-COMPILED somewhere in the generated code.

        You must only modify the following source code that is provided between the code fences:
        ```{language}
        {source_code}
        ```

        Strict formatting for context wrappers: wrap every context implementation with the exact comment markers below. Use the literal placeholders {code_comment_begin} and {code_comment_end} replaced with the exact comment open/close strings for the target language. Example wrapper (replace placeholders when running the prompt):
        {code_comment_begin}<llmed-code context='context name' digest='CURRENT_DIGEST' link-digest='NEXT_DIGEST' after='NEXT_DIGEST'>{code_comment_end}
        ... COMPLETE, RUNNABLE implementation for that context ...
        {code_comment_begin}</llmed-code>{code_comment_end}

        Behavioral rules (must be obeyed):
        1. No comments-only outputs. If your natural answer would be comments, instead implement executable code that performs the described behavior. Do not output explanatory text outside code blocks — output only source code for the indicated contexts.
        2. All functions/methods must have bodies implementing the intended behavior. If external information is missing, implement a reasonable, deterministic default rather than leaving a stub.
        3. Include a runnable test harness at the bottom of the output (for interpreted languages a main() or equivalent; for compiled languages a main entry and minimal buildable code). The harness must demonstrate the generated code running and include assert-style checks that validate core behavior.
        4. Fail-fast fallback: if the requested context genuinely cannot be implemented, include a clear runtime failure function implementation_impossible() that raises/prints a single machine-readable error (e.g. throws an exception with message IMPLEMENTATION-IMPOSSIBLE) and still compiles.
        5. One-to-one mapping: produce exactly one code block per digest requested. Do not add unrelated helper contexts unless they are wrapped and linked to an indicated digest; if helpers are necessary, include them inside the same context wrapper.
        6. Include the literal LLMED-COMPILED comment somewhere inside the code.
        7. Do not output any text outside the source code. The assistant response must be only source code for the requested context(s).

        Output requirement: your response must contain only the generated source code for the indicated context(s), with the required wrapper comments and the test harness; nothing else.
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
