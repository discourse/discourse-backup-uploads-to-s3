module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if path = "#{Discourse.store.path_for(upload)}.gpg"
        s3_gnupg_public_key = GlobalSetting.backup_uploads_to_s3_gnupg_public_key
        tmp_path = "/tmp/#{File.basename(path)}"

        `echo '#{s3_gnupg_public_key}' | gpg --import`
        gnupg_user_id = `echo '#{s3_gnupg_public_key}' | gpg --list-keys --with-colons | awk -F: '/^pub:/ { print $5 }'`.chomp

        begin
          `gpg --encrypt --output #{tmp_path} --batch --yes --verbose --recipient #{gnupg_user_id} #{@path}`
          File.open(tmp_path) { |file| backup_upload(file, path, upload.id) }
        ensure
          File.delete(tmp_path)
        end
      end
    end

    def backup_upload(file, path, upload_id)
      path = DiscourseBackupUploadsToS3::Utils.s3_helper.upload(file, path)

      PluginStore.set(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload_id),
        "#{DiscourseBackupUploadsToS3::Utils.s3_store.absolute_base_url}/#{path}"
      )
    end
  end
end
