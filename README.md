# LLMED

LLM Execution Development.

Concepts:
* Source Code = This (there is not name yet)
* Application = Legacy Source Code
* Compiler = LLM

What would happen if:
* Source code becomes just an opaque resource for being executed.
* If we express the context of the solution (compile the idea).

In classic terms the LLM is the Compiler, Source Code is the Binary, the Programming language is Context Description.

```ruby
set_llm provider: :like_openai, api_key: ENV['TOGETHERAI_API_KEY'], model: 'Qwen/Qwen2.5-Coder-32B-Instruct', options: {uri_base: 'https://api.together.xyz/v1'}

application "MINI COUNTER", release: nil, language: :node, output_file: "minicounter.ollmed" do
  # Most stable context: if this changes, all subsequent context will be recompiled.
  context "dependencies" do
    <<-LLM
    * Must use only the standard/native library.
    * Must not use external dependencies.
    LLM
  end

  # Most inestable context: if this changes, only this context will be recompiled.
  context "API" do
    <<-LLM
    API Server listening port 3007.
    Expose the following endpoints:
    - GET /count
      - return the latest count.
    - POST /count
      - increase the count by 1.
    add CORS endpoints.
    LLM
  end
end

Since version 0.4.0, literate programming was introduced, and it is now possible to write code using a markdown-like syntax.

```md
# Dependencies

* Must use only the standard/native library.
* Must not use external dependencies.

# API

API Server listening port 3007.
Expose the following endpoints:
 - GET /count
   - return the latest count.
 - POST /count
   - increase the count by 1.
add CORS endpoints.
```
then compile using command `llmed.literate`.

## Programming flow

* Cycle
  * Edit application.
  * Once you agree with the current state of the application, increase the value of the `release` attribute
* Commit the release file (.release) and the source code (.llmed).

# Usage

* `gem install llmed`
* or local user
  * `gem install --user-install llmed`
  * add to `PATH` the path `~/.local/share/gem/ruby/<RUBY VERSION example 3.0.1>/bin/`
* `llmed -t /tmp/demo.llmed`
* edit
* compile to legacy source code `llmed /tmp/demo.llmed`
* execute or compile the legacy source code.

# Usage Development

* `bundle3.1 install --path vendor/`
* `OPENAI_API_KEY=xxx rake llmed[examples/tictactoe.rb]`

# Interesting

* The same prompt and the same source code produce exactly the same source code, but if we change the prompt a little bit, the source code also changes a little bit. So we have almost a one-to-one relationship. Can the prompt be the source of truth?

# History

After doing a small project in OpenAI i just deleted the chat,
later i decide to add more features but it was not possible
because i did not have the "source code", so some questions hit me:
Why i need to spend time of my life fixing LLM trash?
What if i just compile the idea?
How can i study the idea of others?

So this project is for exploring this questions
