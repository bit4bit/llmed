# Copyright 2025 Jovany Leandro G.C <bit4bit@riseup.net>
# frozen_string_literal: true

require 'llmed'


describe LLMed::Release do
  it 'merge releases' do
    r1 = LLMed::Release.load("<llmed-code context='A' digest='abc'>code A</llmed-code>
<llmed-code context='B' digest='abc'>code B</llmed-code>")
    rchange = LLMed::Release.load("<llmed-code context='A' digest='abc'>code AA</llmed-code>")

    r1.merge!(rchange, '#')
    expect(r1.content).to eq "<llmed-code context='A' digest='abc'>code AA</llmed-code>
<llmed-code context='B' digest='abc'>code B</llmed-code>"
  end
end
