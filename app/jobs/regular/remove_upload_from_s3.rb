module Jobs
  class RemoveUploadFromS3 < Jobs::Base
    def execute(args)
      upload_id = check_args(args, :upload_id)
      path = check_args(args, :path)

      DiscourseBackupUploadsToS3::S3Helper.helper.remove(path, true)

      PluginStore.remove(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload_id)
      )
    end

    private

    def check_args(args, key)
      value = args[key]
      raise Discourse::InvalidParameters("upload path is not valid") unless value
      value
    end
  end
end
