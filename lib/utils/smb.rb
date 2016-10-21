class SMB
  require 'sambal'
  def initialize
    host     = CredService.creds.smb.host
    user     = CredService.creds.smb.user
    password = CredService.creds.smb.password
    @smb_client = Sambal::Client.new(host: host, user: user, password: password, share:'DATA')
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

  def cache
    process_directory( documents_path )
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
    end
    cd '..'
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
    response = cd '.'
    path = response.message.split('smb:').last.strip.gsub("\\", '/').gsub("\r", '').chomp('>')
    path + entity.first
  end
  private

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
