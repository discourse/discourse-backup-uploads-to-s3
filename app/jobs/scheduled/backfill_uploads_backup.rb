module Jobs
  class BackfillUploadsBackup < Jobs::Scheduled
    every 1.hour

    def execute(args)
      Upload.not_backuped.limit(5000).find_each { |upload| upload.backup_to_s3 }
    end
  end
end
