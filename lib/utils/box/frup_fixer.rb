module Utils
  module Box
    class FrupFixer
      def initialize(sf_id: nil, box_id: nil, user: nil)
        @sf_id                = sf_id
        @box_id               = box_id
        @user                 = user
        @sf_client            = Utils::SalesForce::Client.new(DB::User.Doug)
        @box_client           = Utils::Box::Client.new(@user || DB::User.Doug)
        @admin_box_client     = Utils::Box::Client.new(DB::User.first(email: 'boxsalesforce@reedhein.com'))
      end

      def frup_fixer
        s_object    = s_object_from_id(@sf_id)
        old_folder  = @box_client.folder(frups.first.box__folder_id__c)
        frups       = query_frup(s_object, debug: true)
        frups.each do |frup|
          frup.delete
        end
        frups = query_frup(s_object, debug: true)
        yield old_folder if block_given?
        @box_client.delete(old_folder)
      rescue => e
        ap e.backtrace
        binding.pry
        puts 'YUGE'
      end

      def build_new_box
        s_object = s_object_from_id(id)
        @box_client.case_template
      end

      def repair_box
        puts 'yeeee'
        new_case_template  = @admin_box_client.case_template
        # new_opp_template   = @admin_box_client.opp_template
        case_colab         = @admin_box_client.folder_collaborations(new_case_template)
        # opp_colab          = @admin_box_client.folder_collaborations(new_opp_template )
        # opp_parent         = @admin_box_client.folder('5665505677')
        case_parent        = @admin_box_client.folder('5665821837')
        # folders            = @admin_box_client.folders
        s_object           = s_object_from_id
        if s_object.type.downcase.to_sym == :case
          new_folder  = @admin_box_client.copy_folder(new_case_template, case_parent, name: "#{(s_object.time_share_name__c || '')} -  #{s_object.case_number}Finance" )
        else #opp
          new_folder  = @admin_box_client.copy_folder(new_opp_template, opp_parent, name: "#{(s_object.name)} - Finance - #{s_object.id} ")
        end
        frups         = query_frup(s_object, debug: true)
        old_folder    = @box_client.folder(frups.first.box__folder_id__c) if frups.present?
        binding.pry
        frups.each do |frup|
          frup.delete
        end
        Utils::SalesForce::BoxFrupC.create_from_objects(s_object, new_folder, @sf_client)
        move_data_to_new_folder(new_folder,old_folder) if old_folder.present?
      rescue => e
        puts e
        binding.pry
      end

      private

      def query_frup(sobject, debug: false)
        db = Utils::SalesForce::BoxFrupC.find_db_by_id(sobject.id)
        if db.present? && db.box__folder_id__c.present? && db.created_date.present? && DateTime.parse(db.created_date) < ( DateTime.today - 3.days )
          db
        else
          @sf_client.custom_query(query:"SELECT id, createddate, box__Folder_ID__c, box__Object_Name__c, box__Record_ID__c FROM box__FRUP__c WHERE box__Record_ID__c = '#{sobject.id}' LIMIT 1")
        end
      end

      def move_data_to_new_folder(new_folder, old_folder)
        @box_client.update_folder(old_folder, name: old_folder.name + ' (backup)')
        old_folder_folders = old_folder.folders
        files = old_folder.files
        files.each do |file|
          @box_client.move_file(file, new_folder)
        end
        old_folder_folders.each do |folder|
          folder.files.each do |file|
            @box_client.move_file(file, new_folder)
          end
        end
      end

      def s_object_from_id
        if @sf_id =~ /^500/
          query = construct_case_query
        else
          query = construct_opp_query
        end
        @sf_client.custom_query(query: query).first
      end
      
      def construct_case_query
        query = <<-EOF
          SELECT Id, createdDate, caseNumber, closeddate, zoho_id__c, createdbyid, contactid, subject, Opportunity__c, time_share_name__c,
          (SELECT Id, Name FROM Attachments)
          FROM case
          WHERE id = '#{@sf_id}'
          LIMIT 1
        EOF
        query
      end

      def construct_opp_query
        <<-EOF
          SELECT Name, Id, createdDate,
          (SELECT id, caseNumber, createddate, closeddate, zoho_id__c, createdbyid, contactid, opportunity__c, subject FROM cases__r),
          (SELECT Id, Name FROM Attachments)
          FROM Opportunity
          WHERE id = '#{@sf_id}'
          LIMIT 1
        EOF
      end
    end
  end
end
