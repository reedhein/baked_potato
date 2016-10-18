module Utils
  module SalesForce
    module Concern
      module DB
        # This class is mostly for hooking in DB functionality
        def self.included(base)
          base.extend(ClassMethods)
        end

        def convert_api_object_to_local_storage(api_object)
          fail 'SOQL query needs Id' unless api_object['Id']
          db = ::DB::SalesForceProgressRecord.first_or_new(
            sales_force_id: api_object.fetch('Id'),
            object_type: api_object.fetch('attributes').fetch('type')
          )
          db.box__folder_id__c = api_object.fetch('box__Folder_ID__c', nil)
          db.box__record_id__c = api_object.fetch('box__Record_ID__c', nil)
          db.save
        rescue DataObjects::ConnectionError => e
          puts e
          sleep 0.02
          retry
        end

        def migration_complete?
          @migration_complete ||= @storage_object.complete
        end

        def mark_migration_complete(task)
          change = {}
          change["#{task.to_s}_migration_complete".to_sym] = true
          @storage_object.update(change)
        end

        def mark_all_completed
          @migration_complete = @storage_object.update(complete: true)
        end

        def mark_unfinished
          [:notes, :attachment].each do |task|
            change = {}
            change["#{task.to_s}_migration_complete".to_sym] = false
            @storage_object.update(change)
          end
        end

        def notes_migration_complete?
          @storage_object.notes_migration_complete
        end

        def modified?
          @modified
        end

        module ClassMethods
        end
      end
    end
  end
end
