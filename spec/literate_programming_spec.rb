# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'

describe LLMed::LiterateProgramming::Markdown do
  it 'parse comment' do
    md = LLMed::LiterateProgramming::Markdown.new()
    expect(md.parse("#% Comment

# Context A
Contenido

")).to eq  [
         {type: :context,
          title: "_default",
          content: [
            {type: :comment, content: "Comment\n"},
            {type: :string, content: "\n"}
          ]},
         {type: :context,
          title: "Context A",
          content: [
            {type: :string, content: "Contenido\n"},
            {type: :string, content: "\n"}
          ]}
       ]
  end

  it 'parse without initial context' do
    md = LLMed::LiterateProgramming::Markdown.new()
    expect(md.parse("
Here pre data

# Context A
Contenido
[link](http://link)

## SubContexto A
SubContenido

# Contexto 3
Contenido 3

")).to eq  [
         {type: :context,
          title: "_default",
          content: [
            {type: :string, content: "\n"},
            {type: :string, content: "Here pre data\n"},
            {type: :string, content: "\n"}
          ]},
         {type: :context,
          title: "Context A",
          content: [
            {type: :string, content: "Contenido\n"},
            {type: :link, content: "link", reference: "http://link"},
            {type: :string, content: "\n"},
            {type: :string, content: "## SubContexto A\n"},
            {type: :string, content: "SubContenido\n"},
            {type: :string, content: "\n"}
          ]},
         {type: :context,
          title: "Contexto 3",
          content: [
            {type: :string, content: "Contenido 3\n"},
            {type: :string, content: "\n"}
          ]}]
  end
  
  it 'parse with initial context' do
    md = LLMed::LiterateProgramming::Markdown.new()
    expect(md.parse("# Context A
Contenido
[link](http://link)

## SubContexto A
SubContenido

# Contexto 3
Contenido 3

")).to eq [{type: :context,
            title: "Context A",
            content: [
              {type: :string, content: "Contenido\n"},
              {type: :link, content: "link", reference: "http://link"},
              {type: :string, content: "\n"},
              {type: :string, content: "## SubContexto A\n"},
              {type: :string, content: "SubContenido\n"},
              {type: :string, content: "\n"}
            ]},
           {type: :context,
            title: "Contexto 3",
            content: [
              {type: :string, content: "Contenido 3\n"},
              {type: :string, content: "\n"}
            ]}]
  end
end
