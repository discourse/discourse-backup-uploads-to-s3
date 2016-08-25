module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if local_path = Discourse.store.path_for(upload)
        path = "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(upload)}.gz.enc"
        s3_helper = DiscourseBackupUploadsToS3::Utils.s3_helper

        DiscourseBackupUploadsToS3::Utils.file_encryptor.encrypt(local_path, compress: true) do |tmp_path|
          path = s3_helper.upload(tmp_path, path)
        end

        PluginStore.set(
          DiscourseBackupUploadsToS3::PLUGIN_NAME,
          DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
          "#{s3_helper.s3_bucket_name}/#{path}"
        )
      end
    end
  end
end
