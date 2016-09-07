module Utils
  module SalesForce
    module Concern
      module Box
        def box_attach(zoho, file_data)
          if file_already_present?(file_data)
            return
          end
          # description = description_from_file_data(file_data)
          begin
            file = ::Zoho::Base.client.download_file(zoho.module_name, file_data[:id])
            create_relevant_folders
            create_linked(file)
            create_box(file)
            @modified = true
          rescue Errno::ETIMEDOUT
            puts 'api timeout waiting 10 seconds and retrying'
            sleep 10
            retry
          rescue => e
            puts e
            binding.pry
          end

        end

        private

        def create_relevant_folders
          root        = 'All Files'
          environment = "Salesforce - ReedHein (#{Utils.environment.capitalize})"
          type        = self.type.pluralize
          id          = self.id
          home        = 'test' #XXX
          desired_folders = [root, environment, type, id, home]
          home_folder = @client.create_folders(desired_folders)
          @client.upload_file('proposed_file_path', home_folder)
        end

        def create_folder
          what_is_my_environment?
        end

        def create_box(file)
          Utils::Box::Client
        end

        def create_linked(file)
          @client.create('box__frup__c',
            box__record_id__c: 'XXX',
            box__object_name_c: 'XXX',
            box__folder_id: 'xxx'
          )
        end

        def file_already_present?(file_data)
          puts 'testing for presence'
          attachments.entries.map{|attachment| attachment.fetch('Name')}.include? file_data[:file_name]
        end
      end
    end
  end
end

