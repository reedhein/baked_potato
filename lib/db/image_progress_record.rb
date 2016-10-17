module DB
  class ImageProgressRecord
    include DataMapper::Resource
    property :id,             Serial
    property :file_id,        String, length: 255
    property :parent_id,      String, length: 255
    property :filename,       String, length: 255
    property :full_path,      FilePath
    property :moved_from,     FilePath
    property :date,           String, length: 255
    property :sha1,           String, length: 255
    property :ext,            String, length: 255
    property :parent_type,    String, length: 255
    property :fingerprint,    String, length: 255
    property :locked,        Boolean, default: false
    property :complete,      Boolean, default: false

    def self.create_new_from_path(path)
      path = Pathname.new(path)
      cf = CacheFolder.new(path)
      db = first_or_new(
        parent_id:   cf.id,
        ext:         path.extname,
        full_path:   path,
        parent_type: parent_type(path)
      )
      db.date = Date.today.to_s
      binding.pry if db.new?
      db.save
      db
    end

    def self.find_from_path(path)
      path = Pathname.new(path)
      db = first_or_new(
        ext:         path.extname,
        full_path:   path,
        parent_type: parent_type(path),
        date:        Date.today.to_s
      )
      db.date = Date.today.to_s
      db
    end

    def self.delete_old
      DB::ImageProgressRecord.destroy_all
    end

    def rename(name)
      self.fullname = name
      full_path.rename(name)
      save
    end

    def lock
      self.update(locked: true)
    end

    def move_to(destination_id, new_id)
      record           = DB::ImageProgressRecord.first(parent_id: id)
      path             = record.full_path.parent
      self.moved_from  = self.full_path
      self.full_path   = path + filename
      self.parent_type = self.class.parent_type(path)
      self.file_id     = new_id if new_id
      save
    rescue => e
      ap e.backtrace
      binding.pry
    end

    private

    def self.parent_type(path)
      parent = path.ascend.detect do |entity|
        entity.directory? && (entity.basename.to_s =~ /^500/ || entity.basename.to_s =~ /^006/)
      end
      parent.basename.to_s.match(/^500/) ? :case : :opportunity
    end

    DataMapper.finalize
  end
end

