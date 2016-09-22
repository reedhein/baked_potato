module DB
  class ImageProgressRecord
    include DataMapper::Resource
    property :id, Serial
    property :public_folder , String, length: 255
    property :private_folder, String, length: 255
    property :parent_id,      String, length: 255
    property :parent_type,    String, length: 255
    property :filename,       String, length: 255
    property :full_path,      String, length: 512
    property :type,           String, length: 255
    property :size,           Integer
    property :fingerprint,    String, length: 255
    property :locked,        Boolean, default: false
    property :complete,      Boolean, default: false

    def self.create_new_from_path(path)
      path = Pathname.new(path)
      size = path.size
      id = path.parent.to_s.split('/').last
      first_or_create(
        parent_id:   id,
        full_path:   path,
        type:        Pathname.new(path).extname.downcase,
        parent_type: self.get_parent_type(id),
        size:        size
      )
    end

    def self.delete_old
      DB::ImageProgressRecord.destroy_all
    end

    private

    def self.get_parent_type(id)
      if id =~ /^006/
        puts 'opportunity'
        :opportunity
      elsif id =~ /^500/
        puts 'case'
        :case
      elsif id =~ /^\d{10,}$/
        puts 'box'
        :box
      else
        puts 'wtf'
        binding.pry
      end
    end
  end
end
