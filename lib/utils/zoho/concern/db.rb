module Utils
  module Zoho
    module Concern
      module DB
        def self.included(base)
          base.extend(ClassMethods)
        end


        def migration_complete?
          migration_complete
        end
        
        def mark_migration_complete(task)
          change = {}
          change["#{task.to_s}_migration_complete".to_sym] = true
          @storage_object.update(change)
        end

        def mark_all_completed
          @migration_complete = @storage_object.update(complete: true)
        end

        def find_or_create(api_object)
          self.class.convert_api_object_to_local_storage(api_object)
        end

        module ClassMethods


          def convert_api_object_to_local_storage(api_object)
            ::DB::ZohoProgressRecord.first_or_create(
              zoho_id: api_object.id,
              module_name: api_object.module_name
            )
          end


          def zoho_id(id)
            id.gsub('zcrm_', '')
          end
        end
      end
    end
  end
end
