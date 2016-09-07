module DB
  class BoxProgressRecord
    include DataMapper::Resource
    property :id, Serial
    property :name, String, length: 512
    property :created_date, DateTime
    property :sales_force_id, String, length: 255
    property :zoho_id, String, length: 255
    property :box_id, String, length: 255
    property :path, String, length: 512
    property :object_type, String, length: 255 #either folder or item
    property :lock, Boolean, default: false
    property :complete, Boolean, default: false
    property :attachment_migration_complete, Boolean, default: false
    property :notes_migration_complete, Boolean, default: false
    property :zoho_object_type, String, length: 255
  end
end
