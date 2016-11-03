
module DB
  class SMBRecord
    include DataMapper::Resource
    property :id,            Serial
    property :type,          String, length: 255
    property :name,          String, length: 255
    property :path,          String, length: 255
    property :date,          String, length: 255
    property :sha1,          String, length: 255
    property :local_path,    String, length: 255, default: '/home/doug/Sandbox/s_drive'
    property :network_path,  String, length: 255, default: '/Client Management/REED HEIN and ASSOCIATES/_Timeshare Exits/'
    property :relative_path, String, length: 255

    def self.create_from_smb_entity(smb_client, entity)
      response = smb_client.cd '.'
      path = response.message.split('smb:').last.strip.gsub("\\", '/').gsub("\r", '').chomp('>')
      record = first_or_create(name: entity.first, path: path + entity.first)
      record
    rescue => e
      ap e.backtrace
      binding.pry
    end

    def full_path
      local_path + network_path + relative_path
    end

    def self.create_from_path(path)
      record = first_or_new(name: path.basename, relative_path: get_relative_path(path))
      record.date = Date.today.to_s
      record.type = path.directory? ? :directory : :file
      record.sha1 = Digest::SHA1.hexdigest(path.read)
      record.save
      record
    end

    def self.local_path
      '/home/doug/Sandbox/s_drive'
    end

    def self.network_path
      '/Client Management/REED HEIN and ASSOCIATES/_Timeshare Exits/'
    end

    private

    def self.get_relative_path(path)
      path.to_s.gsub(local_path, '').gsub(network_path, '')
    end
  end

end
