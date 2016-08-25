namespace "backup_uploads_to_s3" do
  desc "Backfill uploads that are missing from S3 backups"
  task "backfill" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting backfill of uploads backup to AWS S3. This may take awhile."

    job = Jobs::BackupUploadToS3.new
    pool = Concurrent::FixedThreadPool.new(ENV["RESTORE_THREAD_POOL_SIZE"] || 1)
    futures = []

    Upload.find_each do |upload|
      backup_url = PluginStore.get(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
      )

      if !backup_url
        futures << Concurrent::Future.new(executor: pool) do
          putc "."
          job.execute(upload_id: upload.id)
        end.execute
      end
    end

    futures.each(&:wait!)

    putc "\n"
    puts "Done!"
  end

  task "restore" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting restore of missing local uploads from AWS S3. This may take awhile."
    tmp_directory = Rails.root.join("tmp", "upload_restores")
    FileUtils.mkdir_p(tmp_directory)

    store = FileStore::LocalStore.new
    file_encryptor = DiscourseBackupUploadsToS3::Utils.file_encryptor
    resource = Aws::S3::Resource.new(DiscourseBackupUploadsToS3::Utils.s3_options)
    pool = Concurrent::FixedThreadPool.new(ENV["RESTORE_THREAD_POOL_SIZE"] || 1)
    futures = []

    avatar_upload_ids = UserAvatar.all.pluck(:custom_upload_id, :gravatar_upload_id).flatten.compact

    [
      Upload.where(id: avatar_upload_ids),
      Upload.where.not(id: avatar_upload_ids)
    ].each do |scope|
      scope.find_each do |upload|
        local_path = store.path_for(upload)

        if !File.exists?(local_path)
          backup_path = PluginStore.get(
            DiscourseBackupUploadsToS3::PLUGIN_NAME,
            DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id)
          )

          if backup_path
            bucket_name, file_path = backup_path.split("/", 2)

            futures << Concurrent::Future.new(executor: pool) do
              begin
                putc "."

                tmp_path = File.join(tmp_directory, File.basename(file_path))

                File.open(tmp_path, 'wb') do |file|
                  resource.bucket(bucket_name).object(file_path).get(response_target: file)
                end

                FileUtils.mkdir_p(File.dirname(local_path))
                file_encryptor.decrypt(tmp_path, local_path)
              rescue Aws::S3::Errors::NoSuchBucket
                puts "AWS S3 Bucket '#{bucket_name}' does not exist."
              rescue Aws::S3::Errors::NoSuchKey
                puts "File '#{file_path}' does not exists in AWS S3 Bucket '#{bucket_name}'."
              ensure
                File.delete(tmp_path) if File.exists?(tmp_path)
              end
            end.execute
          else
            puts "AWS S3 path for upload #{local_path} not found. Skipping..."
          end
        end
      end
    end

    futures.each(&:wait!)

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
