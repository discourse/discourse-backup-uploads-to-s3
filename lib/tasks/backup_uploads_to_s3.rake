namespace "backup_uploads_to_s3" do
  desc "Backfill uploads that are missing from S3 backups"
  task "backfill" => :environment do
    if !DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
      puts "Plugin is not enabled."
      exit
    end

    puts "Starting backfill of uploads backup to AWS S3. This may take awhile."

    s3_helper = DiscourseBackupUploadsToS3::Utils.s3_helper

    Upload.find_each do |upload|
      path = "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(upload)}.gz.enc"
      object = s3_helper.object(path)
      next if object.exists? && object.content_length != 0
      upload.backup_to_s3
      putc "."
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

        if local_path && !File.exists?(local_path)
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
        else
          puts "Upload does not have a local path. Skipping..."
        end
      end
    end

    futures.each(&:wait!)
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

  desc "Recover missing uploads from the backup on S3"
  task "recover_missing_uploads" => :environment do
    RailsMultisite::ConnectionManagement.each_connection do |db|
      puts "Recoverying #{db}"
      puts "---------------------------------\n"

      object_keys = begin
        s3_helper = DiscourseBackupUploadsToS3::Utils.s3_helper

        s3_helper.list("original").map(&:key).concat(
          s3_helper.list("#{FileStore::S3Store::TOMBSTONE_PREFIX}original").map(&:key)
        )
      end

      Post.where("raw LIKE '%upload:\/\/%' OR raw LIKE '%href=%'").find_each do |post|
        analyzer = PostAnalyzer.new(post.raw, post.topic_id)
        file_encryptor = DiscourseBackupUploadsToS3::Utils.file_encryptor

        analyzer.cooked_stripped.css("a", "img").each do |media|
          sha1 =
            if media.name == "a"
              if href = media["href"] && data = Upload.extract_upload_url(href)
                data[2]
              end
            elsif media.name == 'img'
              if dom_class = media["class"] &&
                 (Post.white_listed_image_classes & dom_class.split).count > 0

                next
              end

              if orig_src = media["data-orig-src"]
                Upload.sha1_from_short_url(orig_src)
              end
            end

          if sha1 && sha1.length == Upload::SHA1_LENGTH
            unless upload = Upload.find_by(sha1: sha1)
              object_keys.each do |key|
                if key =~ /#{sha1}/
                  puts "#{post.full_url} restoring #{key}"

                  tmp_directory = Rails.root.join("tmp", "upload_restores")
                  FileUtils.mkdir_p(tmp_directory)
                  tmp_path = File.join(tmp_directory, File.basename(key))

                  File.open(tmp_path, 'wb') do |file|
                    Aws::S3::Resource.new(DiscourseBackupUploadsToS3::Utils.s3_options)
                      .bucket(GlobalSetting.backup_uploads_to_s3_bucket.downcase)
                      .object(key)
                      .get(response_target: file)
                  end

                  key = key.sub(".gz.enc", "")
                  key = key.sub(".enc", "")

                  new_path = Rails.root.join(
                    "public",
                    "uploads",
                    "tombstone",
                    key
                  )

                  file_encryptor.decrypt(tmp_path, new_path)

                  if File.size(new_path) == 0
                    puts "File is empty #{new_path}"
                    File.delete(new_path)
                  end
                end
              end
            end
          end
        end
      rescue MiniRacer::ScriptTerminatedError, MiniRacer::RuntimeError => e
        puts "#{e.class} #{post.full_url}"
      end
    end
  end
end
