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

  def remove_meta_yml
    Dir.glob('/home/doug/Sandbox/dated_cache_folder/2016-10-31/**/*').each do |entity|
      path = Pathname.new(entity)
      puts path
      FileUtils.rm(path) if path.basename == 'meta.yml'
    end
  end

  def name_case_attribution
    #this will remove the need for meta.yml
    @sf_client = Utils::SalesForce::Client.new
    DB::SalesForceProgressRecord.all(object_type: 'Case').each_slice(50).with_index do |records, i|
      begin
        puts i
        ids = records.map(&:sales_force_id)
        # id = record.sales_force_id
        @sf_client.custom_query(query: "SELECT id, casenumber, subject FROM Case where id in #{ids.to_s.gsub('[','(').gsub(']',')').gsub('"', "'")}")
      rescue => e
        ap e.backtrace
        puts e
        binding.pry
      end
    end
  end

  def name_opp_attribution
    #this will remove the need for meta.yml
    @sf_client = Utils::SalesForce::Client.new
    DB::SalesForceProgressRecord.all(object_type: 'Opportunity').each_slice(50).with_index do |records, i|
      begin
        puts i
        ids = records.map(&:sales_force_id)
        # id = record.sales_force_id
        @sf_client.custom_query(query: "SELECT id, name FROM Opportunity where id in #{ids.to_s.gsub('[','(').gsub(']',')').gsub('"', "'")}")
      rescue => e
        ap e.backtrace
        puts e
        binding.pry
      end
    end
  end

  def relative_path
    binding.pry
    DB::ImageProgressRecord.all.batch(1000).each_with_index do |record, i|
      relative_path = record.full_path.to_s.split('/')[6..-1].join('/')
      record.relative_path = relative_path
      if i % 1000 == 0
        puts i
        puts relative_path
      end
      record.save
    end
  end

  def glob_test
    binding.pry
    hello = Dir.glob('/home/doug/Sandbox/s_drive/Client Management/REED HEIN and ASSOCIATES/_Timeshare Exits/**/*')
  end

  def local_migration
    DB::SMBRecord.all.batch(1000).each_with_index do |record, i|
      path = record.path
      relative_path = path.split('/')[4..-1].join('/')
      record.local_path = '/home/doug/Sandbox/s_drive/'
      record.network_path = '/Client Management/REED HEIN and ASSOCIATES/_Timeshare Exits/'
      record.relative_path = relative_path
      super_path = record.local_path.chomp('/') + record.network_path + record.relative_path
      record_path =  Pathname.new(super_path)
      if record_path.exist?
        record_path.file? ? record.type = :file : record.type = :directory
        record.save
      else
        record.destroy
      end
      puts i if i % 100 == 0
    end
  end

  def add_date_to_smb_records
    DB::SMBRecord.all.batch(1000).each_with_index do |record,i|
      puts i if i % 1000 == 0
      record.update(date: Date.today.to_s) if record.date.nil?
    end
  end

  def delete_dumb_records
    DB::SMBRecord.all.batch(1000).each_with_index do |record, i|
      puts i
      # binding.pry if i % 1000 == 0
      if record.path[74] == record.path[75]
        delete = false
        puts record.path
        # binding.pry if record.path =~ /2015/
        puts record.name
        record.destroy  if delete
      end
    end
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
  dp.remove_meta_yml
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
