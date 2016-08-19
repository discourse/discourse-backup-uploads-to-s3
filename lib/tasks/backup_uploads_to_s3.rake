namespace "backup_uploads_to_s3" do
  desc "Backfill uploads that are missing from S3 backups"
  task "backfill" => :environment do
    puts RailsMultisite::ConnectionManagement.current_db
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

    puts "Done!"
  end

  task "multisite:backfill" => :environment do
    RailsMultisite::ConnectionManagement.each_connection do |db|
      puts "Backfilling #{db}"
      puts "---------------------------------\n"
      t = Rake::Task["backup_uploads_to_s3:backfill"]
      t.reenable
      t.invoke
    end
  end

  desc "Generate secret key for encryption"
  task "generate_secret_key" => :environment do
    puts Base64.encode64(RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes))
  end
end
