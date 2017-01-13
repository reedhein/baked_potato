require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
# require 'watir-scroll'
# require_relative 'data_potato'
ActiveSupport::TimeZone[-8]

class CloudMigrator
  attr_reader :browser_tool, :dated_cache_folder, :sf_client, :worker_pool
  attr_accessor :box_client
  def initialize(environment: :production, project: 'box_population', id: nil, user: nil, browsers: 2)
    Utils.environment     = @environment = environment.to_sym
    @user                 = user
    @id                   = id
    @sf_client            = Utils::SalesForce::Client.new(@user || DB::User.Doug, debug: true)
    @box_client           = Utils::Box::Client.new(@user || DB::User.Doug)
    @worker_pool          = WorkerPool.instance
    @browser_tool         = BrowserTool.new(browsers) if browsers > 0
    @local_dest_folder    = Pathname.new('/Users/voodoologic/Sandbox/cache_folder')
    @formatted_dest_folder= Pathname.new('/Users/voodoologic/Sandbox/formatted_cache_folder')
    @migration_folder     = Pathname.new('/home/doug/Sandbox/migration_move')
    @dated_cache_folder   = determine_cache_folder
    @do_work              = true
    @download = @cached   = 0
    @smb_client           = SMB.new
    @meta                 = DB::Meta.first_or_create(project: project)
    @box_client           = Utils::Box::Client.new
    @offset_date          = Utils::SalesForce.format_time_to_soql(@meta.offset_date || Date.today - 4.years)
    @offset_count         = @meta.offset_counter
  end

  def pull_down_box
    last_case_date = nil
    @sf_client.custom_query(query: derp) do |c|
      begin
        box_folder = c.box_folder(@box_client, @browser_tool)
        if box_folder.present? && assess_salvage(box_folder)
          @worker_pool.tasks.push Proc.new { migrate_files(c, box_folder) } 
        end
      rescue => e
        puts e
        next
      end
      last_case_date = c.created_date
      @meta.update(offset_date: DateTime.parse(last_case_date))
      @offset_date = DateTime.parse(last_case_date)
    end
  end

  def migrate_files(kase, box_folder)
    box_folder.folders.each do |folder|
      puts '*'*88
      puts folder.name
      puts '*'*88
      case folder.name.downcase
      when /exit complete/, /exit doc(?:\'?)s?/
        sf_file_names  = kase.exit_complete_docs_folder__r.first.attachments.map(&:name)
        folder.files.each do |file|
          if !sf_file_names.include?(file.name)
            local_file = gather_file(kase, folder, file)
            body = File.open(local_file).read
            kase.exit_complete_docs_folder__r.first.add_attachment(body:body , name: file.name)
          end
        end
      when /rh doc(?:\'?)s?/
        opp_query = construct_opp_query(id: kase.opportunity__c)
        opp = @sf_client.custom_query(query: opp_query).first
        sf_file_names  = opp.rh_docs_folder__r.first.attachments.map(&:name)
        folder.files.each do |file|
          if !sf_file_names.include?(file.name)
            local_file = gather_file(opp, folder, file)
            body = File.open(local_file).read
            opp.rh_docs_folder__r.first.add_attachment(body:body , name: file.name)
          end
        end
      when /ts doc(?:\'?)s?/
        sf_file_names  = kase.ts_docs_folder__r.first.attachments.map(&:name)
        folder.files.each do |file|
          if !sf_file_names.include?(file.name)
            local_file = gather_file(kase, folder, file)
            body = File.open(local_file).read
            kase.ts_docs_folder__r.first.add_attachment(body:body , name: file.name)
          end
        end
      end
    end
  rescue => e
    ap e.backtrace[0..5]
    puts e
    binding.pry
  end

  def gather_file(sobject, folder, box_file)
    local_file = DB::BoxFile.all(sha1: box_file.sha1, id: box_file.id)
    if local_file.empty?
      local_file = @migration_folder + sobject.id + folder.id + folder.name + box_file.name
      local_file.parent.mkpath
      download_from_box(box_file, local_file.parent)
    else
      binding.pry
    end
    local_file
  end

  def assess_salvage(box_folder)
    box_folder.folders.detect do |folder|
      folder.name.downcase.match /(((?:rh|ts) doc(?:\'?)s)|(?:exit complete))/
    end
  end

  def derp
    <<-EOF
      SELECT Id, createddate, opportunity__c,
      (SELECT Id FROM Exit_Complete_Docs_Folder__r),
      (SELECT Id FROM TS_Docs_Folder__r)
      FROM Case
      WHERE CreatedDate >= #{@offset_date}
      ORDER BY CreatedDate ASC
    EOF
  end

  def produce_single_snapshot_from_scratch(id)
    if id.match(/^500/)
      s_object = @sf_client.custom_query(query: construct_case_query(id: id)).first
      opp_snapshot_from_scratch(s_object.opportunity)
    else
      s_object = @sf_client.custom_query(query: construct_opp_query(id: id)).first
      opp_snapshot_from_scratch(s_object)
    end
  end

  def produce_snapshot_from_case_number(case_number)
    sf_case = @sf_client.custom_query(query: construct_case_query_from_case_number(case_number)).first
    opp_snapshot_from_scratch(sf_case.opportunity)
    puts sf_case
    sf_case
  end

  def opp_snapshot_from_scratch(opportunity)
    folder = create_folder(opportunity)
    populate_local_box_attachments_for_sobject_and_path(opportunity, folder)
    migrated_cloud_to_local_machine(opportunity)
    opportunity.cases.each do |sf_case|
      migrated_cloud_to_local_machine(sf_case)
      populate_local_box_attachments_for_sobject_and_path(sf_case, folder)
    end
  rescue =>e
    ap e.backtrace
    binding.pry
    puts 'derp'
  end

  def produce_snapshot_from_scratch
    finance_folders.shuffle.each_slice(15).each do |finance_folders|
      cases = cases_from_finance_folders(finance_folders)
      opportunities = opps_from_finance_folder(finance_folders)
      opportunities.each do |opportunity|
        @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(opportunity) }
        opportunity.cases.each do |sf_case|
          @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(sf_case) }
        end
      end
      cases.each do |sf_case|
        @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(sf_case) }
      end
    end
  end

  def sync_s_drive
    # @worker_pool.tasks.push Proc.new {  @smb_client.cache }
    # @smb_client.sync
    @smb_client.improved_sync
  end

  def migrated_cloud_to_local_machine(sobject)
    folder = create_folder(sobject)
    sync_sobject_attachments_to_folder(sobject, folder)
    populate_local_box_attachments_for_sobject_and_path(sobject, folder)
  end

  def sync_sobject_attachments_to_folder(sobject, folder)
    add_attachments_to_path(sobject, folder)
    remove_unwanted_files_from_cache(sobject, folder)
  end

  def remove_unwanted_files_from_cache(sobject, folder)
    return if sobject.attachments.nil?
    folder.each_child.select{|e| e.file?}.each do |path|
      if !sobject.attachments.map(&:name).include?(path.basename.to_s)
        FileUtils.rm(path)
      end
    end
  end

  def update_database(box_folder_files, path)
    box_file_sha1s = box_folder_files.map(&:sha1)
    path.each_child.select{|e| e.file?}.each do |file|
      proposed_file = (path + file)
      begin
        file_sha1 = Digest::SHA1.hexdigest(file.read)
        if box_file_sha1s.include?(file_sha1)
          @cached += 1
          puts @cached.to_s + ' ' + file.inspect
          box_file = box_folder_files.detect{|b| b.sha1 == file_sha1}
          ipr =  DB::ImageProgressRecord.find_from_path(proposed_file)
          ipr.filename  = proposed_file.basename.to_s
          ipr.parent_id = proposed_file.parent.basename.to_s
          ipr.file_id = box_file.id
          ipr.sha1    = file_sha1
          binding.pry unless ipr.save
        end
      rescue DataObjects::ConnectionError
        puts 'db error'
        sleep 0.1
        retry
      rescue  => e
        ap e.backtrace
        binding.pry
      end
    end
  end

  def create_folder(sobject)
    todays_backup      = @dated_cache_folder
    if sobject.type    == 'Case'
      opp_folder       = todays_backup + sobject.opportunity_id
      cases_folder     = opp_folder + 'cases'
      case_folder      = cases_folder + sobject.id
      case_folder.mkpath
      case_folder
    elsif sobject.type  == 'Opportunity'
      opp_folder       = todays_backup + sobject.id
      opp_folder.mkpath
      opp_folder
    else
      binding.pry
    end
  end

  def construct_case_query_from_case_number(case_number)
    <<-EOF
      SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
      (SELECT Id, Name FROM Attachments)
      FROM case
      WHERE caseNumber = '#{case_number}'
    EOF
  end

  private

  def cases_from_finance_folders(finance_folders)
    cases = [finance_folders].flatten.select{|f| f.name.match(/\d{8}Finance/)}
    return cases if cases.empty?
    query = construct_cases_query(cases)
    @sf_client.custom_query(query: query)
  rescue => e
    ap e.backtrace[0..5]
    if Utils.environment == :production
      raise e
    else
      binding.pry
    end
    puts e
  end

  def opps_from_finance_folder(finance_folders)
    opps = [finance_folders].flatten.select do |finance_folder|
      sf_name_from_ff_name(finance_folder)
    end
    return [] unless opps.present?
    query = construct_opps_query(opps)
    @sf_client.custom_query(query: query)
  rescue => e
    ap e.backtrace[0..5]
    binding.pry
    puts e
  end

  def opp_from_finance_folder(finance_folder)
    sf_name  = sf_name_from_ff_name(finance_folder)
    query = construct_opp_query(name: sf_name)
    @sf_client.custom_query(query: query).first
  end

  def populate_local_box_attachments_for_sobject_and_path(sobject, path)
    parent_box_folder = get_parent_box_folder(sobject)
    return unless parent_box_folder
    local_parent_box_folder = create_box_folder(parent_box_folder, path)
    parent_box_folder_files = parent_box_folder.files #keep from calling api
    sync_folder_with_box(parent_box_folder_files , local_parent_box_folder)
    update_database(parent_box_folder_files, local_parent_box_folder)
    parent_box_folder.folders.each do |box_folder|
      object_subfolder_path = create_box_folder(box_folder, local_parent_box_folder)
      box_folder_files = box_folder.files #keep from calling api
      sync_folder_with_box(box_folder_files, object_subfolder_path )
      update_database(box_folder_files, object_subfolder_path)
    end
  end

  def create_box_folder(box_folder, path)
    local_folder = path + box_folder.id
    local_folder.mkpath
    local_folder
  end

  def get_parent_box_folder(sobject)
    kill_counter = 0
    sf_linked = poll_for_frup(sobject)
    parent_box_folder = nil
    return unless sf_linked
    begin
      parent_box_folder = @box_client.folder_from_id( sf_linked.box__folder_id__c )
    rescue Boxr::BoxrError => e
      return nil if e.to_s =~ /404: (Not Found|Item is trashed)/
      # binding.pry if e.to_s =~ /405/
      visited= false
      ap e.backtrace
      puts e
      visit_page_of_corresponding_id(sobject.id) unless visited == true
      visited= true
      sleep 5
      kill_counter += 1
      retry if kill_counter < 3
    end
    parent_box_folder
  end

  def add_attachments_to_path( sobject, folder )
    attachments = sobject.attachments
    return unless attachments.present? #guard against nil or []
    attachments.each_with_index do |a, i|
      proposed_file = folder + a.name
      relative_path = proposed_file.to_s.gsub(@dated_cache_folder, '')[1..-1]
      binding.pry if relative_path.nil?
      begin
        if !proposed_file.exist? || proposed_file.size == 0
          @not_there ||= 0
          @not_there += 1
          puts "\n"
          puts "Not there or zero: #{@not_there}"
          if @not_there % 100 == 0
            puts proposed_file
          end
          puts "\n"
          sf_attachment = @sf_client.custom_query(query: "SELECT id, body FROM Attachment where id = '#{a.id}'").first
          next unless sf_attachment #deleted
          ipr = DB::ImageProgressRecord.find_from_path(relative_path)
          ipr.file_id = sf_attachment.id if ipr.file_id.nil?
          file_body   = sf_attachment.api_object.Body
          ipr.sha1    = Digest::SHA1.hexdigest(file_body) if ipr.sha1.nil?
          File.open(proposed_file, 'w') do |f|
            f.write(file_body)
          end
          binding.pry unless ipr.save
        else #it exists and we are doing temporary sha and id migration
          ipr = DB::ImageProgressRecord.find_from_path(relative_path)
          if  proposed_file.exist? && (ipr.file_id.nil? || ipr.sha1.nil?)
            @there_but_not_fleshed_out ||= 0
            @there_but_not_fleshed_out  += 1
            puts "\n"
            puts "Not fleshed out #{@there_but_not_fleshed_out}"
            puts "file_id: #{ipr.file_id}"
            puts "sha1: #{ipr.sha1}"
            puts "\n"
            ipr.file_id   = a.id
            ipr.sha1      = Digest::SHA1.hexdigest(proposed_file.read)
            binding.pry unless ipr.save
          end
        end
      rescue Faraday::ConnectionFailed => e
        puts e
        retry
      rescue DataObjects::ConnectionError
        puts 'db error'
        sleep 0.1
        retry
      rescue => e
        ap e.backtrace
        binding.pry
      end
    end
  end


  def visit_page_of_corresponding_id(id)
    # @browser_tool.queue_work do |agent|
    #   agent.goto('https://na34.salesforce.com/' + id)
    # end
  end

  def visit_page_of_corresopnding_folder(folder)
    folder_id = folder.split.last.to_s
    agent = @browser_tool.agents.first
    agent.goto('https://na34.salesforce.com/' + folder_id)
  end

  def find_directory_in_list(dir, list)
    list.detect{ |path| path.split.last.to_s == dir.split.last.to_s }
  end

  def file_present?(file, path)
    (path + file.name).exist?
  end

  def work_completed?(file, dest_path)
    Pathname.new([dest_path , file.name].join('/')).exist?
  end

  def sync_folder_with_box(box_folder_files, local_folder_path)
    box_file_sha1s  = box_folder_files.map(&:sha1)
    path_file_sha1s = local_folder_path.each_child.select{ |e| e.file? }.map{|f| Digest::SHA1.hexdigest(f.read)}
    box_folder_files.each do |box_file|
      download_from_box( box_file, local_folder_path ) unless path_file_sha1s.include? box_file.sha1
    end
    local_folder_path.each_child.select{|e| e.file? }.each do |file|
      file_sha1 = Digest::SHA1.hexdigest(file.read)
      if !box_file_sha1s.include?(file_sha1) || !box_folder_files.map(&:name).include?(file.basename.to_s)
        FileUtils.rm(file)
      end
    end
  rescue => e
    puts e
    binding.pry
    puts e
  end

  def download_from_box(file, path)
    proposed_file = Pathname.new(path) + (file.try(:name) || file.basename.to_s)
    if !proposed_file.exist? || (proposed_file.exist? && Digest::SHA1.hexdigest(proposed_file.read) != file.sha1) || proposed_file.size == 0
      local_file = File.new(proposed_file, 'w')
      local_file.write(@box_client.download_file(file))
      local_file.close
      @download += 1
      puts "Download number #{@download}"
    end
  end

  def construct_opps_query(opp_box_folder_names)
    names = opp_box_folder_names.map do |opp|
      sf_name_from_ff_name(opp)
    end
    <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, opportunity__c FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity
        WHERE Name in #{names.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
    EOF
  end

  def construct_cases_query(groups)
    case_numbers = groups.map do |c|
      sf_case_number_from_ff_name(c)
    end
    query = <<-EOF
        SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
        (SELECT Id, Name FROM Attachments)
        FROM case
        WHERE caseNumber in #{case_numbers.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
      EOF
    query
  end

  def construct_case_query(id: nil)
    fail 'need id to query case' unless id
    query = <<-EOF
      SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
      (SELECT Id, Name FROM Attachments)
      FROM case
      WHERE id = '#{id}'
    EOF
    query
  end

  def construct_opp_query(name: nil, id: nil )
    if id
      query = <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT Id FROM RH_Docs_Folder__r),
          (SELECT Id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, opportunity__c, subject FROM cases__r),
          (SELECT Id, Name FROM Attachments)
          FROM Opportunity
          WHERE id = '#{id}'
        EOF
    elsif name
      query = <<-EOF
        SELECT Name, Id, createdDate, Opportunity__c
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity WHERE Name = '#{name.gsub("'", %q(\\\'))}'
      EOF
    elsif @offset_date
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity
        CreatedDate >= #{@offset_date}
        ORDER BY CreatedDate ASC
      EOF
    else
      fail 'need a name or id'
    end
    query
  end

  def query_frup(sobject, debug: false)
    db = Utils::SalesForce::BoxFrupC.find_db_by_id(sobject.id)
    if db.present? && db.box__folder_id__c.present? && db.created_date && DateTime.parse(db.created_date) < ( DateTime.today - 3.days )
      db
    else
      @sf_client.custom_query(query:"SELECT id, createddate, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{sobject.id}' LIMIT 1")
    end
  end

  def poll_for_frup(sobject)
    kill_counter = 0
    sf_linked = query_frup(sobject)
    while sf_linked.nil? do
      # TODO the below line should work but it didin't
      # sobject.update({'Create_Box_Folder__c': true})
      # create_folder_through_browser(sobject)
      @browser_tool.visit_salesforce(sobject)
      puts 'sleeping until created'
      sleep 6
      kill_counter += 1
      break if kill_counter > 2
      sf_linked = query_frup(sobject)
    end
    if sf_linked
      sf_linked.first
    else
      document_offesive_object(sobject) 
      nil
    end
  rescue => e
    ap e.backtrace
    binding.pry
    puts 'pull_for_frup'
  end

  def document_offesive_object(sobject)
    offensive_file        = File.open('offensive_ids.txt', 'a+')
    offensive_file_string = offensive_file.read
    off_file = offensive_file_string.split('\n')
    if !off_file.include?(sobject.id)
      offensive_file << sobject.id + "\n"
    end
    offensive_file.close
  end

  def create_folder_through_browser(sobject)
    @browser_tool.create_folder(sobject)
  end

  def sf_name_from_ff_name(ff)
    match = ff.name.match(/(?<opp_name>.+)\ -\ Finance$/) || ff.name.match(/(?<opp_name>.+)\ -\ (\d+)Finance/)
    puts ff.name
    match.try( :[], :opp_name )
  rescue => e
    ap e.backtrace
    binding.pry
  end

  def sf_case_number_from_ff_name(ff)
    match = ff.name.match(/(.+)\ -\ (?<case_number>\d+)Finance/) || ff.name.match(/^(?<case_number>\d{8,}) - Finance/)
    match.try( :[], :case_number )
  rescue => e
    ap e.backtrace
    binding.pry
  end
  
  def sf_id_from_ff_name(ff)
    result = ff.name.match(/ - Finance - (?<id>(?:500|006)\w{15})/)
    result.nil? ? nil : result[:id]
  end

  def finance_folders(&block)
    @box_client.folder("7811715461").folders.select do |finance_folder|
      yield finance_folder if block_given? && finance_folder.name !~ /^(Case Finance Template|Opportunity Finance Template)$/
      finance_folder.name !~ /^(Case Finance Template|Opportunity Finance Template)$/
    end
  end

  def determine_cache_folder
    if RbConfig::CONFIG['host_os'] =~ /darwin/ 
      Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s 
    else 
      Pathname.new('/home/doug/Sandbox/dated_cache_folder' ) + Date.today.to_s
    end
  end
end

