# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'


describe LLMed::Release do
  before(:all) do
    @ruby_comment = LLMed::Application::CodeComment.new(:ruby)
    @html_comment = LLMed::Application::CodeComment.new(:html)
    @node_comment = LLMed::Application::CodeComment.new(:node)
  end

  it 'merge only update' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code A
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", @ruby_comment)
    rchange = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code AA
#</llmed-code>", @ruby_comment)

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>"
  end

  it 'merge only update HTML' do
    r1 = LLMed::Release.load("<!--<llmed-code context='A' digest='abc' after='contextB'>-->
code A
<!--</llmed-code>-->
<!--<llmed-code context='B' digest='contextB' after=''>-->
code B
<!--</llmed-code>-->", @html_comment)
    rchange = LLMed::Release.load("<!--<llmed-code context='A' digest='abc' after='contextB'>-->
code AA
<!--</llmed-code>-->", @html_comment)

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "<!--<llmed-code context='A' digest='contextA' after='contextB'>-->
code AA
<!--</llmed-code>-->
<!--<llmed-code context='B' digest='contextB' after=''>-->
code B
<!--</llmed-code>-->"
  end

  it 'merge only update broken HTML' do
    r1 = LLMed::Release.load("<!--<llmed-code context='A' digest='abc' after='contextB'>-->
code A
<!--</llmed-code>-->
<!--<llmed-code context='B' digest='contextB' after=''>-->
code B
<!--</llmed-code>-->", @html_comment)
    rchange = LLMed::Release.load("<!--<llmed-code context='A' digest='abc' after='contextB'>-->
code AA
<!--</llmed-code-->", @html_comment)

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "<!--<llmed-code context='A' digest='contextA' after='contextB'>-->
code AA
<!--</llmed-code>-->
<!--<llmed-code context='B' digest='contextB' after=''>-->
code B
<!--</llmed-code>-->"
  end

  it 'merge only node broken comment' do
    r1 = LLMed::Release.load("//<llmed-code context='A' digest='abc' after='contextB'>
code A
//</llmed-code>
//<llmed-code context='B' digest='contextB' after=''>
code B
//</llmed-code>", @node_comment)
    rchange = LLMed::Release.load("//<llmed-code context='A' digest='abc' after='contextB'>
code AA
http://localhost:300;
//</llmed-code-->", @node_comment)

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "//<llmed-code context='A' digest='contextA' after='contextB'>
code AA
http://localhost:300;
//</llmed-code>
//<llmed-code context='B' digest='contextB' after=''>
code B
//</llmed-code>"
  end

  it 'merge append new context' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", @ruby_comment)
    rchange = LLMed::Release.load("#<llmed-code context='C' digest='contextC' after='contextB'>
code C
#</llmed-code>", @ruby_comment)

    r1.merge!(rchange, {})

    expect(r1.content).to eq "#<llmed-code context='A' digest='contextA' after='contextC'>
code AA
#</llmed-code>
#<llmed-code context='C' digest='contextC' after='contextB'>
code C
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>"
  end

  it 'merge context without source code' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='abc'>
code A
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", @ruby_comment)
    rchange = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code AA
#</llmed-code>", @ruby_comment)

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>"
  end

  it 'merge context sync user missed contexts' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='abc'>
code A
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", @ruby_comment)
    rchange = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code AA
#</llmed-code>", @ruby_comment)

    r1.merge!(rchange, {'A' => 'contextA', 'C' => 'contextC'})
    expect(r1.content).to eq "#<llmed-code context='C' digest='contextC' after=''>
#</llmed-code>
#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>"
  end
end
