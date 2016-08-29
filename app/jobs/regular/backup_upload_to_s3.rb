module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find_by(id: args[:upload_id])
      upload.backup_to_s3 if upload
    end
  end
end
