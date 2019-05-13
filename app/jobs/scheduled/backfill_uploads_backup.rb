# frozen_string_literal: true

module Jobs
  class BackfillUploadsBackup < Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      Upload.by_users.not_backuped.find_each { |upload| upload.backup_to_s3 }
    end
  end
end
