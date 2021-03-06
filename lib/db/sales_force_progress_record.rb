module DB
  class SalesForceProgressRecord
    include DataMapper::Resource
    property :id, Serial
    property :created_date, DateTime
    property :box__record_id__c, String, length: 255
    property :box__folder_id__c, String, length: 255
    property :casenumber, String, length: 50
    property :subject, String, length: 255
    property :sales_force_id, String, length: 255
    property :name, String, length: 255
    property :zoho_id, String, length: 255
    property :object_type, String, length: 255
    property :complete, Boolean, default: false
    property :attachment_migration_complete, Boolean, default: false
    property :kitten_migration_complete, Boolean, default: false
    property :notes_migration_complete, Boolean, default: false
    property :zoho_object_type, String, length: 255

    def box_id
      box__folder_id__c
    end

    def case_number
      casenumber
    end

    def case_number=(value)
      casenumber(value)
    end
  end
end
