# encoding: UTF-8
require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
require 'watir-scroll'
require_relative './lib/cache_folder'
require_relative './lib/utils'
# require_relative 'console_potato'
# require_relative 'cron_job'
ActiveSupport::TimeZone[-8]

class DataPotato
  def initialize(path = nil)
    DB::ImageProgressRecord.create_new_from_path(path) if path
  end

  def format_csv_date_column
    working_csv = nil
    fun = CSV.generate do |csv|
      working_csv = CSV.read('Transaction Backload_2013.csv', :encoding => 'windows-1251:utf-8', headers: true)
      working_csv.each do |row|
        better_time = Utils::SalesForce.trevor_format_time(row["Gateway Date"])
        even_better_time = better_time.in_time_zone("Pacific Time (US & Canada)")
        final_time = Utils::SalesForce.format_time_to_soql(even_better_time)
        row["Gateway Date"] = final_time
        csv << row
      end
    end
    finished_csv = CSV.parse(fun)
    finished_csv.prepend working_csv.headers
    File.open('funtimes.csv', 'w') do |f|
      f << fun
    end
    binding.pry
  end


  def herp_derp
    DB::SMBRecord.all.each_with_index do |x,i| 
      next unless x.relative_path.match(/^_exits_backup/) || x.relative_path.match(/^\//)
      x.update(relative_path: x.relative_path.gsub('_exits_backup/', ''))
      x.update(relative_path: x.relative_path[1..-1]) if x.relative_path[0] == '/'
      puts " #{i} #{x.relative_path}" if i % 1000 == 0
    end
  end

  def populate_all_box_dbs
    @box_client = Utils::Box::Client.new
    folder  = @box_client.folder 11792669576
    folder2 = @box_client.folder 11793962443
    binding.pry
    process_folder
  end

  def process_folder(folder = nil)
    puts folder
    folder ||= CacheFolder.path.to_s
    cf = CacheFolder.new(folder)
    if cf.parent_type == :box && cf.type == :directory
      id         = cf.path.basename.to_s
      api_object = @box_client.folder(id)
      puts api_object.storage_object if api_object
    end
    Pathname.new(folder).each_child do |entity|
      process_folder(entity) if entity.directory?
    end
  end

  def test_box_db
    @box_client = Utils::Box::Client.new
    case_folder = @box_client.folder("7474301905")
    case_folder.folders.first.files
    puts 'hello'
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

w = WorkerPool.instance
count = w.tasks.size
dp =  DataPotato.new
dp.format_csv_date_column
binding.pry
puts dp
while w.tasks.size > 1 do
  sleep 1
  new_count = w.tasks.size
  if new_count == count
    kill_switch += 1
    puts 'kill switch at ' + kill_switch.to_s if kill_switch > 10
  else
    count = new_count
    kill_switch = 0
  end
  binding.pry if kill_switch > 60*5
  puts '\''*88
  puts "task size: #{w.tasks.size}"
  puts '\''*88
end
