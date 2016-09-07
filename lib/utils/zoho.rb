require 'ruby_zoho'
require_relative 'zoho/base'
RubyZoho.configure do |config|
  config.api_key = CredService.creds.zoho.api_key
  config.cache_fields = true
end
