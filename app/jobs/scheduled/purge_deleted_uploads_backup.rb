module Jobs
  class PurgeDeletedUploadsBackup < Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      DiscourseBackupUploadsToS3::Utils.s3_helper.update_tombstone_lifecycle(60)
    end
  end
end
