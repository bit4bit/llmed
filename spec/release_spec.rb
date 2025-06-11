# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'


describe LLMed::Release do
  it 'merge only update' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code A
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", '#')
    rchange = LLMed::Release.load("#<llmed-code context='A' digest='abc' after='contextB'>
code AA
#</llmed-code>", '#')

    r1.merge!(rchange, {'A' => 'contextA'})
    expect(r1.content).to eq "#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>"
  end

  it 'merge append new context' do
    r1 = LLMed::Release.load("#<llmed-code context='A' digest='contextA' after='contextB'>
code AA
#</llmed-code>
#<llmed-code context='B' digest='contextB' after=''>
code B
#</llmed-code>", '#')
    rchange = LLMed::Release.load("#<llmed-code context='C' digest='contextC' after='contextB'>
code C
#</llmed-code>", '#')

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
end
