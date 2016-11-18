module DB
  class BoxFile
    include DataMapper::Resource
    property :id, Serial
    property :name, String, length: 512
    property :sha1, String, length: 512
    property :box_id, String, length: 255
    property :relative_path, String, length: 512
    property :box_folder_id, Integer, default: 1337
  end
end
DataMapper.finalize
