module DB
  class ZohoProgressRecord
    include DataMapper::Resource
    property :id, Serial
    property :zoho_id, String, length: 255
    property :module_name, String, length: 255
    property :attachment_migration_complete, Boolean, default: false
    property :note_migration_complete, Boolean, default: false
    property :complete, Boolean, default: false
  end
end
