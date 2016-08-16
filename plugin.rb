# name: discourse-backup-uploads-to-s3
# about: Backup uploads with encryption to a bucket on S3
# version: 0.0.1

after_initialize do
  load File.expand_path("../app/jobs/regular/backup_upload_to_s3.rb", __FILE__)
  load File.expand_path("../app/jobs/regular/remove_upload_from_s3.rb", __FILE__)

  module ::DiscourseBackupUploadsToS3
    PLUGIN_NAME = 's3-backup-uploads'.freeze

    class Utils
      def self.s3_store
        FileStore::S3Store.new(s3_helper, GlobalSetting.backup_uploads_to_s3_bucket)
      end

      def self.s3_helper
        options = {
          region: GlobalSetting.backup_uploads_to_s3_region,
          access_key_id: GlobalSetting.backup_uploads_to_s3_access_key_id,
          secret_access_key: GlobalSetting.backup_uploads_to_s3_secret_access_key
        }

        ::S3Helper.new(
          GlobalSetting.backup_uploads_to_s3_bucket.downcase,
          ::FileStore::S3Store::TOMBSTONE_PREFIX,
          options
        )
      end

      def self.backup_uploads_to_s3?
        GlobalSetting.respond_to?(:backup_uploads_to_s3_enabled) && GlobalSetting.backup_uploads_to_s3_enabled &&
        GlobalSetting.respond_to?(:backup_uploads_to_s3_bucket) && !GlobalSetting.backup_uploads_to_s3_bucket.blank? &&
        GlobalSetting.respond_to?(:backup_uploads_to_s3_access_key_id) && !GlobalSetting.backup_uploads_to_s3_access_key_id.blank? &&
        GlobalSetting.respond_to?(:backup_uploads_to_s3_secret_access_key) && !GlobalSetting.backup_uploads_to_s3_secret_access_key.blank? &&
        GlobalSetting.respond_to?(:backup_uploads_to_s3_region) && !GlobalSetting.backup_uploads_to_s3_region.blank?
      end

      def self.plugin_store_key(upload_id)
        "backup-url-#{upload_id}"
      end
    end
  end

  Upload.class_eval do
    after_commit do
      if ::DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
        Jobs.enqueue(:backup_upload_to_s3, upload_id: self.id)
      end
    end

    after_destroy do
      if ::DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
        s3_helper = ::DiscourseBackupUploadsToS3::Utils.s3_helper

        Jobs.enqueue(
          :remove_upload_from_s3,
          path: ::DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(self),
          upload_id: self.id
        )
      end
    end
  end
end
