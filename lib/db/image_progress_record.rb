module DB
  class ImageProgressRecord
    include DataMapper::Resource
    property :id,             Serial
    property :parent_id,      String, length: 255
    property :filename,       String, length: 255
    property :full_path,      FilePath
    property :date,           String, length: 255
    property :ext,            String, length: 255
    property :parent_type,    String, length: 255
    property :fingerprint,    String, length: 255
    property :locked,        Boolean, default: false
    property :complete,      Boolean, default: false

    def self.create_new_from_path(path)
      puts path
      path = Pathname.new(path)
      cf = CacheFolder.new(path)
      db = first_or_new(
        parent_id:   cf.id,
        ext:         path.extname,
        full_path:   path,
        parent_type: parent_type(path)
      )
      db.date = Date.today.to_s
      db.save
    end

    def self.delete_old
      DB::ImageProgressRecord.destroy_all
    end

    private 
    def self.parent_type(path)
      parent = path.ascend.detect do |entity|
        entity.directory? && (entity.basename.to_s =~ /^500/ || entity.basename.to_s =~ /^006/)
      end
      parent.basename.to_s.match(/^500/) ? :case : :opportunity
    end
  end
end
