# frozen_string_literal: true

require 'bitcoin'
require_relative '../spec_helper'
require_relative '../../lib/wallet'

RSpec.describe Wallet do
  describe Wallet::Loader do
    let(:loader) { described_class.new }
    let(:valid_wif) { 'cSzA6p6BUZfgkHVdU43zmKYnL8isvsbxPPd3dW6RqNN7BPopu7eF' }

    context 'when key exists in ENV' do
      before do
        allow(ENV).to receive(:fetch).with('PRIVATE_KEY_WIF', nil).and_return(valid_wif)
      end

      it 'returns valid address' do
        expect(loader.key.to_p2tr).to eq('tb1pff08xc4vd6ctn764zjudz4aajxc2xcj8y7u6qy0dzkytxt73f0zqxxv3xk')
      end
    end
  end
end
