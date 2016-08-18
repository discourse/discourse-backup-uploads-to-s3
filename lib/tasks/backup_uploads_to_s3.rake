namespace "backup_uploads_to_s3" do
  desc "Backfill uploads that are missing from S3 backups"
  task "backfill" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting backfill of uploads backup to AWS S3. This may take awhile."

    Upload.find_each do |upload|
      backup_url = PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
      )

      if !backup_url
        printf "."
        Jobs.enqueue(:backup_upload_to_s3, upload_id: upload.id)
      end
    end

    puts ""
  end

  desc "Generate secret key for encryption"
  task "generate_secret_key" => :environment do
    puts Base64.encode64(RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes))
  end
end
