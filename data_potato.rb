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
    files = Dir.glob(CacheFolder.path + '**/*').delete_if do |entity|
      Pathname.new(entity).split.last.to_s == 'meta.yml' ||
        Pathname.new(entity).directory?
    end
    derp = files.map do |x|
      DB::ImageProgressRecord.create_new_from_path(x)
    end
    binding.pry
  end
end
