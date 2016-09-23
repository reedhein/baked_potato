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
    records = DB::ImageProgressRecord.all(parent_type: 'opportunity', locked: false, complete: false, ext: %w(.jpg .png .pdf), date: Date.today.to_s)
    record = records.sample
    binding.pry unless record
    cf = CacheFolder.new(record.full_path)
    bpi = BPImage.new(record.full_path)
    bpi.db_image = record
    bpi
  end

  def ext
    @db_image.ext
  end

  def full_path
    @db_image.full_path
  end

  def meta
    @cache_folder.meta
  end

  def name
    @path.basename
  end

  def opportunity
    @cache_folder.opportunity
  end

  def cases
    cases_folder = @path.parent + 'cases'
    return [] unless cases_folder.exist?
    cases_folder.children.select do |entity|
      entity.directory? && entity.basename.to_s =~ /^500/
    end.map do |case_folder|
      CacheFolder.new(case_folder)
    end
  end
end
