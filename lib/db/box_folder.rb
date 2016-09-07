module DB
  class BoxFolder
    include DataMapper::Resource
    property :id, Serial
    property :name, String, length: 512
    property :created_date, DateTime
    property :sales_force_id, String, length: 255
    property :box_id, String, length: 255
    property :path, String, length: 512
    property :lock, Boolean, default: false
    property :download_complete, Boolean, default: false
    property :migration_complete, Boolean, default: false
    property :complete, Boolean, default: false
    property :attachment_migration_complete, Boolean, default: false
    has n, :box_files
  end
end
