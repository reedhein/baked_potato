module Utils
  module Zoho
    class Note < Utils::Zoho::Base
      def note_migration_complete?
        @storage_object.note_migration_complete
      end
    end
  end
end
