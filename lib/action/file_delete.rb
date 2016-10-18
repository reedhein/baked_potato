class FileDelete < Action
  def initialize(*args)
    super(*args)
  end

  def perform
    type = file_type_by_id(@file_id)
    binding.pry
    case type
    when :box
      @box_client.delete_file(@file_id)
    when :salesforce
      @sf_client.destroy('Attachment', @file_id)
    end
    FileUtils.rm(@record.full_path)
    @record.destroy
  end
end
