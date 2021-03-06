module DB
  class ImageProgressRecord
    include DataMapper::Resource
    property :id,             Serial
    property :file_id,        String, length: 255, index: true
    property :parent_id,      String, length: 255
    property :filename,       String, length: 255
    property :mac_base_path,  FilePath, default: Pathname.new('/Users/voodoologic/Sandbox/dated_cache_folder')
    property :linx_base_path, FilePath, default: Pathname.new('/home/doug/Sandbox/dated_cache_folder')
    property :relative_path,  FilePath
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
      db = first_or_new(
        parent_id:   path.parent.basename.to_s,
        ext:         path.extname,
        filename:    path.basename.to_s,
        parent_type: parent_type(path)
      )
      db.relative_path =  path
      db.date = Date.today.to_s
      db.save
      db
    end

    def self.find_from_path(path)
      path = Pathname.new(path)
      db   = first_or_new(
        ext:         path.extname,
        filename:    path.basename.to_s,
        parent_id:   path.parent.basename.to_s,
        parent_type: parent_type(path)
      )
      db.relative_path = path
      db.date = Date.today.to_s
      db.save
      db
    end

    def self.delete_old
      DB::ImageProgressRecord.destroy_all
    end

    def rename(name)
      self.fullname = name
      self.full_path = self.full_path.parent + name
      save
    end

    def lock
      self.update(locked: true)
    end

    def move_to(destination_id, new_id)
      dest = DB::ImageProgressRecord.first(parent_id: destination_id) || Find.find(CacheFolder.path){|path| break Pathname.new(path) if Pathname.new(path).basename.to_s == destination_id}
      if dest.is_a? DB::ImageProgressRecord
        dest_path = dest.full_path.parent
      else
        dest_path = dest
      end
      self.moved_from     = self.full_path
      self.relative_path  = dest_path.sub(self.send(env_path), '').sub('/' + Date.today.to_s , '') + filename
      self.parent_type    = self.class.parent_type(dest_path)
      self.file_id        = new_id if new_id
      save
      self
    rescue => e
      ap e.backtrace
      binding.pry
    end

    def full_path
      self.send(env_path) + Date.today.to_s + relative_path
    end

    def env_path
      if RbConfig::CONFIG['host_os'] =~ /darwin/
        :mac_base_path
      else
        :linx_base_path
      end
    end

    private

    def self.parent_type(path)
      parent = path.ascend.detect do |entity|
        entity.to_s.split('/').last =~ /^500/ || entity.to_s.split('/').last =~ /^006/
      end
      binding.pry if parent.nil?
      parent.basename.to_s.match(/^500/) ? :case : :opportunity
    end

  end
end
DataMapper.finalize

