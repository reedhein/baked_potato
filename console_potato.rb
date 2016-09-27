require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
require 'watir-scroll'
require_relative './lib/cache_folder'
require_relative './lib/utils'
require_relative 'data_potato'
ActiveSupport::TimeZone[-8]

class ConsolePotato
  attr_reader :browser_tool
  def initialize(environment: 'production', offset_count: 0, project: 'box_population', id: nil)
    Utils.environment     = @environment = environment
    @id                   = id
    @sf_client            = Utils::SalesForce::Client.instance
    @box_client           = Utils::Box::Client.instance
    @worker_pool          = WorkerPool.instance
    @browser_tool         = BrowserTool.new(1)
    @local_dest_folder    = Pathname.new('/Users/voodoologic/Sandbox/cache_folder')
    @formatted_dest_folder= Pathname.new('/Users/voodoologic/Sandbox/formatted_cache_folder')
    @dated_cache_folder   = RbConfig::CONFIG['host_os'] =~ /darwin/ ? Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s : Pathname.new('/home/doug/Sandbox/cache_folder' ) + Date.today.to_s
    @do_work             = true
    @download = @cached  = 0
    @meta                = DB::Meta.first_or_create(project: project)
    @offset_date         = Utils::SalesForce.format_time_to_soql(@meta.offset_date || Date.today - 3.years)
    @offset_count        = @meta.offset_counter
  end

  def process_work_queue
    begin
      @total = 0
      while @do_work == true do
        @do_work   = false
        @processed = 0
        finance_folders do |financial_folder|
            opportunity = opp_from_finance_folder(finance_folder)
            next unless opportunity
            next if %w(006610000066wSZAAY 006610000068R7qAAE 00661000008PuHQAA0  00661000005RPAjAAO 006610000068JjuAAE 006610000066jcyAAA).include? opp.id
            make_file(opportunity)
            make_xml(opportunity)
            make_db(opportunity)
            make_box(opportunity)
            make_native(opportunity)
            opportunity.cases.each do |sf_case|
              make_file(sf_case)
              make_xml(sf_case)
              make_db(sf_case)
              make_box(sf_case)
              make_native(sf_case)
            end
        end
      end
    end
  end

  def produce_snapshot_from_scratch
    finance_folders.each_slice(10) do |finance_folders|
      cases = cases_from_finance_folders(finance_folders)
      opportunities = opps_from_finance_folder(finance_folders)
      opportunities.delete_if do |opp|
        %w(006610000066wSZAAY 006610000068R7qAAE 00661000008PuHQAA0  00661000005RPAjAAO 006610000068JjuAAE 006610000066jcyAAA).include? opp.id
      end
      opportunities.each do |opportunity|
        @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(opportunity) }
        # migrated_cloud_to_local_machine(opportunity)
        opportunity.cases.each do |sf_case|
          @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(sf_case) }
        end
      end
      cases.each do |sf_case|
        @worker_pool.tasks.push Proc.new { migrated_cloud_to_local_machine(sf_case) }
        # migrated_cloud_to_local_machine(sf_case)
      end
    end
  end

  def migrated_cloud_to_local_machine(sobject)
    folder = create_folder(sobject)
    add_attachments_to_path(sobject, folder)
    populate_local_box_attachments_for_sobject_and_path(sobject, folder)
    add_meta_to_folder(sobject, folder)
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
    @browser_tool.close
  end

  private

  def cases_from_finance_folders(finance_folders)
    cases = finance_folders.select{|f| f.name.match(/\d{8}/)}
    return cases if cases.empty?
    query = construct_cases_query(cases)
    @sf_client.custom_query(query: query)
  end

  def opps_from_finance_folder(finance_folders)
    opps = finance_folders.select do |finance_folder|
      !sf_name_from_ff_name(finance_folder).match(/^\d{8}/)
    end
    return [] unless opps.present?
    query = construct_opps_query(opps)
    @sf_client.custom_query(query: query)
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
    sync_folder_with_box(parent_box_folder, local_parent_box_folder)
    add_meta_to_folder(parent_box_folder, local_parent_box_folder)
    parent_box_folder.folders.each do |box_folder|
      object_subfolder_path = create_box_folder(box_folder, local_parent_box_folder)
      sync_folder_with_box(box_folder, object_subfolder_path )
      add_meta_to_folder(box_folder, object_subfolder_path)
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
      ap e.backtrace
      puts e
      visit_page_of_corresponding_id(sobject.id)
      sleep 3
      kill_counter += 1
      retry if kill_counter < 3
    end
    parent_box_folder
  end

  def add_attachments_to_path( sobject, folder )
    attachments = sobject.attachments
    return unless attachments.present? #guard against nil or []
    attachments.each do |a|
      proposed_file = folder + a.name
      if !proposed_file.exist? || proposed_file.size == 0
        sf_attachment = @sf_client.custom_query(query: "SELECT id, body FROM Attachment where id = '#{a.id}'").first
        File.open(proposed_file, 'w') do |f|
          f.write(sf_attachment.api_object.Body)
        end
      end
    end
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
      (SELECT id, name FROM Attachments)
      FROM #{type}
      WHERE id = '#{id}'
    EOF
    @sf_client.custom_query(query: query).first
  end

  def visit_page_of_corresponding_id(id)
    @browser_tool.queue_work do |agent|
      agent.goto('https://na34.salesforce.com/' + id)
    end
  end

  def visit_page_of_corresopnding_folder(folder)
    folder_id = folder.split.last.to_s
    agent = @browser_tool.agents.first
    agent.goto('https://na34.salesforce.com/' + folder_id)
  end

  def process_box_folders(box_folder, parent_folder)
    destination = parent_folder + box_folder.id
    destination.mkpath
    box_folder.files.each do |file|
      proposed_file = destination + file.name
      if !proposed_file.present?
        File.new(proposed_file) do |local_file|
          local_file.write @box_client.download_file(file)
        end
      end
    end
    box_folder.folders.each do |folder|
      process_box_folders(folder, destination)
    end
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

  def sync_folder_with_box(box_folder, path)
    box_file_names = box_folder.files.map(&:name)
    path.each_child.select(&:file?).each do |file|
      FileUtils.rm(file) unless box_file_names.include?(file.split.last.to_s)
    end
    path.each_child.select(&:file?).each do |file|
      download_from_box( file, path )
    end
  end

  def download_from_box(file, path)
    proposed_file = Pathname.new(path) + (file.try(:name) || file.split.last.to_s)
    if !proposed_file.exist?
      local_file = File.new(proposed_file, 'w')
      local_file.write(@box_client.download_file(file))
      local_file.close
      @download += 1
      puts "Download number #{@download}"
    end
  end

  def construct_opps_query(groups)
    names = groups.map do |opp|
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
    names = groups.map do |c|
      sf_name_from_ff_name(c)
    end
    query = <<-EOF
        SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c,
        (SELECT Id, Name FROM Attachments)
        FROM case
        WHERE caseNumber in #{names.to_s.gsub('[','(').gsub(']',')').gsub('"', "'")}
      EOF
    query
  end

  def construct_opp_query(name: nil, id: nil )
    if id
      query = <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject FROM cases__r),
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
    if db.present? && db.try(:box_id).present?
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
    binding.pry
    @browser_tool.create_folder(opp)
  end

  def sf_name_from_ff_name(ff)
    begin
      match = ff.name.match(/(.+)\ -\ Finance$/) || ff.name.match(/(.+)\ -\ (\d+)Finance/)
      puts ff.name
      match[1]
    rescue => e
      ap e.backtrace
      binding.pry
    end
  end

  def finance_folders(&block)
    @box_client.folder("7811715461").folders.select do |finance_folder|
      yield finance_folder if block_given? && finance_folder.name !~ /^(Case Finance Template|Opportunity Finance Template)$/
      finance_folder.name !~ /^(Case Finance Template|Opportunity Finance Template)$/
    end
  end
end

begin
  cp = ConsolePotato.new()
  cp.produce_snapshot_from_scratch
  # cp.populate_database
rescue => e
  ap e.backtrace
  binding.pry
ensure
  w = WorkerPool.instance
  count = w.tasks.size
  kill_switch = 0
  while w.tasks.size > 1 do 
    sleep 1
    new_count = w.tasks.size
    if new_count == count
      kill_switch += 1
    else
      count = new_count
      kill_switch = 0
    end
    binding.pry if kill_switch > 60*5
    puts '\''*88
    puts "task size: #{w.tasks.size}"
    if count % 1000 == 0
      puts "worker status: #{w.workers.map(&:inspect)}"
      sleep 4
    end
    puts '\''*88
  end
  cp.browser_tool.agents.each(&:close)
end
