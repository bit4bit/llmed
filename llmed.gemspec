Gem::Specification.new do |s|
  s.name        = 'llmed'
  s.version     = '0.3.10'
  s.licenses    = ['GPL-3.0']
  s.summary = "LLM Execution Development"
  s.description     = "Use this 'compiler' to build software using LLMs in a controlled way. In classical terms, the LLM is the compiler, the context description is the programming language, and the generated output is the binary."
  s.authors     = ["Jovany Leandro G.C"]
  s.email       = 'bit4bit@riseup.net'
  s.files       = Dir.glob("{lib}/**/*") + %w(LICENSE README.md)
  s.homepage    = "https://github.com/bit4bit/llmed"
  s.metadata    = { "source_code_uri" => "https://github.com/bit4bit/llmed" }
  
  s.bindir = 'exe'
  s.executables << 'llmed'

  s.required_ruby_version     = ">= 3.0.0"
  s.required_rubygems_version = ">= 1.3.7"

  s.metadata['allowed_push_host'] = 'https://rubygems.org'

  s.add_dependency "langchainrb", "~> 0.19.5"
  s.add_dependency "ruby-openai", "~> 8.1"
  s.add_dependency "notify", "~> 0.5.2"

  s.add_development_dependency 'rspec', "~> 3.13"
  s.add_development_dependency 'rubocop', "~> 1.75"
end
