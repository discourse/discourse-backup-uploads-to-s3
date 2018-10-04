# name: discourse-backup-uploads-to-s3
# about: Backup uploads with encryption to a bucket on S3
# version: 0.0.1
# url: https://github.com/discourse/discourse-backup-uploads-to-s3

gem 'rbnacl', '3.4.0', require: false
gem 'rbnacl-libsodium', '1.0.10', require: false

after_initialize do
  load File.expand_path("../app/jobs/regular/backup_upload_to_s3.rb", __FILE__)
  load File.expand_path("../app/jobs/regular/remove_upload_from_s3.rb", __FILE__)
  load File.expand_path("../app/jobs/scheduled/backfill_uploads_backup.rb", __FILE__)
  load File.expand_path("../app/jobs/scheduled/purge_deleted_uploads_backup.rb", __FILE__)

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

      PLUGIN_STORE_KEY_PREFIX = 'backup-path-'.freeze

      def self.plugin_store_key(upload_id)
        "#{PLUGIN_STORE_KEY_PREFIX}#{upload_id}"
      end
    end
  end

  add_to_class(:s3_helper, :object) do |path|
    path = get_path_for_s3_upload(path)
    s3_bucket.object(path)
  end

  Upload.class_eval do
    scope :not_backuped, -> {
      joins(
        "LEFT JOIN plugin_store_rows
        ON plugin_store_rows.plugin_name = '#{DiscourseBackupUploadsToS3::PLUGIN_NAME}'
        AND CONCAT('#{DiscourseBackupUploadsToS3::Utils::PLUGIN_STORE_KEY_PREFIX}', uploads.id) = plugin_store_rows.key"
      )
        .where("plugin_store_rows.id IS NULL")
    }

    after_commit do
      if ::DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3? && saved_change_to_sha1?
        Jobs.enqueue(:backup_upload_to_s3, upload_id: self.id)
      end
    end

    after_destroy do
      if ::DiscourseBackupUploadsToS3::Utils.backup_uploads_to_s3?
        Jobs.enqueue(
          :remove_upload_from_s3,
          path: s3_backup_path,
          upload_id: self.id
        )
      end
    end

    def local_path
      @local_path ||= Discourse.store.path_for(self)
    end

    def compress_backup?
      @compress ||= begin
        if local_path.nil?
          false
        elsif FileHelper.respond_to?(:is_supported_image?)
          !FileHelper.is_supported_image?(File.basename(local_path))
        else
          !FileHelper.is_image?(File.basename(local_path))
        end
      end
    end

    def s3_backup_path
      "#{DiscourseBackupUploadsToS3::Utils.s3_store.get_path_for_upload(self)}#{compress_backup? ? '.gz' : ''}.enc"
    end

    def backup_to_s3
      DistributedMutex.synchronize("upload_backup_to_s3_#{self.id}") do
        if local_path && File.exist?(local_path)
          s3_helper = DiscourseBackupUploadsToS3::Utils.s3_helper

          path = s3_backup_path

          DiscourseBackupUploadsToS3::Utils.file_encryptor.encrypt(
            local_path, compress: compress_backup?
          ) do |tmp_path|

            path = s3_helper.upload(tmp_path, s3_backup_path)
          end

          PluginStore.set(
            DiscourseBackupUploadsToS3::PLUGIN_NAME,
            DiscourseBackupUploadsToS3::Utils.plugin_store_key(self.id),
            "#{s3_helper.s3_bucket_name}/#{path}"
          )
        end
      end
    end
  end
end
