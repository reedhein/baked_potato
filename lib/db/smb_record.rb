
module DB
  class SMBRecord
    include DataMapper::Resource
    property :id,   Serial
    property :name, String, length: 255
    property :path, String, length: 255, unique: true, index: true

    def self.create_from_smb_entity(smb_client, entity)
      response = smb_client.cd '.'
      path = response.message.split('smb:').last.strip.gsub("\\", '/').gsub("\r", '').chomp('>')
      record = first_or_create(name: entity.first, path: path + entity.first)
      puts record.inspect
      record
    rescue => e
      ap e.backtrace
      binding.pry
    end
  end

end
