class DerpAttachmentMigrationTool
  attr_accessor :meta
  def initialize(zoho, sf, meta)
    @meta = meta
    @zoho = zoho_sushi
    @sf   = sf
  end

  def perform
    attachments = @zoho.attachments
    attachments.map do |attachment|
      @sf.attach(@zoho, attachment)
    end
    @meta.updated_count += 1
    if @sf.modified?
      @meta.updated_count += 1
      @meta.save
    end
    @zoho.mark_migration_complete(:attachment)
    @sf.mark_migration_complete(:attachment)
  end
end
