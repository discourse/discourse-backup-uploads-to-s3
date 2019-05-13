# frozen_string_literal: true

module Jobs
  class RemoveUploadFromS3 < Jobs::Base
    sidekiq_options queue: 'low'

    def execute(args)
      upload_id = check_args(args, :upload_id)
      path = check_args(args, :path)

      DiscourseBackupUploadsToS3::Utils.s3_helper.remove(path, true)

      PluginStore.remove(
        DiscourseBackupUploadsToS3::PLUGIN_NAME,
        DiscourseBackupUploadsToS3::Utils.plugin_store_key(upload_id)
      )
    end

    private

    def check_args(args, key)
      value = args[key]
      raise Discourse::InvalidParameters.new("argument #{key} is not valid") unless value
      value
    end
  end
end
