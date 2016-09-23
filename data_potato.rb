require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
require 'watir-scroll'
require_relative './lib/cache_folder'
require_relative './lib/utils'
ActiveSupport::TimeZone[-8]

class DataPotato
  def initialize(path = nil)
    DB::ImageProgressRecord.create_new_from_path(path) if path
  end

  def populate_database
    # puts 'deleting old'
    # DB::ImageProgressRecord.destroy
    # puts 'finished deleting old'
    files = Dir.glob(CacheFolder.path + '**/*').delete_if do |entity|
      Pathname.new(entity).basename.to_s == 'meta.yml' ||
        Pathname.new(entity).directory?
    end
    files.map do |x|
      DB::ImageProgressRecord.create_new_from_path(x)
    end
  end
end

begin
  DataPotato.new.populate_database
rescue DataObjects::ConnectionError
  sleep 0.1
  retry
end
