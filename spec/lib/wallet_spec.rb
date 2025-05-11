# frozen_string_literal: true

require_relative '../spec_helper'

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

  describe Wallet::Generator do
    let(:generator) { described_class.new }
    let(:key) { instance_double(Bitcoin::Key) }
    let(:key_wif) { 'key_wif' }
    let(:project_root) { File.expand_path('../..', __dir__) }
    let(:env_path) { File.join(project_root, '.env') }

    before do
      allow(Bitcoin::Key).to receive(:generate).and_return(key)
      allow(key).to receive_messages(to_wif: key_wif, to_p2tr: 'key_p2tr_bar')
      allow(File).to receive(:write).with('keys/private_key', key_wif).and_return(true)
      allow(File).to receive(:exist?).with('<STDOUT>').and_return(true)
      allow(File).to receive(:exist?).with(env_path).and_return(true)
      allow(File).to receive(:readlines).with(env_path).and_return([])
      allow(File).to receive(:write).with(env_path, '')
    end

    context 'when generating a new wallet' do
      it 'does not raise an error' do
        expect { generator.call }.not_to raise_error
      end
    end
  end
end
