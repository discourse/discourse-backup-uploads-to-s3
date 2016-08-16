require_dependency 'file_store/s3_store'

module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if path = Discourse.store.path_for(upload)
        store = ::DiscourseBackupUploadsToS3::Utils.s3_store
        File.open(path) { |file| backup_upload(store, file, upload) }
      end
    end

    def backup_upload(store, file, upload)
      backup_url = store.store_upload(file, upload)

      PluginStore.set(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
        backup_url
      )
    end
  end
end
