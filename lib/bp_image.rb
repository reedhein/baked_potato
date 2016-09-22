class BPImage
  attr_accessor :db_image, :path

  def initialize(image_path)
    @path         = Pathname.new(image_path)
    @cache_folder = CacheFolder.new(@path)
  end

  def lock
    @db_image.update(locked: true)
  end

  def self.random_unlocked
    records = DB::ImageProgressRecord.all(parent_type: 'opportunity', locked: false, complete: false, type: %w(.jpg .png .pdf))
    record = records.sample
    cf = CacheFolder.new(record.full_path)
    bpi = BPImage.new(record.full_path)
    bpi.db_image = record
    bpi
  end

  def full_path
    @db_image.full_path
  end

  def meta
    @cache_folder.meta
  end

  def cases
    cases_folder = @path.parent + 'cases'
    cases_folder.children.select do |entity|
      entity.directory? && entity.basename =~ /^005/
    end
  end
end
