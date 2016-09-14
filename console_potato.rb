require 'pry'
require 'active_support/time'
require 'awesome_print'
require 'yaml'
require 'watir'
require 'watir-scroll'
require_relative './lib/cache_folder'
require_relative './lib/utils'
ActiveSupport::TimeZone[-8]

class ConsolePotato
  attr_reader :browser_tool
  def initialize(environment: 'production', offset_count: 0, project: 'box_population', id: nil)
    Utils.environment    = @environment = environment
    @id                  = id
    @sf_client           = Utils::SalesForce::Client.instance
    @box_client           = Utils::Box::Client.instance
    @local_dest_folder   = Pathname.new('/Users/voodoologic/Sandbox/cache_folder')
    @formatted_dest_folder= Pathname.new('/Users/voodoologic/Sandbox/formatted_cache_folder')
    @dated_cache_folder   = Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder') + Date.today.to_s
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
          #find opp
            opportunity = opp_from_finance_folder(finance_folder)
            next unless opportunity
            next if [ '006610000066jcyAAA' , '00661000008PuHQAA0' , '00661000005RPAjAAO' ].include? opportunity.id
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
              #make xml
              #make db
              #get box
              #get native
            end
        end
      end
    end
  end

  def populate_database
    files = Dir.glob(@dated_cache_folder + '**/*').map do |d_or_f|
      Dir.glob(d_or_f + '/*')
    end.flatten.delete_if{|x| Pathname.new(x).basename == 'cases' && Pathname.new(x).extname == 'yml'}
    files.map do |x|
      DB::ImageProgressRecord.create_new_from_path(x)
    end
  end

  def produce_snapshot_from_scratch
    finance_folders do |finance_folder|
      opportunity = opp_from_finance_folder(finance_folder)
      next unless opportunity
      next if [ '006610000066jcyAAA' , '00661000008PuHQAA0' , '00661000005RPAjAAO' ].include? opportunity.id
      todays_backup = @dated_cache_folder + opportunity.id
      todays_backup.mkpath
      add_attachments_to_path(todays_backup, opportunity.attachments)
      populate_local_box_attachments_for_sobject_and_path(opportunity, todays_backup)
      populate_local_cases_salesforce_native_attachments_and_box_from_opportunity(opportunity)
    end
  end

  def bc
    @browser_tool.close
  end

  private

  def opp_from_finance_folder(finance_folder)
    sf_name  = sf_name_from_ff_name(finance_folder)
    query = construct_opp_query(name: sf_name)
    @sf_client.custom_query(query: query).first
  end

  def populate_local_salesforce_native_attachments_cases_from_opportunity(opp)
    todays_backup      = @dated_cache_folder
    cases_folder = (todays_backup + opp.id + 'cases')
    cases_folder.mkpath
    opp.cases.each do |sf_case|
      case_folder = cases_folder + sf_case.id
      case_folder.mkpath
      add_attachments_to_path(case_folder, sf_case.attachments)
    end
  end

  def populate_local_cases_salesforce_native_attachments_and_box_from_opportunity(opp)
    todays_backup      = @dated_cache_folder
    cases_folder = (todays_backup + opp.id + 'cases')
    cases_folder.mkpath
    opp.cases.each do |sf_case|
      case_folder = cases_folder + sf_case.id
      case_folder.mkpath
      add_attachments_to_path(case_folder, sf_case.attachments)
      populate_local_box_attachments_for_sobject_and_path(sf_case, case_folder)
    end
  end

  def populate_local_box_attachments_for_sobject_and_path(sobject, path)
    sf_linked = poll_for_frup(sobject)
    begin
      parent_box_folder = @box_client.folder_from_id( sf_linked.box__folder_id__c )
    rescue Boxr::BoxrError => e
      visit_page_of_corresponding_id(sobject.id)
      sleep 3
      retry
    end
    local_parent_box_folder = (path + parent_box_folder.id)
    local_parent_box_folder.mkpath
    parent_box_folder.files.each do |file|
      download_from_box(file, local_parent_box_folder )
    end
    parent_box_folder.folders.each do |folder|
      object_subfolder_path = local_parent_box_folder + folder.id
      object_subfolder_path.mkpath
      meta = {name: folder.name}
      File.open(object_subfolder_path  + 'meta.yml', 'w') {|f| f.write meta.to_yaml}
      folder.files.each do |file|
        download_from_box(file, object_subfolder_path) unless file_present?(file, object_subfolder_path)
      end
    end
  end

  def add_attachments_to_path(folder, attachments)
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
      add_attachments_to_path(folder, opp.attachments)
    when Utils::SalesForce::Opportunity, Utils::SalesForce::Case
      add_attachments_to_path(folder, object.attachments)
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
    opp = @sf_client.custom_query(query: query).first
  end

  def add_box_attachments_to_folder(box_folder)
    folder_id = box_folder.split.last.to_s
    api_box_folder = @box_client.folder_from_id(folder_id)
    api_box_folder.files.each do |file|
      proposed_file = box_folder + file.name
      binding.pry
      if !proposed_file.exist?
        File.new(proposed_file) do |local_file|
          local_file.write @box_client.download_file(file)
        end
      end
    end
  end

  def add_meta_to_folder(folder)
    if folder.split[-1].size >= 15 #sf folder
    else
    end
  end

  def visit_page_of_corresponding_id(id)
    agent = @browser_tool.agents.first
    agent.goto('https://na34.salesforce.com/' + id)
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

  def move_cases_over(source_folder, dest_folder)
    create_folders_from_source(source_folder, dest_folder)
    # copy_stuff_over(source_folder, dest_folder)
  end

  def create_folders_from_source(source_folder, dest_folder) #source_folder = opp, dset_folder = 
    source_cases_folder = Pathname.new(source_folder + 'cases')
    binding.pry unless source_cases_folder.exist?
    traverse_cases(source_cases_folder)
  end

  def traverse_cases(source_cases_folder)
    source_cases_folder.each_child.select{|x| x.split.last.to_s =~ /^500/ && !x.file?}.each do |case_folder|
      puts case_folder
      box_folder = find_parent_box_folder_of_case(case_folder)
      move_other_box_folders_into_parent_folder(box_folder, case_folder)
    end
  end

  def copy_stuff_over(source_folder, dest_folder)
    source_directories    = Dir.glob(source_folder + '**/*').select{|c| File.directory?(c) }.map{|d| Pathname.new(d)}
    newly_created_folders = Dir.glob(dest_folder + 'cases/**/*').select{|c| File.directory?(c) }.map{|d| Pathname.new(d)}
    newly_created_folders.each do |folder|
      corresponding_source_folder = find_directory_in_list(folder, source_directories)
      items_to_copy = corresponding_source_folder.children.delete_if { |d| d.basename.to_s == '.DS_Store' }
      items_to_copy.each do |item|
        FileUtils.cp_r(item, dest_folder)
      end
    end
  end

  def find_directory_in_list(dir, list)
    list.detect{ |path| path.split.last.to_s == dir.split.last.to_s }
  end

  def move_other_box_folders_into_parent_folder(parent_box_folder, source_case_folder)
    parent_dest_folder = source_case_folder + parent_box_folder.id
    parent_box_folder.folders.each do |folder|
      local_folder = Pathname.new(source_case_folder) + folder.id
      begin
        FileUtils.mv(local_folder, parent_dest_folder) if local_folder.exist? && !parent_dest_folder.exist?
      rescue => e
        puts e
        binding.pry
      end
    end
  end

  def move_opp_to_new_format(folder) 
    box_finance_folder_id, opp_id, box_root_folder_id = folder.split.last.to_s.split('_')
    opp_folder = @formatted_dest_folder + opp_id
    visit_page_of_corresopnding_folder(opp_folder)
    sleep 3
    opp = salesforce_object_from_id_folder(opp_folder)
    binding.pry unless opp
    add_sf_attachments_to_folder(opp)
    move_cases_over(folder, opp_folder) #folder = oroginal oldcache folder, opp_folder = newcache
    @kill  = 0
    begin
      api_box_folder = @box_client.folder_from_id(box_root_folder_id)
    rescue
      @kill += 1
      if @kill >= 3
        binding.pry
      else
        puts "404 sleeping"
        sleep 3
        retry
      end
    end
    process_box_folders(api_box_folder, opp_folder)
  end

  def file_present?(file, path)
    (path + file.name).exist?
  end

  def preserve_indexed_name!(source_file, file)
    binding.pry
    File.rename(source_file, file.name)
  end

  def work_completed?(file, dest_path)
    Pathname.new([dest_path , file.name].join('/')).exist?
  end

  def download_from_box(file, path)
    proposed_file = Pathname.new(path) + file.name
    if !proposed_file.exist?
      local_file = File.new(proposed_file, 'w')
      local_file.write(@box_client.download_file(file))
      local_file.close
      @download += 1
      puts "Download number #{@download}"
    end
  end

  def construct_opp_query(name: nil, id: nil )
    if id
      query = <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c FROM cases__r),
          (SELECT Id, Name FROM Attachments)
          FROM Opportunity
          WHERE id = '#{id}'
        EOF
    elsif name
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c FROM cases__r),
        (SELECT Id, Name FROM Attachments)
        FROM Opportunity WHERE Name = '#{name.gsub("'", %q(\\\'))}'
      EOF
    elsif @offset_date
      query = <<-EOF
        SELECT Name, Id, createdDate,
        (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c FROM cases__r),
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
    result = @sf_client.custom_query(query:"SELECT id, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{sobject.id}'")
  end

  def poll_for_frup(opp)
    kill_counter = 0
    sf_linked = query_frup(opp).first
    while sf_linked.nil? do
      puts 'sleeping until created'
      sleep 6
      kill_counter += 1
      break if kill_counter > 5
      sf_linked = query_frup(opp).first
    end
    sf_linked
  end

  def create_folder_through_browser(opp)
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
      finance_folder.name.match(/\d{8}\ -\ Finance$/)
    end
  end
end

begin
  cp = ConsolePotato.new()
  # cp.produce_snapshot_from_scratch
  cp.populate_database
rescue => e
  ap e.backtrace
  binding.pry
ensure
  cp.browser_tool.agents.each(&:close)
end
