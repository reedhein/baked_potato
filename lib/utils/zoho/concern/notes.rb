module Utils
  module Zoho
    module Concern
      module Notes
        def notes
          RubyZoho.configuration.api.related_records(self.module_name, self.id, 'Notes') || []
        end

      end
    end
  end
end
