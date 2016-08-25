namespace "backup_uploads_to_s3" do
  desc "Backfill uploads that are missing from S3 backups"
  task "backfill" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting backfill of uploads backup to AWS S3. This may take awhile."

    job = Jobs::BackupUploadToS3.new

    Upload.order("created_at DESC").find_each do |upload|
      backup_url = PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
      )

      if !backup_url
        putc "."
        job.execute(upload_id: upload.id)
      end
    end
    putc "\n"
    puts "Done!"
  end

  task "restore" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting restore of missing local uploads from AWS S3. This may take awhile."

    store = FileStore::LocalStore.new
    file_encryptor = DiscourseBackupUploadsToS3::Utils.file_encryptor
    resource = Aws::S3::Resource.new(DiscourseBackupUploadsToS3::Utils.s3_options)

    Upload.order("created_at DESC").find_each do |upload|
      local_path = store.path_for(upload)

      if !File.exists?(local_path)
        backup_path = PluginStore.get(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
        )

        if backup_path
          bucket_name, file_path = backup_path.split("/", 2)

          begin
            putc "."
            tempfile = Tempfile.new
            resource.bucket(bucket_name).object(file_path).get(response_target: tempfile.path)
            FileUtils.mkdir_p(File.dirname(local_path))
            file_encryptor.decrypt(tempfile.path, local_path)
          rescue Aws::S3::Errors::NoSuchBucket
            puts "AWS S3 Bucket '#{bucket_name}' does not exist."
          rescue Aws::S3::Errors::NoSuchKey
            puts "File '#{file_path}' does not exists in AWS S3 Bucket '#{bucket_name}'."
          ensure
            tempfile.delete if tempfile
          end
        else
          puts "AWS S3 path for upload #{local_path} not found. Skipping..."
        end
      end
    end
    putc "\n"

    puts "Regenerating optimized images..."
    t = Rake::Task["uploads:regenerate_missing_optimized"]
    t.reenable
    t.invoke
  end

  task "multisite:restore" => :environment do
    RailsMultisite::ConnectionManagement.each_connection do |db|
      puts "Restoring #{db}"
      puts "---------------------------------\n"
      t = Rake::Task["backup_uploads_to_s3:restore"]
      t.reenable
      t.invoke
    end
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
