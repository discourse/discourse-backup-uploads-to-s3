module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if local_path = Discourse.store.path_for(upload)
        file_encryptor = DiscourseBackupUploadsToS3::FileEncryptor.new(
          GlobalSetting.backup_uploads_to_s3_secret_key
        )

        path = "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(upload)}.enc"

        file_encryptor.encrypt(local_path) do |enc_file|
          path = DiscourseBackupUploadsToS3::Utils.s3_helper.upload(enc_file, path)
        end

        PluginStore.set(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
          "#{DiscourseBackupUploadsToS3::Utils.s3_store.absolute_base_url}/#{path}"
        )
      end
    end
  end
end
