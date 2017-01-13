module Utils
  module Box
    module Concern
      module DB
        def self.included(base)
          base.extend(ClassMethods)
        end

        def convert_api_object_to_local_storage(api_object)
          if api_object.type == 'folder'
            db = ::DB::BoxFolder.first_or_create( box_id: api_object.id)
          else
            db = ::DB::BoxFile.first_or_new( box_id: api_object.id, sha1: api_object.sha1)
          end
          db.name = api_object.name
          db.save
          api_object.storage_object = db
          api_object
        rescue DataObjects::ConnectionError => e
          puts e
          sleep 0.02
          retry
        rescue => e
          binding.pry
        end

        module ClassMethods
        end
      end
    end
  end
end
