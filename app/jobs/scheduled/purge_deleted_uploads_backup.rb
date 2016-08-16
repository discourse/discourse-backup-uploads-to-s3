module Jobs
  class PurgeDeletedUploadsBackup < Jobs::Scheduled
    every 1.day

    def execute(args)
      DiscourseBackupUploadsToS3::Utils.s3_helper.update_tombstone_lifecycle(60)
    end
  end
end
