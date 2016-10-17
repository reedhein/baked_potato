class FileMove < Action
  def initialize(*args)
    super(*args)
  end

  def perform
    record = DB::ImageProgressRecord.first(file_id: @file_id)
    prep = [file_type_by_id(@file_id), folder_type_by_id(@destination_id)]
    binding.pry
    new_id = nil
    case prep
    when [:salesforce, :opportunity], [:salesforce, :case]
      move_sf_attachment_to_sf_folder
    when [:box, :opportunity], [:box, :case]
      new_id = move_box_attachment_to_sf_folder
    when [:salesforce, :box]
      new_id = move_sf_attachment_to_box_folder
    when [:box, :box]
      move_box_attachment_to_box_folder
    end
    CacheFolder.new(@record.full_path).move_to_folder_id(@destination_id)
    @record.move_to(@destination_id, new_id)
  end

  def move_sf_attachment_to_sf_folder
    @sf_client.update('Attachment', Id: @file_id, parentId: @destination_id)
  end

  def move_box_attachment_to_sf_folder
    attachment = @sf_cleint.create('Attachment',
      Name: record.filename,
      Body: Base64::encode64(File.read(record.full_path)),
      Description: "Moved by #{@email} from #{@source_id} on #{Date.today.to_s}",
      ParentId: @destination_id
    )
    binding.pry
    attachment.id
  end

  def move_sf_attachment_to_box_folder
    file = @box_client.upload_file(@record.full_path, @destination_id)
    binding.pry
    file.id
  end

  def move_box_attachment_to_box_folder
    @box_client.move_folder(@file_id, @destination_id)
  end

end
