# name: discourse-backup-uploads-to-s3
# about: Backup uploads with encryption to a bucket on S3
# version: 0.0.1

gem 'rbnacl', '3.4.0', { require: false }
gem 'rbnacl-libsodium', '1.0.10', { require: false }

after_initialize do
  load File.expand_path("../app/jobs/regular/backup_upload_to_s3.rb", __FILE__)
  load File.expand_path("../app/jobs/regular/remove_upload_from_s3.rb", __FILE__)

  require_dependency "s3_helper"
  require_dependency "file_store/s3_store"
  require 'rbnacl/libsodium'

  module ::DiscourseBackupUploadsToS3
    PLUGIN_NAME = 's3-backup-uploads'.freeze

    autoload :FileEncryptor, "#{Rails.root}/plugins/discourse-backup-uploads-to-s3/lib/file_encryptor"

    class Utils
      def self.file_encryptor
        DiscourseBackupUploadsToS3::FileEncryptor.new(
          GlobalSetting.backup_uploads_to_s3_encryption_key
        )
      end

      def self.s3_store
        FileStore::S3Store.new(s3_helper)
      end

      def self.s3_options
        {
          region: GlobalSetting.backup_uploads_to_s3_region,
          access_key_id: GlobalSetting.backup_uploads_to_s3_access_key_id,
          secret_access_key: GlobalSetting.backup_uploads_to_s3_secret_access_key
        }
      end

      def self.s3_helper
        ::S3Helper.new(
          backup_uploads_to_s3_bucket,
          ::FileStore::S3Store::TOMBSTONE_PREFIX,
          s3_options
        )
      end

      def self.backup_uploads_to_s3?
        @backup_uploads_to_s3 ||= begin
          GlobalSetting.try(:backup_uploads_to_s3_enabled) &&
          GlobalSetting.try(:backup_uploads_to_s3_bucket).presence &&
          GlobalSetting.try(:backup_uploads_to_s3_access_key_id).presence &&
          GlobalSetting.try(:backup_uploads_to_s3_secret_access_key).presence &&
          GlobalSetting.try(:backup_uploads_to_s3_region).presence &&
          GlobalSetting.try(:backup_uploads_to_s3_encryption_key).presence
        end
      end

      def self.backup_uploads_to_s3_bucket
        "#{GlobalSetting.backup_uploads_to_s3_bucket.downcase}/#{RailsMultisite::ConnectionManagement.current_db}"
      end

      def self.plugin_store_key(upload_id)
        "backup-path-#{upload_id}"
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
        Jobs.enqueue(
          :remove_upload_from_s3,
          path: ::DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(self),
          upload_id: self.id
        )
      end
    end
  end
end
