module DB
  class BoxFolder
    include DataMapper::Resource
    property :id, Serial
    property :name, String, length: 512
    property :box_id, String, length: 255, index: true, unique: true
    property :relative_path, String, length: 512
  end
end
DataMapper.finalize
