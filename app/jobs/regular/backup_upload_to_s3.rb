# frozen_string_literal: true

module Jobs
  class BackupUploadToS3 < ::Jobs::Base
    sidekiq_options queue: 'low'

    def execute(args)
      upload = Upload.by_users.find_by(id: args[:upload_id])
      upload.backup_to_s3 if upload
    end
  end
end
