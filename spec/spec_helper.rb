# frozen_string_literal: true

require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  track_files 'lib/**/*.rb'
  minimum_coverage line: 100, branch: 100
end

require 'rspec'
require 'fileutils'
require 'tmpdir'
require 'dotenv'
require 'faraday'
require 'json'
require 'bitcoin'
require 'rubocop'
require 'dry/configurable'
require_relative '../lib/services/http_client'
require_relative '../lib/wallet'
require_relative '../lib/balance_checker'
require_relative '../lib/transaction_sender'
require_relative '../utils/script_logger'

RSpec.configure do |config|
  config.order = :random

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.around do |example|
    original_env = ENV.to_h
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
    end
    example.run
    ENV.replace(original_env)
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
end
