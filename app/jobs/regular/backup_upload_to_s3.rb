require_dependency 'file_store/s3_store'

module Jobs
  class BackupUploadToS3 < Jobs::Base
    def execute(args)
      upload = Upload.find(args[:upload_id])

      if path = Discourse.store.path_for(upload)
        store = ::FileStore::S3Store.new(DiscourseBackupUploadsToS3::S3Helper.helper)

        File.open(path) do |file|
          backup_url = store.store_upload(file, upload)

          PluginStore.set(
            DiscourseBackupUploadsToS3::PLUGIN_NAME,
            DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload.id),
            backup_url
          )
        end
      end
    end
  end
end
