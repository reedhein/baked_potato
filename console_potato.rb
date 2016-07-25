require 'pry'
require 'active_support/time'
require 'awesome_print'
require_relative '../global_utils/global_utils'
ActiveSupport::TimeZone[-8]

class ConsolePotato
  attr_reader :browser_tool
  def initialize(environment: 'production', offset_count: 0, project: 'box_population', id: nil)
    Utils.environment    = @environment = environment
    @id                  = id
    @sf_client           = Utils::SalesForce::Client.instance
    @box_client          = Utils::Box::Client.instance
    @browser_tool        = BrowserTool.new
    @local_source_folder = Pathname.new('/Users/voodoologic/Sandbox/backup/Opportunity')
    @local_dest_folder   = Pathname.new('/Users/voodoologic/Sandbox/cache_folder')
    @do_work             = true
    @download = @cached  = 0
    @meta                = DB::Meta.first_or_create(project: project)
    @offset_count        = @meta.offset_counter
  end

  def process_work_queue
    begin
      @total = 0
      while @do_work == true do
        @do_work   = false
        @processed = 0
        finance_folders do |financial_folder|
          boxfolder_db = DB::BoxFolder.first_or_create(box_id: financial_folder.id)
          next if boxfolder_db.download_complete
          next if financial_folder.name == "Case Finance Template"
          next if financial_folder.name == "Opportunity Finance Template"
          sf_name  = sf_name_from_ff_name(financial_folder)
          query = construct_query(sf_name)
          opportunity = @sf_client.custom_query(query: query).first
          next unless opportunity
          @meta.offset_date = Utils::SalesForce.soql_time_to_datetime(opportunity.created_date)
          @meta.save
          dest_path = update_cache_folder(opportunity, financial_folder)
          next if dest_path == false
          financial_folder.files.each do |file|
            puts "processing file: #{file.name}"
            boxfile_db = DB::BoxFile.first_or_create(box_id: file.id)
            next if boxfile_db.download_complete
            begin
              if work_completed?(file, dest_path)
                next
              elsif case_file_path = exist_locally?(opportunity, file)
                source_file = get_local_copy(case_file_path)
                preserve_indexed_name!(source_file, file)
              else
                source_file = download_from_box(file)
              end
            rescue => e
              ap e.backtrace
              binding.pry
            end
            puts File.basename(source_file)
            copy_file_to_cache_folder(dest_path, source_file)
            boxfile_db.download_complete = true
            boxfile_db.save
          end
          boxfolder_db.download_complete = true
          boxfolder_db.save
        end

      end
    end
  end

  private

  def preserve_indexed_name!(source_file, file)
    binding.pry
    File.rename(source_file, file.name)
  end

  def work_completed?(file, dest_path)
    Pathname.new([dest_path , file.name].join('/')).exist?
  end

  def download_from_box(file)
    local_file = File.new("/tmp/#{file.name}", 'w')
    local_file.write(@box_client.download_file(file))
    local_file.close
    @download += 1
    puts "Download number #{@download}"
    local_file
  end

  def get_local_copy(file_path)
    @cached += 1
    puts "Cached number #{@cached}"
    File.new get_source_file(file_path)
  end

  def construct_query(sf_name)
    if @id
      query = " SELECT Name, Id, createdDate, (SELECT Id, Name FROM Attachments) FROM Opportunity WHERE id = '#{@id}'"
    elsif @offset_date
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity 
        CreatedDate >= #{@offset_date} 
        ORDER BY CreatedDate ASC
      EOF
    else
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity WHERE Name = '#{sf_name.gsub("'", %q(\\\'))}'
      EOF
    end
    query
  end

  def update_cache_folder(opportunity, ff)
    sf_linked = query_frup(opportunity).first
    if sf_linked.nil?
      if create_folder_through_browser(opportunity)
        sf_linked = poll_for_frup(opportunity)
      else
        return false
      end
    end
    cache_path_name = [ ff.id, opportunity.id, sf_linked.box__folder_id__c ].join('_')
    path = Pathname.new(@local_dest_folder) + cache_path_name
    path.mkpath
    path
  end

  def exist_locally?(opp , file)
    file_name_minus_index = file.name.gsub(/^\d{1,3}-/, '')
    opp_file_path = Pathname.new([@local_source_folder , "Opportunity", opp.id , file_name_minus_index].join('/'))
    return opp_file_path if opp_file_path.exist?
    opp.cases.each do |opp_case|
      _case_path = @local_source_folder.to_s.split('/')
      _case_path << 'Cases'
      case_path =  _case_path.join('/')
      file_path = Pathname.new(case_path) + opp_case.id + file_name_minus_index
      puts "found local cache" if file_path.exist?
      return file_path if file_path.exist?
    end
    nil
    # file_path = Pathname.new(@local_source_folder) + opp.id + file.name
    # file_path.exist?
  end

  def get_source_file(local_file_path)
    sf_object_id   = sf_object_id_from_path(local_file_path)
    sf_object_type = sf_object_type_from_path(local_file_path)
    binding.pry
    file_path = Pathname.new([@local_source_folder , sf_object_type, sf_object_id , File.basename(local_file_path)].join('/'))
    binding.pry
    file_path if file_path.exist?
  end

  def sf_object_id_from_path(path)
    path.to_s.split('/')[-2]
  end

  def sf_object_type_from_path(path)
  end

  def copy_file_to_cache_folder(path, file)
    puts "copying file: #{File.basename(file)} to path: #{path.to_s}"
    begin
      binding.pry if File.dirname(file) !~ /tmp/
      FileUtils.cp(file, path)
      if File.basename(file).split('/')[1] == 'tmp'
        puts "removing temp file: #{File.path(file)}"
        FileUtils.rm(file)
      end
    rescue => e
      puts e.backtrace
      binding.pry
    end
  end

  def query_frup(opportunity)
    @sf_client.custom_query(query:"SELECT id, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{opportunity.id}'")
  end

  def poll_for_frup(opp)
    sf_linked = nil
    while sf_linked.nil? do
      sleep 6
      sf_linked = query_frup(opp).first
    end
  end

  def create_folder_through_browser(opp)
    @browser_tool.create_folder(opp)
  end

  def find_old_file(path, sf_link_record)
    Pathname.new( [@local_source_folder, sf_link_record.box__object_name__c, sf_link_record.box__record_id__c].join('/') )
  end

  def guard_against_multiple_records(sf_linked)
    # there are some join records that are duplicates
    # probably due to integration development
    sf_linked.map do |sf|
      {
        folder_id: sf.box__folder_id__c,
        record_id: sf.box__record_id__c
      }
    end.uniq.count
  end

  def sf_name_from_ff_name(ff)
    begin
      match = ff.name.match(/(.+)\ -\ Finance$/)
      match[1]
    rescue => e
      ap e.backtrace
      binding.pry
    end
  end

  def finance_folders
    @box_client.folder("7811715461").folders.delete_if do |finance_folder|
      completed_db      = DB::BoxProgressRecord.first(box_id: finance_folder.id, object_type: 'folder', complete: true)
      db_finance_folder = DB::BoxProgressRecord.first_or_create(box_id: finance_folder.id, object_type: 'folder')
      finance_folder.storage_object = db_finance_folder
      yield finance_folder if block_given? && !completed_db && finance_folder.name !~ /\d{8}\ -\ Finance$/
      completed_db && finance_folder.name !~ /\d{8}\ -\ Finance$/
    end
  end
end
cp = ConsolePotato.new().process_work_queue
begin
ensure
  binding.pry
  cp.browser_tool.close
end
