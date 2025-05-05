# frozen_string_literal: true

VCR.configure do |c|
  c.cassette_library_dir = 'spec/cassettes'
  c.hook_into :faraday
  c.allow_http_connections_when_no_cassette = true

  c.default_cassette_options = {
    record: :once,
    allow_unused_http_interactions: false
  }
end
