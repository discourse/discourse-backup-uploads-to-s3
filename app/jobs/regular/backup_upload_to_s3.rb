module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if local_path = Discourse.store.path_for(upload)
        s3_gnupg_public_key = GlobalSetting.backup_uploads_to_s3_gnupg_public_key
        encrypted_filename = "#{File.basename(local_path)}.gpg"
        tmp_path = "/tmp/#{encrypted_filename}"

        `echo '#{s3_gnupg_public_key}' | gpg --import`
        gnupg_user_id = `gpg --list-keys --with-colons | awk -F: '/^pub:/ { print $5 }'`.chomp

        begin
          `gpg --encrypt --output #{tmp_path} --batch --yes --verbose --recipient #{gnupg_user_id} #{local_path}`
          File.open(tmp_path) { |file| backup_upload(file, upload) }
        ensure
          File.delete(tmp_path) if File.exists?(tmp_path)
        end
      end
    end

    def backup_upload(file, upload)
      path = "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(upload)}.gpg"
      path = DiscourseBackupUploadsToS3::Utils.s3_helper.upload(file, path)

      PluginStore.set(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
        "#{DiscourseBackupUploadsToS3::Utils.s3_store.absolute_base_url}/#{path}"
      )
    end
  end
end
