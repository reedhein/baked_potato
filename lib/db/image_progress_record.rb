module DB
  class ImageProgressRecord
    include DataMapper::Resource
    property :id, Serial
    property :public_folder , String, length: 255
    property :private_folder, String, length: 255
    property :opportunity_id, String, length: 255
    property :filename,       String, length: 255
    property :full_path,      String, length: 512
    property :type,           String, length: 255
    property :size,           Integer
    property :fingerprint,    String, length: 255
    property :locked,        Boolean, default: false
    property :complete,      Boolean, default: false

    def self.create_new_from_path(path)
      opp_id = CacheFolder.opp_id_from_path(path)
      cf = CacheFolder.new(opp_id: opp_id)
      puts path
      first_or_create(
        public_folder:  cf.box_public,
        private_folder: cf.box_private,
        opportunity_id: cf.opp_id,
        type:           Pathname.new(path).extname,
        full_path:      path
      )
    end
  end
end
