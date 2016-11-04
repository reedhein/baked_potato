class SMB
  require 'sambal'
  attr_reader :smb_client
  def initialize
    host     = CredService.creds.smb.host
    user     = CredService.creds.smb.user
    password = CredService.creds.smb.password
    @worker_pool = WorkerPool.instance
    @cache_folder = Pathname.new('/home/doug/Sandbox/s_drive/Client Management/REED HEIN and ASSOCIATES/_Timeshare Exits')
    @smb_client = Sambal::Client.new(host: host, user: user, password: password, share:'DATA', columns: 500)
    dynanmic_methods_for_client
    @count  ||= 0
  end

  def reboot
    @smb_client = Sambal::Client.new(host: CredService.creds.smb.host, user: CredService.creds.smb.user, password: CredService.creds.smb.password, share:'DATA')
  end

  def self.cache
    smb = self.new
    smb.process_directory( smb.documents_path )
  end

  def sync
    cd(documents_path)
    DB::SMBRecord.all.batch(1000).each_with_index do |record, i|
      puts "#{i} testing #{record.path}"
      if Date.parse(record.date) && Date.parse(record.date) > Date.today
        puts "skipping #{Pathname.new(record.path).basename}"
        next
      end
      if !self.exists? record.path
        puts "deleting #{Pathname.new(record.path).basename}"
        record.destroy
      else
        record.date = Date.today.to_s
      end
      sleep 0
    end
  rescue =>  e
    ap e
    retry
  end

  def improved_sync
    @cache_folder.each_child.with_index do |entity, i|
      self.instance_variable_set("@woker#{i}".to_sym,  Thread.new { improved_process_path_entity(entity) } )
    end
    Thread.new do 
      seconds_elapsed ||= 0
      loop do
        statuses = instance_variables.select{|v| v =~ /worker\d+/}.map{|worker| worker.status}.uniq
        puts statuses
        if statuses.count == 1 && status.first == false
          DB::SMBRecord.all(:date.not => Date.today.to_s).destroy
          break
        elsif statuses.count == 1 && status.first.nil?
          break
        else
          puts "Waited #{seconds_elapsed} seconds"
          seconds_elapsed += 3
          sleep 3
        end
      end
    end
  end

  def improved_process_path_entity(entity)
    if entity.directory?
      entity.each_child do |enity|
        improved_process_path_entity(entity)
      end
    end
    DB::SMBRecord.create_from_path(entity)
  end

  def exists?(record_path)
    path        = Pathname.new(record_path).parent
    parent_path = path.parent
    file_name   = path.basename.to_s
    query_string = parent_path.to_s.gsub(current_directory, '') << "/*"
    ls(query_string).key? file_name
  end

  def cache
    # process_directory( documents_path )
    improved_proces_path
  end

  def process_directory(directory)
    response = cd directory
    return if response.success? == false
    @smb_client.ls.each do |entity|
      next if irrelevant(entity)
      entity_name = entity.first.dup
      process_directory(entity_name) if entity.last[:type] == :directory
      path = derive_path(entity)
      puts path
      if DB::SMBRecord.first(path: path)
        puts 'skipping'
      else
        @count += 1
        puts @count
        DB::SMBRecord.create_from_smb_entity(@smb_client, entity)
      end
      sleep 0
    end
    cd '..'
  rescue => e
    ap e.backtrace
    return
  end

  def files
    @smb_client.ls.select do |key, value|
      value[:type] == :file && (key != '..' || key != '.' || key != '.DS_Store')
    end
  end

  def directories
    @smb_client.ls.select do |key, value|
      value[:type] == :directory
    end
  end

  def documents
    @smb_client.cd documents_path
  end

  def derive_path(entity)
    path = current_directory
    path + entity.first
  end
  private

  def current_directory
    response = cd '.'
    response.message.split('smb:').last.strip.gsub("\\", '/').gsub("\r", '').chomp('>')
  end

  def documents_path
    ['Client Management', "REED HEIN and ASSOCIATES",  "_Timeshare Exits"].join('/').prepend('/')
  end

  def twenty_thirteen
    documents_path + '/2013 Exits'
  end

  def twenty_fourteen
    documents_path + '/2014 Exits'
  end

  def twenty_fifteen
    documents_path + '/2015 Exits'
  end

  def twenty_sixteen
    documents_path + '/2016 Exits'
  end

  def irrelevant(entity)
    ['.', '..', '.DS_Store', 'desktop.ini'].include? entity.first
  end

  def dynanmic_methods_for_client
    methods = @smb_client.public_methods - self.public_methods
    methods.each do |meth|
      define_singleton_method meth do |*args|
        @smb_client.send(meth, *args)
      end
    end
  end

end
