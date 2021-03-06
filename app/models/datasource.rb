class Datasource < ActiveRecord::Base

  belongs_to :project
  has_one :datapackage_resource
  validates :project_id, presence: true
  validates :table_ref, uniqueness: { scope: :project,
                                      message: "Filenames must be unique (file extensions are ignored)" }
  has_attached_file :datafile,
    :path => ":rails_root/public/uploads/project_:proj_id/:filename",
    :url  => "/uploads/project_:proj_id/:filename"

  # validates_attachment :datafile, :content_type => /\Atext\/csv/
  validates_attachment :datafile, content_type: { :content_type => [/\Atext\//, "application/json"] }
  validates_attachment_file_name :datafile, :matches => [/csv\Z/, /datapackage.*\.json/]

  process_in_background :datafile # delayed_paperclip

  enum import_status: [ :ok, :note, :warning, :error ]

  before_create :set_table_ref

  # Some helper methods, useful for linking to log file
  def basename
    File.basename(self.datafile_file_name, ".*" )
  end

  def full_upload_path
    File.dirname(self.datafile.path)
  end

  def upload_path
    full_upload_path[/(?=\/datafiles).*/]
  end

  def logfile
    "upload_" + self.basename + ".log"
  end


  def delete_associated_artifacts
    unset_dp_datasource_id(self.id)
    delete_db_table
    delete_log
    delete_upload
  end

  def unset_dp_datasource_id(ds_id)
    dp_res = DatapackageResource.where(datasource_id: ds_id)
    # should only be one
    dp_res.each do |r|
      r.datasource_id = nil
      r.save
    end
  end

  # delete_db_table called when destroying datasource
  def delete_db_table
    table = self.db_table_name
    if ActiveRecord::Base.connection.table_exists? table
      ActiveRecord::Base.connection.drop_table(table)
    end
  end

  def delete_log
    log = self.project.job_log_path + self.datafile_file_name + ".log"
    File.delete(log) if File.exist?(log)
  end

  def delete_upload
    upload = self.project.upload_path + self.datafile_file_name
    File.delete(upload) if File.exist?(upload)
  end

  private

    # Use an interpolation to get project_id into the path
    # https://github.com/thoughtbot/paperclip/wiki/Interpolations
    #http://stackoverflow.com/questions/9173920/paperclip-custom-path-with-id-belongs-to
    Paperclip.interpolates :proj_name do |attachment, style|
      Project.find(attachment.instance.project_id).name
    end

    Paperclip.interpolates :proj_id do |attachment, style|
      attachment.instance.project_id
    end

    def set_table_ref
      self.table_ref = basename
    end

end
