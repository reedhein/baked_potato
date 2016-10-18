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

  def get_files_from_cache_folder
    Dir.glob(CacheFolder.path + '**/*').delete_if.with_index do |entity, i|
      puts i if i % 100 == 0
      Pathname.new(entity).basename.to_s == 'meta.yml' ||
        Pathname.new(entity).basename.to_s == '.DS_Store' ||
        Pathname.new(entity).directory?
    end
  end

  def populate_parent_id
    DB::ImageProgressRecord.all.each_with_index do |ipr, i|
      puts i if i % 100 == 0
      if ipr.filename == nil
        ipr.update(filename: ipr.full_path.basename.to_s)
      end
    end
  end

  def create_db_for_file_strings(files)
    files.map.with_index do |file_string, i|
      puts i  if i % 100 == 0
      file_path = Pathname.new(file_string)
      ipr = DB::ImageProgressRecord.find_from_path(file_path)
      ipr.save if ipr.new?
      ipr
    end
  end

  def add_meta_to_db_records(records)
    records.each_with_index do |ipr, i|
      puts i if i % 100 == 0
      ipr.sha1 = Digest::SHA1.hexdigest(ipr.full_path.read) unless ipr.sha1
      id = ipr.file_id || CacheFolder.new(ipr.full_path).file_id
      if id.nil?
        ipr.destroy
        next
      end
      ipr.file_id  = id
      ipr.date = Date.today.to_s if ipr.date != Date.today.to_s
      ipr.save
    end
  end

  def destroy_all
    puts 'deleting old'
    DB::ImageProgressRecord.destroy
    puts 'finished deleting old'
  end
end

begin
  dp =  DataPotato.new
  dp.populate_parent_id
  # dp.destroy_all
  # files = dp.get_files_from_cache_folder
  # records = dp.create_db_for_file_strings(files)
  # binding.pry
  # dp.add_meta_to_db_records(records)
  puts 'awesome'
rescue DataObjects::ConnectionError
  puts 'db error'
  sleep 0.1
  retry
rescue =>e
  puts e
  ap e.backtrace
  binding
  puts 'awesome'
end
