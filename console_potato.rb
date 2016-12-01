require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
# require 'watir-scroll'
require_relative './lib/cache_folder'
require_relative './lib/utils'
# require_relative 'data_potato'
ActiveSupport::TimeZone[-8]

class ConsolePotato
  attr_reader :browser_tool, :dated_cache_folder
  def initialize(environment: 'production', offset_count: 0, project: 'box_population', id: nil)
    Utils.environment     = @environment = environment
    @id                   = id
    @sf_client            = Utils::SalesForce::Client.new
    @box_client           = Utils::Box::Client.new
    @worker_pool          = WorkerPool.instance
    # @browser_tool         = BrowserTool.new(2)
    @local_dest_folder    = Pathname.new('/Users/voodoologic/Sandbox/cache_folder')
    @formatted_dest_folder= Pathname.new('/Users/voodoologic/Sandbox/formatted_cache_folder')
    @dated_cache_folder   = determine_cache_folder
    @do_work              = true
    @download = @cached   = 0
    @smb_client           = SMB.new
    @meta                 = DB::Meta.first_or_create(project: project)
    @box_client           = Utils::Box::Client.new
    @offset_date          = Utils::SalesForce.format_time_to_soql(@meta.offset_date || Date.today - 3.years)
    @offset_count         = @meta.offset_counter
  end

  def produce_single_snapshot_from_scratch(id)
    opportunity = @sf_client.query(query: construct_opp_query(id: id))
    migrated_cloud_to_local_machine(opportunity)
    opportunity.cases.each do |sf_case|
      migrated_cloud_to_local_machine(sf_case)
    end
  end

  def produce_snapshot_from_scratch
    finance_folders.shuffle.each_slice(15).each do |finance_folders|
      cases = cases_from_finance_folders(finance_folders)
      opportunities = opps_from_finance_folder(finance_folders)
      opportunities.delete_if do |opp|
        %w(006610000066wSZAAY 006610000068R7qAAE 00661000008PuHQAA0  00661000005RPAjAAO 006610000068JjuAAE 006610000066jcyAAA).include? opp.id
      end
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
    # add_meta_to_folder(sobject, folder)
  end

  def sync_sobject_attachments_to_folder(sobject, folder)
    add_attachments_to_path(sobject, folder)
    remove_unwanted_files_from_cache(sobject, folder)
  end

  def remove_unwanted_files_from_cache(sobject, folder)
    return if sobject.attachments.nil?
    relevant_children(folder).each do |path|
      if !sobject.attachments.map(&:name).include?(path.basename.to_s)
        FileUtils.rm(path)
      end
    end

  end

  def update_database(box_folder_files, path)
    box_file_sha1s = box_folder_files.map(&:sha1)
    relevant_children(path).each do |file|
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

  def add_meta_to_folder(object, folder)
    file = File.open(folder + 'meta.yml', 'w+')
    meta = {}
    if object.type == 'Case'
      meta[:subject]      = object.subject
      meta[:id]           = object.id
      meta[:case_number]  = object.case_number
    elsif object.type == 'Opportunity'
      meta[:name]         = object.name
      meta[:id]           = object.id
    else #box
      meta[:name]         = object.name
      meta[:id]           = object.id
    end
    file.write(meta.to_yaml)
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

  def bc
    # @browser_tool.close
  end

  private

  def cases_from_finance_folders(finance_folders)
    cases = [finance_folders].flatten.select do |f| 
      f.name.match(/\d{8}/)
      sf_id_from_ff_name(f) =~ /500/
    end
    return cases if cases.empty?
    name_query = construct_cases_name_query(cases)
    id_query   = construct_cases_id_query(cases)
    if name_query
      name_results = @sf_client.custom_query(query: name_query)
    else
      name_results = []
    end
    if id_query
      id_results   = @sf_client.custom_query(query: id_query)
    else
      id_results = []
    end
    id_results.each do |id_r|
      name_results.push(id_r) unless name_results.map(&:id).include?(id_r.id)
    end
    name_results
  end

  def opps_from_finance_folder(finance_folders)
    opps = [finance_folders].flatten.select do |finance_folder|
      !sf_name_from_ff_name(finance_folder).try( :match, /^\d{8}/ )
      sf_id_from_ff_name(finance_folder) =~ /006/
    end
    return [] unless opps.present?
    name_query = construct_opps_name_query(opps)
    id_query   = construct_opps_id_query(opps)
    if name_query
      name_results = @sf_client.custom_query(query: name_query)
    else
      name_results = []
    end
    if id_query
      id_results   = @sf_client.custom_query(query: id_query)
    else
      id_results = []
    end
    id_results   = @sf_client.custom_query(query: id_query)
    id_results.each do |id_r|
      name_results.push(id_r) if name_results.size == 0 || name_results.map(&:id).include?(id_r.id)
    end
    name_results
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
    # add_meta_to_folder(parent_box_folder, local_parent_box_folder)
    parent_box_folder.folders.each do |box_folder|
      object_subfolder_path = create_box_folder(box_folder, local_parent_box_folder)
      box_folder_files = box_folder.files #keep from calling api
      sync_folder_with_box(box_folder_files, object_subfolder_path )
      update_database(box_folder_files, object_subfolder_path)
      # add_meta_to_folder(box_folder, object_subfolder_path)
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
      if !proposed_file.exist? || proposed_file.size == 0
        @not_there ||= 0
        @not_there += 1
        puts "\n"
        puts "Not there or zero: #{@not_there}"
        if @not_there % 100 == 0
          puts proposed_file
        end
        binding.pry if proposed_file.exist? && proposed_file.size == 0
        puts "\n"
        sf_attachment = @sf_client.custom_query(query: "SELECT id, body FROM Attachment where id = '#{a.id}'").first
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

  def add_sf_attachments_to_folder(object)
    case object
    when Pathname
      opp = salesforce_object_from_id_folder(object)
      binding.pry unless opp
      add_attachments_to_path(opp,folder)
    when Utils::SalesForce::Opportunity, Utils::SalesForce::Case
      add_attachments_to_path(object, folder)
    else
      binding.pry
      fail
    end
  end

  def salesforce_object_from_id_folder(folder)
    id = folder.split.last.to_s
    type = id[0] == 5 ? 'Case' : 'Opportunity'
    query = <<-EOF
      SELECT id, name,
      (SELECT id, Name FROM Attachments)
      FROM #{type}
      WHERE id = '#{id}'
    EOF
    @sf_client.custom_query(query: query).first
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
    path_file_sha1s = relevant_children(local_folder_path).map{|f| Digest::SHA1.hexdigest(f.read)}
    box_folder_files.each do |box_file|
      download_from_box( box_file, local_folder_path ) unless path_file_sha1s.include? box_file.sha1
    end
    relevant_children(local_folder_path).each do |file|
      file_sha1 = Digest::SHA1.hexdigest(file.read)
      if !box_file_sha1s.include?(file_sha1) || !box_folder_files.map(&:name).include?(file.basename.to_s)
        FileUtils.rm(file)
      end
    end
  end

  def download_from_box(file, path)
    proposed_file = Pathname.new(path) + (file.try(:name) || file.basename.to_s)
    if !proposed_file.exist? || (proposed_file.exist? && Digest::SHA1.hexdigest(proposed_file.read) != file.sha1) || proposed_file.size == 0
      local_file = File.new(proposed_file, 'w')
      binding.pry unless file.try(:id)
      local_file.write(@box_client.download_file(file))
      local_file.close
      @download += 1
      puts "Download number #{@download}"
    end
  end

  def relevant_children(path)
    path.each_child.select do |entity|
      entity.file? && entity.basename.to_s != 'meta.yml' && entity.basename.to_s != '.DS_Store'
    end
  end

  def construct_opps_name_query(group)
    names = []
    group.each do |opp|
      name_match = sf_name_from_ff_name(opp)
      names << name_match if name_match
    end
    return nil if names.empty?
    <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, opportunity__c FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity
        WHERE Name in #{names.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
    EOF
  rescue => e
    ap e.backtrace[0..5]
    binding.pry
    puts e
  end

  def construct_opps_id_query(group)
    ids = []
    group.each do |opp|
      id_match  = sf_id_from_ff_name(opp)
      ids << id_match if id_match
    end
    return nil if ids.empty?
    <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, opportunity__c FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity
        WHERE Id in #{ids.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
      EOF
  end

  def construct_cases_id_query(group)
    ids = []
    group.each do |opp|
      id_match  = sf_id_from_ff_name(opp)
      ids << id_match if id_match
    end
    return nil if case_ids.empty?
    <<-EOF
      SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
      (SELECT Id, Name FROM Attachments)
      FROM case
      WHERE Id in #{case_ids.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
    EOF
  end

  def construct_cases_name_query(group)
    case_numbers = group.select do |c|
      sf_case_number_from_ff_name(c)
    end
    return nil if case_numbers.empty?
    query = <<-EOF
        SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
        (SELECT Id, Name FROM Attachments)
        FROM case
        WHERE caseNumber in #{case_numbers.to_s.gsub('[','(').gsub(']',')').gsub("'", %q(\\\')).gsub('"', "'")}
      EOF
    query
  end

  def construct_opp_query(name: nil, id: nil )
    if id
      query = <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, opportunity__c, subject FROM cases__r),
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

  def query_frup(sobject)
    db = Utils::SalesForce::BoxFrupC.find_db_by_id(sobject.id)
    if db.present? && db.box__folder_id__c.present?
      db
    else
      @sf_client.custom_query(query:"SELECT id, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{sobject.id}'").first
    end
  end

  def poll_for_frup(sobject)
    kill_counter = 0
    sf_linked = query_frup(sobject)
    while sf_linked.nil? do
      # TODO the below line should work but it didin't
      # sobject.update({'Create_Box_Folder__c': true})
      puts 'sleeping until created'
      sleep 6
      kill_counter += 1
      break if kill_counter > 1
      sf_linked = query_frup(sobject)
    end
    if sf_linked
      sf_linked
    else
      document_offesive_object(sobject) 
      nil
    end
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

  def create_folder_through_browser(opp)
    @browser_tool.create_folder(opp)
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
      yield finance_folder if block_given? && finance_folder.name !~ /^(Case Template|Salesforce \- ReedHein \(Sandbox\))$/
      finance_folder.name !~ /^(Case Finance Template|Opportunity Finance Template)$/
    end
  rescue => e
    ap e.backtrace[0..5]
    binding.pry
    puts e
  end

  def determine_cache_folder
    if RbConfig::CONFIG['host_os'] =~ /darwin/
      Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s 
    else 
      Pathname.new('/home/doug/Sandbox/dated_cache_folder' ) + Date.today.to_s
    end
  end
end

